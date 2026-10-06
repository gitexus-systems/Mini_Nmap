import '../models/discovery_observation.dart';

abstract interface class DiscoveryProvider {
  String get id;

  Stream<DiscoveryObservation> discover({required Duration timeout});

  Future<void> cancel();

  Future<void> dispose();
}
