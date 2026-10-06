import 'announced_service.dart';

class DiscoveryObservation {
  final DiscoveryProtocol protocol;
  final String? ip;
  final String? hostname;
  final String? announcedName;
  final String? serviceType;
  final int? port;
  final String? stableId;
  final Map<String, String> metadata;
  final Duration ttl;
  final DateTime observedAt;

  DiscoveryObservation({
    required this.protocol,
    this.ip,
    this.hostname,
    this.announcedName,
    this.serviceType,
    this.port,
    this.stableId,
    Map<String, String> metadata = const {},
    this.ttl = const Duration(seconds: 120),
    DateTime? observedAt,
  }) : metadata = Map.unmodifiable(metadata),
       observedAt = observedAt ?? DateTime.now();

  Set<String> get identityKeys {
    final keys = <String>{};
    _addIdentity(keys, 'id', stableId);
    _addIdentity(keys, 'ip', ip);
    _addIdentity(keys, 'host', hostname);
    _addIdentity(keys, 'name', announcedName);
    return keys;
  }

  AnnouncedService? toAnnouncedService() {
    final type = serviceType;
    final name = announcedName;
    if (type == null || name == null) {
      return null;
    }

    return AnnouncedService(
      protocol: protocol,
      serviceType: type,
      instanceName: name,
      hostname: hostname,
      port: port,
      addresses: ip == null ? const [] : [ip!],
      metadata: metadata,
      ttl: ttl,
      observedAt: observedAt,
    );
  }

  static void _addIdentity(Set<String> keys, String prefix, String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized != null && normalized.isNotEmpty) {
      keys.add('$prefix:$normalized');
    }
  }
}
