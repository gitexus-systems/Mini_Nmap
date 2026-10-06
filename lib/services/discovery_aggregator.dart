import '../models/discovered_device.dart';
import '../models/discovery_observation.dart';

class DiscoveryAggregator {
  final List<DiscoveredDevice> _devices = [];

  List<DiscoveredDevice> get devices => List.unmodifiable(_devices);

  DiscoveredDevice add(DiscoveryObservation observation) {
    final matches = _devices
        .where((device) => device.matches(observation))
        .toList();

    if (matches.isEmpty) {
      final device = DiscoveredDevice.fromObservation(observation);
      _devices.add(device);
      return device;
    }

    final target = matches.first;
    target.add(observation);
    for (final duplicate in matches.skip(1)) {
      target.absorb(duplicate);
      _devices.remove(duplicate);
    }
    return target;
  }
}
