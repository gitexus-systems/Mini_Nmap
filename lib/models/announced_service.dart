enum DiscoveryProtocol { mdns, ssdp, upnp, other }

extension DiscoveryProtocolLabel on DiscoveryProtocol {
  String get label {
    switch (this) {
      case DiscoveryProtocol.mdns:
        return 'mDNS';
      case DiscoveryProtocol.ssdp:
        return 'SSDP';
      case DiscoveryProtocol.upnp:
        return 'UPnP';
      case DiscoveryProtocol.other:
        return 'Otro';
    }
  }
}

class AnnouncedService {
  final DiscoveryProtocol protocol;
  final String serviceType;
  final String instanceName;
  final String? hostname;
  final int? port;
  final List<String> addresses;
  final Map<String, String> metadata;
  final Duration ttl;
  final DateTime observedAt;

  AnnouncedService({
    required this.protocol,
    required this.serviceType,
    required this.instanceName,
    this.hostname,
    this.port,
    Iterable<String> addresses = const [],
    Map<String, String> metadata = const {},
    this.ttl = const Duration(seconds: 120),
    DateTime? observedAt,
  }) : addresses = List.unmodifiable(addresses.toSet()),
       metadata = Map.unmodifiable(metadata),
       observedAt = observedAt ?? DateTime.now();

  String get identity =>
      '${protocol.name}|${serviceType.toLowerCase()}|'
      '${instanceName.toLowerCase()}';

  bool get isExpired => DateTime.now().isAfter(observedAt.add(ttl));

  AnnouncedService merge(AnnouncedService newer) {
    if (identity != newer.identity) {
      throw ArgumentError('Only identical announced services can be merged.');
    }

    return AnnouncedService(
      protocol: protocol,
      serviceType: newer.serviceType,
      instanceName: newer.instanceName,
      hostname: newer.hostname ?? hostname,
      port: newer.port ?? port,
      addresses: {...addresses, ...newer.addresses},
      metadata: {...metadata, ...newer.metadata},
      ttl: newer.ttl,
      observedAt: newer.observedAt,
    );
  }
}
