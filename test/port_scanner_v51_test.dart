import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mini_nmap/models/device.dart';
import 'package:mini_nmap/screens/device_details_screen.dart';
import 'package:mini_nmap/services/port_scanner_service.dart';

class _ControlledPortScannerService extends PortScannerService {
  final List<Completer<Map<int, String>>> attempts = [];

  int get callCount => attempts.length;

  @override
  Future<Map<int, String>> scanPorts(
    String ip, {
    Duration timeout = const Duration(milliseconds: 600),
  }) {
    final completer = Completer<Map<int, String>>();
    attempts.add(completer);
    return completer.future;
  }
}

Device _buildDevice() {
  return Device(
    ip: '192.168.1.20',
    hostname: 'test-device',
    deviceType: 'PC',
    detectionMethod: 'ICMP',
    icon: Icons.computer,
  );
}

Future<void> _pumpDetails(
  WidgetTester tester,
  Device device,
  PortScannerService scanner,
) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: DeviceDetailsScreen(device: device, portScannerService: scanner),
    ),
  );
}

Finder get _tcpServicesTile =>
    find.widgetWithText(ExpansionTile, 'Servicios detectados');

void main() {
  test('service map contains only the TCP ports supported by v5.1', () {
    expect(PortScannerService.serviceMap, {
      21: 'FTP',
      22: 'SSH',
      80: 'HTTP',
      135: 'RPC',
      139: 'NetBIOS',
      443: 'HTTPS',
      445: 'SMB',
      554: 'RTSP',
      3389: 'RDP',
      5357: 'WSDAPI',
      8080: 'HTTP Alt',
      8443: 'HTTPS Alt',
      9100: 'Printer',
    });
    expect(PortScannerService.serviceMap, isNot(contains(53)));
    expect(PortScannerService.serviceMap, isNot(contains(1900)));
    expect(PortScannerService.serviceMap, isNot(contains(5353)));
  });

  test(
    'PortScannerService can scan an IP and returns known services',
    () async {
      final results = await const PortScannerService().scanPorts(
        '127.0.0.1',
        timeout: const Duration(milliseconds: 50),
      );

      for (final entry in results.entries) {
        expect(entry.value, PortScannerService.serviceMap[entry.key]);
      }
    },
  );

  testWidgets(
    'shows results, reuses the cache, and replaces results on rescan',
    (tester) async {
      final scanner = _ControlledPortScannerService();
      final device = _buildDevice();
      await _pumpDetails(tester, device, scanner);

      await tester.tap(_tcpServicesTile);
      await tester.pump();

      expect(scanner.callCount, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Escaneando puertos...'), findsOneWidget);

      scanner.attempts.single.complete({80: 'HTTP', 445: 'SMB'});
      await tester.pumpAndSettle();

      expect(find.text('HTTP (80)'), findsOneWidget);
      expect(find.text('SMB (445)'), findsOneWidget);
      expect(device.openPorts, [80, 445]);
      expect(device.isPortScanCompleted, isTrue);
      expect(find.text('Volver a escanear servicios'), findsOneWidget);

      await tester.tap(_tcpServicesTile);
      await tester.pumpAndSettle();
      await tester.tap(_tcpServicesTile);
      await tester.pumpAndSettle();

      expect(scanner.callCount, 1);

      await tester.tap(find.text('Volver a escanear servicios'));
      await tester.pump();

      expect(scanner.callCount, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Volver a escanear servicios'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );

      scanner.attempts.last.complete({443: 'HTTPS'});
      await tester.pumpAndSettle();

      expect(find.text('HTTP (80)'), findsNothing);
      expect(find.text('SMB (445)'), findsNothing);
      expect(find.text('HTTPS (443)'), findsOneWidget);
      expect(device.detectedServices, {443: 'HTTPS'});
      expect(device.openPorts, [443]);
      expect(find.text('Volver a escanear servicios'), findsOneWidget);
    },
  );

  testWidgets('shows the empty state after a successful scan', (tester) async {
    final scanner = _ControlledPortScannerService();
    await _pumpDetails(tester, _buildDevice(), scanner);

    await tester.tap(_tcpServicesTile);
    await tester.pump();
    scanner.attempts.single.complete({});
    await tester.pumpAndSettle();

    expect(find.text('No se detectaron servicios conocidos.'), findsOneWidget);
    expect(find.text('Volver a escanear servicios'), findsOneWidget);
  });

  testWidgets('shows an error and allows retrying the scan', (tester) async {
    final scanner = _ControlledPortScannerService();
    await _pumpDetails(tester, _buildDevice(), scanner);

    await tester.tap(_tcpServicesTile);
    await tester.pump();
    scanner.attempts.single.completeError(Exception('scan failed'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo completar el escaneo.'), findsOneWidget);
    expect(find.text('Volver a escanear servicios'), findsOneWidget);

    await tester.tap(find.text('Volver a escanear servicios'));
    await tester.pump();
    expect(scanner.callCount, 2);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );

    scanner.attempts.last.complete({443: 'HTTPS'});
    await tester.pumpAndSettle();

    expect(find.text('HTTPS (443)'), findsOneWidget);
    expect(find.text('No se pudo completar el escaneo.'), findsNothing);
    expect(find.text('Volver a escanear servicios'), findsOneWidget);
  });
}
