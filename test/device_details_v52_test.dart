import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mini_nmap/models/announced_service.dart';
import 'package:mini_nmap/models/device.dart';
import 'package:mini_nmap/screens/device_details_screen.dart';

void main() {
  testWidgets(
    'shows announced mDNS services separately from detected TCP ports',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final device = Device(
        ip: '192.168.1.40',
        hostname: 'living-room.local',
        deviceType: 'TV',
        detectionMethod: 'ICMP',
        icon: Icons.tv,
        announcedServices: [
          AnnouncedService(
            protocol: DiscoveryProtocol.mdns,
            serviceType: '_googlecast._tcp.local',
            instanceName: 'Living Room',
            hostname: 'living-room.local',
            port: 8009,
            addresses: const ['192.168.1.40'],
            metadata: const {'model': 'Chromecast'},
          ),
        ],
        discoveryProtocols: {DiscoveryProtocol.mdns},
        isAdvancedDiscoveryCompleted: true,
      );

      await tester.pumpWidget(
        MaterialApp(home: DeviceDetailsScreen(device: device)),
      );

      expect(
        find.widgetWithText(ExpansionTile, 'Servicios detectados'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ExpansionTile, 'Servicios anunciados'),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(ExpansionTile, 'Servicios anunciados'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Living Room'), findsOneWidget);
      expect(
        find.text('mDNS · _googlecast._tcp.local\nliving-room.local:8009'),
        findsOneWidget,
      );
      expect(device.announcedServices, hasLength(1));
      expect(device.openPorts, isEmpty);
      expect(device.isPortScanCompleted, isFalse);
      expect(device.isAdvancedDiscoveryCompleted, isTrue);
    },
  );
}
