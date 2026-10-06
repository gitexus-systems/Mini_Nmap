import 'dart:async';
import 'dart:io';

import 'android_multicast_lock.dart';

abstract interface class MdnsTransport {
  Stream<List<int>> get packets;

  Future<void> start();

  void send(List<int> packet);

  Future<void> close();
}

class UdpMdnsTransport implements MdnsTransport {
  static final InternetAddress multicastAddress = InternetAddress(
    '224.0.0.251',
  );
  static const int multicastPort = 5353;

  final AndroidMulticastLock multicastLock;
  final StreamController<List<int>> _packets = StreamController.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;

  UdpMdnsTransport({AndroidMulticastLock? multicastLock})
    : multicastLock = multicastLock ?? AndroidMulticastLock();

  @override
  Stream<List<int>> get packets => _packets.stream;

  @override
  Future<void> start() async {
    if (_socket != null) return;
    await multicastLock.acquire();
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        multicastPort,
        reuseAddress: true,
        reusePort: true,
      );
      socket.multicastHops = 1;
      socket.joinMulticast(multicastAddress);
      _socket = socket;
      _subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          _packets.add(datagram!.data);
        }
      }, onError: _packets.addError);
    } catch (_) {
      await multicastLock.release();
      rethrow;
    }
  }

  @override
  void send(List<int> packet) {
    final socket = _socket;
    if (socket == null) {
      throw StateError('The mDNS transport has not been started.');
    }
    socket.send(packet, multicastAddress, multicastPort);
  }

  @override
  Future<void> close() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _socket?.close();
    _socket = null;
    await multicastLock.release();
    if (!_packets.isClosed) {
      await _packets.close();
    }
  }
}
