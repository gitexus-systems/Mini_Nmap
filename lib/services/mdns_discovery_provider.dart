import 'dart:async';

import '../models/announced_service.dart';
import '../models/discovery_observation.dart';
import 'discovery_provider.dart';
import 'mdns_packet.dart';
import 'mdns_transport.dart';

typedef MdnsTransportFactory = MdnsTransport Function();

class MdnsDiscoveryProvider implements DiscoveryProvider {
  static const String serviceEnumeration = '_services._dns-sd._udp.local';
  static const List<String> commonServiceTypes = [
    '_googlecast._tcp.local',
    '_airplay._tcp.local',
    '_raop._tcp.local',
    '_http._tcp.local',
    '_https._tcp.local',
    '_ipp._tcp.local',
    '_ipps._tcp.local',
    '_printer._tcp.local',
    '_device-info._tcp.local',
    '_workstation._tcp.local',
  ];

  final MdnsTransportFactory transportFactory;
  final MdnsPacketParser parser;
  final MdnsQueryEncoder queryEncoder;

  MdnsTransport? _transport;
  StreamSubscription<List<int>>? _packetSubscription;
  Timer? _timeoutTimer;
  StreamController<DiscoveryObservation>? _controller;
  final Map<String, String> _serviceTypeByInstance = {};
  final Map<String, MdnsSrvData> _srvByInstance = {};
  final Map<String, Map<String, String>> _txtByInstance = {};
  final Map<String, Set<String>> _addressesByHostname = {};
  final Map<String, Duration> _ttlByInstance = {};
  final Set<String> _queriesSent = {};
  final Map<String, String> _lastEmission = {};

  MdnsDiscoveryProvider({
    MdnsTransportFactory? transportFactory,
    this.parser = const MdnsPacketParser(),
    this.queryEncoder = const MdnsQueryEncoder(),
  }) : transportFactory = transportFactory ?? UdpMdnsTransport.new;

  @override
  String get id => 'mdns';

  @override
  Stream<DiscoveryObservation> discover({required Duration timeout}) {
    if (_controller != null) {
      throw StateError('mDNS discovery is already running.');
    }

    final controller = StreamController<DiscoveryObservation>();
    _controller = controller;
    controller.onListen = () => _start(timeout);
    controller.onCancel = cancel;
    return controller.stream;
  }

  Future<void> _start(Duration timeout) async {
    _resetCaches();
    final transport = transportFactory();
    _transport = transport;
    try {
      await transport.start();
      _packetSubscription = transport.packets.listen(
        _handlePacket,
        onError: (Object error, StackTrace stackTrace) {
          _controller?.addError(error, stackTrace);
        },
      );
      _query(serviceEnumeration, 12);
      for (final serviceType in commonServiceTypes) {
        _query(serviceType, 12);
      }
      _timeoutTimer = Timer(timeout, _finish);
    } catch (error, stackTrace) {
      _controller?.addError(error, stackTrace);
      await _finish();
    }
  }

  void _handlePacket(List<int> packet) {
    List<MdnsRecord> records;
    try {
      records = parser.parse(packet);
    } on FormatException {
      return;
    }

    for (final record in records) {
      final data = record.data;
      if (record.type == 12 && data is MdnsNameData) {
        if (_sameName(record.name, serviceEnumeration)) {
          _query(data.name, 12);
        } else {
          _serviceTypeByInstance[data.name] = record.name;
          _ttlByInstance[data.name] = record.ttl;
          _query(data.name, 33);
          _query(data.name, 16);
        }
      } else if (record.type == 33 && data is MdnsSrvData) {
        _srvByInstance[record.name] = data;
        _ttlByInstance[record.name] = record.ttl;
        _query(data.target, 1);
        _query(data.target, 28);
      } else if (record.type == 16 && data is MdnsTxtData) {
        _txtByInstance[record.name] = data.values;
      } else if ((record.type == 1 || record.type == 28) &&
          data is MdnsAddressData) {
        _addressesByHostname
            .putIfAbsent(record.name, () => <String>{})
            .add(data.address);
      }
    }

    for (final instance in _serviceTypeByInstance.keys) {
      _emitObservation(instance);
    }
  }

  void _emitObservation(String instance) {
    final type = _serviceTypeByInstance[instance];
    final srv = _srvByInstance[instance];
    if (type == null || srv == null) return;
    final addresses = _addressesByHostname[srv.target] ?? const <String>{};
    final metadata = _txtByInstance[instance] ?? const <String, String>{};
    final announcedName = _instanceDisplayName(instance, type);
    final ttl = _ttlByInstance[instance] ?? const Duration(seconds: 120);
    if (ttl <= Duration.zero) return;

    final Iterable<String?> addressCandidates = addresses.isEmpty
        ? const [null]
        : addresses;
    for (final ip in addressCandidates) {
      final signature =
          '$ip|${srv.target}|${srv.port}|${metadata.entries.join('&')}';
      final emissionKey = '$instance|$ip';
      if (_lastEmission[emissionKey] == signature) continue;
      _lastEmission[emissionKey] = signature;

      _controller?.add(
        DiscoveryObservation(
          protocol: DiscoveryProtocol.mdns,
          ip: ip,
          hostname: srv.target,
          announcedName: announcedName,
          serviceType: type,
          port: srv.port,
          stableId: metadata['id'] ?? metadata['uuid'],
          metadata: metadata,
          ttl: ttl,
        ),
      );
    }
  }

  void _query(String name, int type) {
    final key = '${name.toLowerCase()}|$type';
    if (!_queriesSent.add(key)) return;
    _transport?.send(queryEncoder.query([(name, type)]));
  }

  bool _sameName(String first, String second) =>
      first.toLowerCase() == second.toLowerCase();

  String _instanceDisplayName(String instance, String serviceType) {
    final suffix = '.${serviceType.toLowerCase()}';
    if (instance.toLowerCase().endsWith(suffix)) {
      return instance.substring(0, instance.length - suffix.length);
    }
    return instance;
  }

  void _resetCaches() {
    _serviceTypeByInstance.clear();
    _srvByInstance.clear();
    _txtByInstance.clear();
    _addressesByHostname.clear();
    _ttlByInstance.clear();
    _queriesSent.clear();
    _lastEmission.clear();
  }

  Future<void> _finish() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final subscription = _packetSubscription;
    _packetSubscription = null;
    await subscription?.cancel();
    final transport = _transport;
    _transport = null;
    await transport?.close();
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  @override
  Future<void> cancel() => _finish();

  @override
  Future<void> dispose() => _finish();
}
