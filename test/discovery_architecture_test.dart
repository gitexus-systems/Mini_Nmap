import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mini_nmap/models/announced_service.dart';
import 'package:mini_nmap/models/discovery_observation.dart';
import 'package:mini_nmap/services/advanced_discovery_coordinator.dart';
import 'package:mini_nmap/services/discovery_aggregator.dart';
import 'package:mini_nmap/services/discovery_provider.dart';

class _FakeProvider implements DiscoveryProvider {
  final String providerId;
  final StreamController<DiscoveryObservation> controller =
      StreamController<DiscoveryObservation>();
  bool wasCancelled = false;
  Duration? requestedTimeout;

  _FakeProvider(this.providerId);

  @override
  String get id => providerId;

  @override
  Stream<DiscoveryObservation> discover({required Duration timeout}) {
    requestedTimeout = timeout;
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    wasCancelled = true;
    if (!controller.isClosed) await controller.close();
  }

  @override
  Future<void> dispose() => cancel();
}

DiscoveryObservation _observation({
  String? ip = '192.168.1.40',
  String? hostname = 'living-room.local',
  String name = 'Living Room',
  String serviceType = '_googlecast._tcp.local',
  Map<String, String> metadata = const {'model': 'Chromecast'},
}) {
  return DiscoveryObservation(
    protocol: DiscoveryProtocol.mdns,
    ip: ip,
    hostname: hostname,
    announcedName: name,
    serviceType: serviceType,
    port: 8009,
    metadata: metadata,
    ttl: const Duration(seconds: 120),
  );
}

void main() {
  test('DiscoveryObservation creates a structured announced service', () {
    final observation = _observation();
    final service = observation.toAnnouncedService();

    expect(observation.identityKeys, contains('ip:192.168.1.40'));
    expect(observation.identityKeys, contains('host:living-room.local'));
    expect(service, isNotNull);
    expect(service!.protocol, DiscoveryProtocol.mdns);
    expect(service.instanceName, 'Living Room');
    expect(service.port, 8009);
    expect(service.metadata['model'], 'Chromecast');
  });

  test('announced services preserve TTL and expose expiration', () {
    final service = AnnouncedService(
      protocol: DiscoveryProtocol.mdns,
      serviceType: '_http._tcp.local',
      instanceName: 'Expired service',
      ttl: const Duration(seconds: 1),
      observedAt: DateTime.now().subtract(const Duration(seconds: 2)),
    );

    expect(service.isExpired, isTrue);
  });

  test('aggregator merges multiple observations for the same device', () {
    final aggregator = DiscoveryAggregator();
    aggregator.add(_observation());
    aggregator.add(
      _observation(name: 'Living Room Web', serviceType: '_http._tcp.local'),
    );

    expect(aggregator.devices, hasLength(1));
    expect(aggregator.devices.single.observations, hasLength(2));
    expect(aggregator.devices.single.announcedServices, hasLength(2));
  });

  test('aggregator keeps unrelated observations as separate devices', () {
    final aggregator = DiscoveryAggregator();
    aggregator.add(_observation());
    aggregator.add(
      _observation(
        ip: '192.168.1.41',
        hostname: 'printer.local',
        name: 'Office Printer',
        serviceType: '_ipp._tcp.local',
      ),
    );

    expect(aggregator.devices, hasLength(2));
  });

  test('coordinator combines providers and forwards timeout', () async {
    final first = _FakeProvider('first');
    final second = _FakeProvider('second');
    final coordinator = AdvancedDiscoveryCoordinator(
      providers: [first, second],
    );
    final operation = coordinator.discover(timeout: const Duration(seconds: 1));

    first.controller.add(_observation());
    second.controller.add(
      _observation(name: 'Living Room Web', serviceType: '_http._tcp.local'),
    );
    await first.controller.close();
    await second.controller.close();

    final result = await operation;
    expect(result.devices, hasLength(1));
    expect(result.devices.single.announcedServices, hasLength(2));
    expect(result.errors, isEmpty);
    expect(result.timedOut, isFalse);
    expect(first.requestedTimeout, const Duration(seconds: 1));
  });

  test('coordinator reports provider errors without losing results', () async {
    final provider = _FakeProvider('broken');
    final coordinator = AdvancedDiscoveryCoordinator(providers: [provider]);
    final operation = coordinator.discover(timeout: const Duration(seconds: 1));

    provider.controller.add(_observation());
    provider.controller.addError(StateError('network failed'));
    await provider.controller.close();

    final result = await operation;
    expect(result.devices, hasLength(1));
    expect(result.errors['broken'], isA<StateError>());
  });

  test('coordinator enforces timeout and cancels providers', () async {
    final provider = _FakeProvider('slow');
    final coordinator = AdvancedDiscoveryCoordinator(providers: [provider]);

    final result = await coordinator.discover(
      timeout: const Duration(milliseconds: 20),
    );

    expect(result.timedOut, isTrue);
    expect(result.cancelled, isFalse);
    expect(provider.wasCancelled, isTrue);
  });

  test('an active discovery operation can be cancelled', () async {
    final provider = _FakeProvider('active');
    final coordinator = AdvancedDiscoveryCoordinator(providers: [provider]);
    final operation = coordinator.discover(timeout: const Duration(seconds: 5));

    await Future<void>.delayed(Duration.zero);
    await coordinator.cancel();
    final result = await operation;

    expect(result.cancelled, isTrue);
    expect(result.timedOut, isFalse);
    expect(provider.wasCancelled, isTrue);
  });
}
