import 'dart:io';

import 'package:flutter/services.dart';

class AndroidMulticastLock {
  static const MethodChannel _channel = MethodChannel('mini_nmap/multicast');

  bool _isHeld = false;

  Future<void> acquire() async {
    if (!Platform.isAndroid || _isHeld) return;
    await _channel.invokeMethod<void>('acquire');
    _isHeld = true;
  }

  Future<void> release() async {
    if (!Platform.isAndroid || !_isHeld) return;
    try {
      await _channel.invokeMethod<void>('release');
    } finally {
      _isHeld = false;
    }
  }
}
