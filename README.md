<div align="center">
  <img src="https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/flutter/flutter-original.svg" width="88" alt="Flutter" />

  # Mini Nmap

  **Explorador de red local desarrollado con Flutter para descubrir dispositivos y consultar servicios expuestos.**

  [![Flutter](https://img.shields.io/badge/Flutter-Material_3-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
  [![Dart](https://img.shields.io/badge/Dart-%5E3.12.2-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
  [![Android](https://img.shields.io/badge/Android-configurado-3DDC84?logo=android&logoColor=white)](https://developer.android.com/)
  [![Tests](https://img.shields.io/badge/tests-Flutter_Test-42A5F5?logo=flutter&logoColor=white)](#pruebas)
</div>

---

## Sobre el proyecto

Mini Nmap es una aplicación para inspeccionar una red Wi-Fi local desde una interfaz móvil. Obtiene la dirección IPv4 del dispositivo, deriva su segmento `/24` y permite descubrir hosts activos mediante ICMP o mediante una combinación de ICMP y conexiones TCP.

Cada resultado incluye dirección IP, hostname cuando la resolución inversa está disponible, método de detección y una clasificación orientativa del tipo de dispositivo. Desde la vista de detalle se pueden consultar puertos TCP conocidos y anuncios de servicios mDNS.

El nombre está inspirado en Nmap, pero el alcance es deliberadamente acotado: la aplicación no realiza explotación de vulnerabilidades, escaneo UDP general, fingerprinting de sistema operativo ni análisis profundo de servicios.

## Características principales

- Detección automática de la IP Wi-Fi y del segmento local `/24`.
- Dos modalidades de descubrimiento: escaneo rápido por ICMP y escaneo profundo con fallback TCP.
- Resultados incrementales durante el escaneo y ordenamiento final por dirección IPv4.
- Resolución inversa de hostname con un timeout de 800 ms.
- Clasificación heurística por hostname para routers, equipos, teléfonos, televisores, impresoras, servidores/NAS, consolas, cámaras IP, dispositivos IoT, altavoces inteligentes y repetidores Wi-Fi.
- Sondeo bajo demanda de 13 puertos TCP conocidos por dispositivo.
- Descubrimiento mDNS bajo demanda con lectura de registros PTR, SRV, TXT, A y AAAA.
- Agrupación y deduplicación de observaciones mDNS, conservación del TTL y descarte de anuncios vencidos.
- Estados de carga, resultados vacíos, reintento y mensajes de error en las operaciones desde la vista de detalle.
- Interfaz Material 3 con listado de dispositivos y pantalla de información individual.

## Cómo funciona el escaneo

### Escaneo rápido

1. `NetworkService` obtiene la IP asignada a la interfaz Wi-Fi mediante `network_info_plus`.
2. La aplicación toma los tres primeros octetos para representar la red como `x.x.x.0/24`.
3. `lan_scanner` ejecuta un descubrimiento ICMP rápido sobre el segmento.
4. Cada host encontrado pasa por resolución inversa de nombre y clasificación heurística antes de mostrarse.

### Escaneo profundo

El escaneo profundo comienza con la misma fase ICMP. Después recorre las direcciones `1` a `254` que no respondieron y las procesa en bloques de 20:

| Nivel | Puertos TCP | Timeout por intento |
| --- | --- | ---: |
| Prioritario | `445`, `135`, `139`, `80`, `443`, `22`, `3389` | 300 ms |
| Secundario | `21`, `554`, `8080`, `8443`, `9100`, `5353`, `1900` | 500 ms |

El segundo nivel solo se ejecuta si ninguno de los puertos prioritarios acepta una conexión. Una conexión TCP exitosa basta para considerar activa la dirección; no se inspeccionan banners ni contenido de aplicación.

### Servicios TCP por dispositivo

Al abrir la sección **Servicios detectados**, `PortScannerService` prueba en paralelo un conjunto fijo de puertos con conexiones TCP y un timeout predeterminado de 600 ms:

| Puerto | Servicio asociado | Puerto | Servicio asociado |
| ---: | --- | ---: | --- |
| 21 | FTP | 22 | SSH |
| 80 | HTTP | 135 | RPC |
| 139 | NetBIOS | 443 | HTTPS |
| 445 | SMB | 554 | RTSP |
| 3389 | RDP | 5357 | WSDAPI |
| 8080 | HTTP Alt | 8443 | HTTPS Alt |
| 9100 | Printer |  |  |

La asociación se basa exclusivamente en el número de puerto. Un puerto abierto se muestra con el nombre esperado, sin validación del protocolo que realmente responde detrás de él. Los resultados se guardan en el modelo del dispositivo durante la sesión y pueden volver a escanearse manualmente.

## Descubrimiento mDNS

La vista de detalle también puede buscar servicios anunciados en `224.0.0.251:5353` durante una ventana de cinco segundos. La implementación:

- enumera tipos mediante `_services._dns-sd._udp.local`;
- consulta servicios habituales como Google Cast, AirPlay, RAOP, HTTP(S), IPP(S), impresoras, información de dispositivo y estaciones de trabajo;
- codifica consultas DNS PTR y analiza respuestas PTR, SRV, TXT, A y AAAA;
- relaciona instancias, hostname, puerto, direcciones y metadatos TXT;
- vincula los anuncios al dispositivo seleccionado por IP o hostname;
- cancela el descubrimiento cuando la pantalla pasa a segundo plano y libera sus recursos.

En Android se utiliza un `MethodChannel` para adquirir temporalmente un `WifiManager.MulticastLock`, necesario para recibir tráfico multicast con fiabilidad. Aunque los modelos contemplan protocolos futuros, el único proveedor de descubrimiento avanzado implementado actualmente es mDNS.

## Tecnologías

| Tecnología | Uso en el proyecto |
| --- | --- |
| Flutter / Material 3 | Interfaz y navegación de la aplicación |
| Dart `^3.12.2` | Lógica, sockets TCP/UDP, concurrencia y modelos |
| `lan_scanner ^4.0.0+1` | Descubrimiento ICMP de hosts en la LAN |
| `network_info_plus ^8.1.0` | Obtención de la dirección IP Wi-Fi |
| Kotlin / Android SDK | Integración nativa del bloqueo multicast |
| `flutter_test` | Pruebas unitarias y de widgets |
| `flutter_lints ^6.0.0` | Reglas de análisis estático |

## Arquitectura

El código separa la presentación, los modelos de dominio y los servicios de red:

```text
lib/
├── main.dart
├── models/
│   ├── device.dart
│   ├── announced_service.dart
│   ├── discovered_device.dart
│   └── discovery_observation.dart
├── screens/
│   ├── home_screen.dart
│   └── device_details_screen.dart
├── services/
│   ├── network_service.dart
│   ├── scanner_service.dart
│   ├── hostname_service.dart
│   ├── tcp_probe_service.dart
│   ├── port_scanner_service.dart
│   ├── advanced_discovery_coordinator.dart
│   ├── discovery_aggregator.dart
│   ├── discovery_provider.dart
│   ├── mdns_discovery_provider.dart
│   ├── mdns_packet.dart
│   ├── mdns_transport.dart
│   └── android_multicast_lock.dart
├── utils/
│   ├── device_classifier.dart
│   └── ip_sorter.dart
└── widgets/
    ├── device_card.dart
    ├── loading_state.dart
    └── scan_buttons.dart
```

`DiscoveryProvider` define una interfaz extensible para fuentes de descubrimiento. `AdvancedDiscoveryCoordinator` administra ejecución, timeout, cancelación y errores de los proveedores, mientras `DiscoveryAggregator` unifica observaciones que comparten identificadores, IP, hostname o nombre anunciado.

## Plataformas y permisos

El repositorio conserva los runners generados por Flutter para Android, iOS, Linux, macOS, web y Windows. Sin embargo, la integración de red necesaria para el funcionamiento completo está configurada de forma explícita en **Android**.

El manifiesto principal de Android declara:

- `INTERNET`
- `ACCESS_WIFI_STATE`
- `ACCESS_NETWORK_STATE`
- `ACCESS_FINE_LOCATION`
- `CHANGE_WIFI_MULTICAST_STATE`

Además, la implementación depende de `dart:io`, por lo que no es compatible con web en su estado actual. Los demás runners no incluyen en este repositorio una configuración nativa equivalente para permisos de red local/multicast; por ello no se presentan aquí como plataformas operativas verificadas.

## Pruebas

La suite ubicada en `test/` cubre:

- arranque y contenido básico de la interfaz;
- mapa de puertos TCP, caché, reescaneo, estados vacíos y recuperación ante errores;
- conversión, TTL y expiración de servicios anunciados;
- agrupación de observaciones y separación de dispositivos no relacionados;
- coordinación de proveedores, timeout, cancelación y tolerancia a errores parciales;
- codificación de consultas y parsing de paquetes mDNS;
- emisión de observaciones desde datagramas controlados y descarte de paquetes malformados;
- renderizado de servicios mDNS en el detalle de un dispositivo.

Para ejecutar las verificaciones:

```bash
flutter analyze
flutter test
```

## Ejecución

### Requisitos

- Flutter en el canal estable con una versión compatible con Dart `^3.12.2`.
- Android SDK y un dispositivo o emulador configurado.
- Conexión del dispositivo a una red Wi-Fi local.

### Puesta en marcha

```bash
git clone <URL_DEL_REPOSITORIO>
cd mini_nmap
flutter pub get
flutter run
```

Para obtener resultados útiles, ejecuta la aplicación en un dispositivo conectado a la misma LAN que los equipos que deseas descubrir y concede los permisos solicitados por Android.

> [!CAUTION]
> Utiliza el escaneo únicamente en redes propias o en aquellas donde tengas autorización. Los firewalls, el aislamiento entre clientes Wi-Fi y las políticas del punto de acceso pueden ocultar dispositivos o puertos.

## Límites conocidos

- La máscara se asume como `/24`; no se consulta la máscara real de la interfaz.
- El descubrimiento inicial usa IPv4 y el fallback recorre únicamente las direcciones `1–254`.
- La detección de servicios TCP se limita a un mapa fijo de puertos y no realiza banner grabbing.
- La clasificación del dispositivo es heurística y depende principalmente del hostname.
- mDNS descubre anuncios disponibles en la red, pero no equivale a un escaneo UDP general.
- No se realiza análisis de vulnerabilidades, fingerprinting de sistema operativo ni explotación.

---

<div align="center">
  Construido con Flutter para ofrecer una vista clara y acotada de la red local.
</div>
