import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mini_nmap/services/mdns_discovery_provider.dart';
import 'package:mini_nmap/services/mdns_packet.dart';
import 'package:mini_nmap/services/mdns_transport.dart';

class _ControlledMdnsTransport implements MdnsTransport {
  final StreamController<List<int>> controller =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentPackets = [];
  bool started = false;
  bool closed = false;

  @override
  Stream<List<int>> get packets => controller.stream;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  void send(List<int> packet) {
    sentPackets.add(packet);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  test('query encoder creates a DNS PTR question', () {
    final packet = const MdnsQueryEncoder().query([
      ('_googlecast._tcp.local', 12),
    ]);

    expect(packet.take(2), [0, 0]);
    expect(packet[4], 0);
    expect(packet[5], 1);
    expect(packet, containsAllInOrder('_googlecast'.codeUnits));
    expect(packet.sublist(packet.length - 4), [0, 12, 0, 1]);
  });

  test('packet parser extracts PTR, SRV, TXT and IPv4 records', () {
    final records = const MdnsPacketParser().parse(_mdnsResponse());

    expect(records, hasLength(4));
    expect((records[0].data as MdnsNameData).name, _instance);
    final srv = records[1].data as MdnsSrvData;
    expect(srv.target, _hostname);
    expect(srv.port, 8009);
    expect(
      (records[2].data as MdnsTxtData).values,
      containsPair('model', 'Chromecast'),
    );
    expect((records[3].data as MdnsAddressData).address, '192.168.1.40');
  });

  test('mDNS provider emits observations from controlled datagrams', () async {
    final transport = _ControlledMdnsTransport();
    final provider = MdnsDiscoveryProvider(transportFactory: () => transport);
    final observations = provider
        .discover(timeout: const Duration(milliseconds: 30))
        .toList();

    await Future<void>.delayed(Duration.zero);
    transport.controller.add(_mdnsResponse());
    final result = await observations;

    expect(transport.started, isTrue);
    expect(transport.sentPackets, isNotEmpty);
    expect(transport.closed, isTrue);
    expect(result, isNotEmpty);
    final observation = result.last;
    expect(observation.ip, '192.168.1.40');
    expect(observation.hostname, _hostname);
    expect(observation.announcedName, 'Living Room');
    expect(observation.serviceType, _serviceType);
    expect(observation.port, 8009);
    expect(observation.metadata['model'], 'Chromecast');
  });

  test(
    'mDNS provider ignores malformed datagrams and supports cancel',
    () async {
      final transport = _ControlledMdnsTransport();
      final provider = MdnsDiscoveryProvider(transportFactory: () => transport);
      final observations = provider
          .discover(timeout: const Duration(seconds: 1))
          .toList();

      await Future<void>.delayed(Duration.zero);
      transport.controller.add([0, 1, 2]);
      await provider.cancel();

      expect(await observations, isEmpty);
      expect(transport.closed, isTrue);
    },
  );
}

const String _serviceType = '_googlecast._tcp.local';
const String _instance = 'Living Room._googlecast._tcp.local';
const String _hostname = 'living-room.local';

List<int> _mdnsResponse() {
  final packet = <int>[0, 0, 0x84, 0, 0, 0, 0, 4, 0, 0, 0, 0];
  _addRecord(packet, _serviceType, 12, _name(_instance));
  _addRecord(packet, _instance, 33, [
    0,
    0,
    0,
    0,
    0x1f,
    0x49,
    ..._name(_hostname),
  ]);
  final txt = 'model=Chromecast'.codeUnits;
  _addRecord(packet, _instance, 16, [txt.length, ...txt]);
  _addRecord(packet, _hostname, 1, [192, 168, 1, 40]);
  return packet;
}

void _addRecord(List<int> packet, String name, int type, List<int> data) {
  packet
    ..addAll(_name(name))
    ..addAll([type >> 8, type & 0xff])
    ..addAll([0, 1])
    ..addAll([0, 0, 0, 120])
    ..addAll([data.length >> 8, data.length & 0xff])
    ..addAll(data);
}

List<int> _name(String name) {
  final result = <int>[];
  for (final label in name.split('.')) {
    result
      ..add(label.length)
      ..addAll(label.codeUnits);
  }
  result.add(0);
  return result;
}
