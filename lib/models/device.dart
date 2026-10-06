import 'package:flutter/material.dart';
import 'announced_service.dart';
import 'discovery_observation.dart';

class Device {
  final String ip;
  final String hostname;
  final String deviceType;
  final String detectionMethod;
  final IconData icon;

  // Port scan fields (lazy loaded)
  List<int> openPorts;
  Map<int, String> detectedServices;
  bool isPortScanCompleted;

  // Announced network services (mDNS in v5.2, extensible to future providers)
  List<AnnouncedService> announcedServices;
  Set<DiscoveryProtocol> discoveryProtocols;
  bool isAdvancedDiscoveryCompleted;

  Device({
    required this.ip,
    required this.hostname,
    required this.deviceType,
    required this.detectionMethod,
    required this.icon,
    List<int>? openPorts,
    Map<int, String>? detectedServices,
    this.isPortScanCompleted = false,
    List<AnnouncedService>? announcedServices,
    Set<DiscoveryProtocol>? discoveryProtocols,
    this.isAdvancedDiscoveryCompleted = false,
  }) : openPorts = openPorts ?? [],
       detectedServices = detectedServices ?? {},
       announcedServices = announcedServices ?? [],
       discoveryProtocols = discoveryProtocols ?? {};

  void mergeDiscoveryObservation(DiscoveryObservation observation) {
    discoveryProtocols.add(observation.protocol);
    final service = observation.toAnnouncedService();
    if (service == null) return;

    final index = announcedServices.indexWhere(
      (existing) => existing.identity == service.identity,
    );
    if (index < 0) {
      announcedServices.add(service);
    } else {
      announcedServices[index] = announcedServices[index].merge(service);
    }
  }

  bool get hasExpiredAnnouncedServices =>
      announcedServices.any((service) => service.isExpired);

  void pruneExpiredAnnouncedServices() {
    announcedServices.removeWhere((service) => service.isExpired);
  }
}
