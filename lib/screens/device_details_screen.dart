import 'dart:async';

import 'package:flutter/material.dart';
import '../models/announced_service.dart';
import '../models/device.dart';
import '../services/advanced_discovery_coordinator.dart';
import '../services/mdns_discovery_provider.dart';
import '../services/port_scanner_service.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final Device device;
  final PortScannerService portScannerService;
  final AdvancedDiscoveryCoordinator? discoveryCoordinator;

  const DeviceDetailsScreen({
    super.key,
    required this.device,
    this.portScannerService = const PortScannerService(),
    this.discoveryCoordinator,
  });

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen>
    with WidgetsBindingObserver {
  bool _isScanningPorts = false;
  bool _hasFinishedPortScanAttempt = false;
  String? _portScanError;
  bool _isDiscoveringServices = false;
  bool _hasFinishedDiscoveryAttempt = false;
  String? _discoveryError;
  late final AdvancedDiscoveryCoordinator _discoveryCoordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _discoveryCoordinator =
        widget.discoveryCoordinator ??
        AdvancedDiscoveryCoordinator(providers: [MdnsDiscoveryProvider()]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_discoveryCoordinator.cancel());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_discoveryCoordinator.dispose());
    super.dispose();
  }

  Future<void> _startPortScan({bool force = false}) async {
    if (_isScanningPorts || (!force && widget.device.isPortScanCompleted)) {
      return;
    }

    setState(() {
      _isScanningPorts = true;
      _portScanError = null;
    });

    try {
      final results = await widget.portScannerService.scanPorts(
        widget.device.ip,
      );
      widget.device.detectedServices = results;
      widget.device.openPorts = results.keys.toList();
      widget.device.isPortScanCompleted = true;
    } catch (_) {
      if (mounted) {
        _portScanError = 'No se pudo completar el escaneo.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanningPorts = false;
          _hasFinishedPortScanAttempt = true;
        });
      }
    }
  }

  Future<void> _startAdvancedDiscovery({bool force = false}) async {
    final device = widget.device;
    if (_isDiscoveringServices ||
        (!force && device.isAdvancedDiscoveryCompleted)) {
      return;
    }

    setState(() {
      _isDiscoveringServices = true;
      _discoveryError = null;
    });

    try {
      final result = await _discoveryCoordinator.discover(
        timeout: const Duration(seconds: 5),
      );
      if (result.cancelled) return;

      if (force) {
        device.announcedServices.clear();
        device.discoveryProtocols.clear();
      }
      for (final discoveredDevice in result.devices) {
        final sameIp = discoveredDevice.addresses.contains(device.ip);
        final sameHostname = discoveredDevice.hostnames.any(
          (hostname) => _sameHostname(hostname, device.hostname),
        );
        if (!sameIp && !sameHostname) continue;
        for (final observation in discoveredDevice.observations) {
          device.mergeDiscoveryObservation(observation);
        }
      }
      device.isAdvancedDiscoveryCompleted = true;

      if (result.errors.isNotEmpty && device.announcedServices.isEmpty) {
        _discoveryError = 'No se pudo completar el descubrimiento mDNS.';
      }
    } catch (_) {
      _discoveryError = 'No se pudo completar el descubrimiento mDNS.';
    } finally {
      if (mounted) {
        setState(() {
          _isDiscoveringServices = false;
          _hasFinishedDiscoveryAttempt = true;
        });
      }
    }
  }

  bool _sameHostname(String first, String second) {
    String normalize(String value) =>
        value.trim().replaceFirst(RegExp(r'\.$'), '').toLowerCase();
    final normalizedSecond = normalize(second);
    return normalizedSecond != 'host desconocido' &&
        normalize(first) == normalizedSecond;
  }

  IconData _getIconForService(int port, String serviceName) {
    switch (serviceName.toUpperCase()) {
      case 'FTP':
        return Icons.folder_shared;
      case 'SSH':
        return Icons.terminal;
      case 'HTTP':
      case 'HTTPS':
      case 'HTTP ALT':
      case 'HTTPS ALT':
        return Icons.language;
      case 'RPC':
        return Icons.settings_ethernet;
      case 'NETBIOS':
        return Icons.devices;
      case 'SMB':
        return Icons.folder;
      case 'RTSP':
        return Icons.video_camera_back;
      case 'RDP':
        return Icons.desktop_windows;
      case 'WSDAPI':
        return Icons.devices_other;
      case 'PRINTER':
        return Icons.print;
      default:
        return Icons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final device = widget.device;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles del dispositivo'),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icono grande superior
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: device.detectionMethod == 'ICMP'
                    ? Colors.blue.shade100
                    : Colors.orange.shade100,
                child: Icon(
                  device.icon,
                  size: 50,
                  color: device.detectionMethod == 'ICMP'
                      ? Colors.blue
                      : Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Sección: Información Básica
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Información básica',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Divider(),
                    _buildInfoRow(context, 'Hostname', device.hostname),
                    _buildInfoRow(context, 'Dirección IP', device.ip),
                    _buildInfoRow(
                      context,
                      'Tipo de dispositivo',
                      device.deviceType,
                    ),
                    _buildInfoRow(
                      context,
                      'Método de detección',
                      device.detectionMethod,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sección: Estado
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Divider(),
                    const Row(
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 14),
                        SizedBox(width: 8),
                        Text(
                          'Detectado en el último escaneo',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sección: Servicios detectados
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                title: Text(
                  'Servicios detectados',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                leading: Icon(
                  Icons.settings_ethernet,
                  color: colorScheme.primary,
                ),
                shape: const Border(),
                collapsedShape: const Border(),
                onExpansionChanged: (expanded) {
                  if (expanded && !device.isPortScanCompleted) {
                    _startPortScan();
                  }
                },
                children: [
                  const Divider(height: 1),
                  if (_isScanningPorts)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text(
                              'Escaneando puertos...',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_portScanError != null)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: colorScheme.error,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _portScanError!,
                              style: TextStyle(color: colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (device.isPortScanCompleted)
                    if (device.detectedServices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'No se detectaron servicios conocidos.',
                            style: TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          children: device.detectedServices.entries.map((
                            entry,
                          ) {
                            final port = entry.key;
                            final serviceName = entry.value;
                            return ListTile(
                              leading: Icon(
                                _getIconForService(port, serviceName),
                                color: colorScheme.secondary,
                              ),
                              title: Text(
                                '$serviceName ($port)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      )
                  else
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          'Toca para escanear servicios',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  if (device.isPortScanCompleted || _hasFinishedPortScanAttempt)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: OutlinedButton.icon(
                        onPressed: _isScanningPorts
                            ? null
                            : () => _startPortScan(force: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Volver a escanear servicios'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _buildAnnouncedServicesCard(context),
            const SizedBox(height: 16),

            // Sección: Información adicional (placeholders para futuras iteraciones)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Información adicional',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Divider(),
                    _buildInfoRow(context, 'Fabricante', 'No disponible'),
                    _buildInfoRow(
                      context,
                      'Servicios detectados',
                      device.isPortScanCompleted
                          ? (device.detectedServices.isEmpty
                                ? 'Ninguno'
                                : device.detectedServices.values.join(', '))
                          : 'No disponible',
                    ),
                    _buildInfoRow(
                      context,
                      'Puertos abiertos',
                      device.isPortScanCompleted
                          ? (device.openPorts.isEmpty
                                ? 'Ninguno'
                                : device.openPorts.join(', '))
                          : 'No disponible',
                    ),
                    _buildInfoRow(
                      context,
                      'Tiempo de respuesta',
                      'No disponible',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncedServicesCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final services = [...widget.device.announcedServices]
      ..sort((a, b) => a.instanceName.compareTo(b.instanceName));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          'Servicios anunciados',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        subtitle: const Text('mDNS y futuros protocolos de anuncio'),
        leading: Icon(Icons.campaign, color: colorScheme.primary),
        shape: const Border(),
        collapsedShape: const Border(),
        onExpansionChanged: (expanded) {
          if (!expanded) return;
          final hasExpiredServices = widget.device.hasExpiredAnnouncedServices;
          if (!widget.device.isAdvancedDiscoveryCompleted ||
              hasExpiredServices) {
            widget.device.pruneExpiredAnnouncedServices();
            _startAdvancedDiscovery(force: hasExpiredServices);
          }
        },
        children: [
          const Divider(height: 1),
          if (_isDiscoveringServices)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Buscando anuncios mDNS...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else if (_discoveryError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _discoveryError!,
                    style: TextStyle(color: colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (widget.device.isAdvancedDiscoveryCompleted &&
              services.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No se detectaron servicios anunciados por este dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (services.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: services.map((service) {
                  final endpoint = [
                    if (service.hostname != null) service.hostname!,
                    if (service.port != null) service.port.toString(),
                  ].join(':');
                  return ListTile(
                    leading: Icon(
                      Icons.wifi_tethering,
                      color: colorScheme.secondary,
                    ),
                    title: Text(
                      service.instanceName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      [
                        '${service.protocol.label} · ${service.serviceType}',
                        if (endpoint.isNotEmpty) endpoint,
                      ].join('\n'),
                    ),
                    isThreeLine: endpoint.isNotEmpty,
                  );
                }).toList(),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Toca para buscar servicios anunciados',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          if (widget.device.isAdvancedDiscoveryCompleted ||
              _hasFinishedDiscoveryAttempt)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton.icon(
                onPressed: _isDiscoveringServices
                    ? null
                    : () => _startAdvancedDiscovery(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Volver a buscar servicios anunciados'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
