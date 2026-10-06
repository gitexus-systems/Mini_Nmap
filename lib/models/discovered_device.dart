import 'announced_service.dart';
import 'discovery_observation.dart';

class DiscoveredDevice {
  final List<DiscoveryObservation> observations;
  final Set<String> identityKeys;
  final Set<String> addresses;
  final Set<String> hostnames;
  final Map<String, AnnouncedService> _services;

  DiscoveredDevice._({
    required this.observations,
    required this.identityKeys,
    required this.addresses,
    required this.hostnames,
    required this._services,
  });

  factory DiscoveredDevice.fromObservation(DiscoveryObservation observation) {
    final service = observation.toAnnouncedService();
    final services = <String, AnnouncedService>{};
    if (service != null) {
      services[service.identity] = service;
    }
    return DiscoveredDevice._(
      observations: [observation],
      identityKeys: {...observation.identityKeys},
      addresses: {?observation.ip},
      hostnames: {?observation.hostname},
      services: services,
    );
  }

  List<AnnouncedService> get announcedServices =>
      List.unmodifiable(_services.values);

  bool matches(DiscoveryObservation observation) =>
      identityKeys.intersection(observation.identityKeys).isNotEmpty;

  void add(DiscoveryObservation observation) {
    observations.add(observation);
    identityKeys.addAll(observation.identityKeys);
    if (observation.ip != null) {
      addresses.add(observation.ip!);
    }
    if (observation.hostname != null) {
      hostnames.add(observation.hostname!);
    }

    final service = observation.toAnnouncedService();
    if (service != null) {
      _services.update(
        service.identity,
        (existing) => existing.merge(service),
        ifAbsent: () => service,
      );
    }
  }

  void absorb(DiscoveredDevice other) {
    for (final observation in other.observations) {
      add(observation);
    }
  }
}
