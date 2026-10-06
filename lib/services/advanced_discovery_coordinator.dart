import 'dart:async';

import '../models/discovered_device.dart';
import 'discovery_aggregator.dart';
import 'discovery_provider.dart';

class DiscoveryRunResult {
  final List<DiscoveredDevice> devices;
  final Map<String, Object> errors;
  final bool timedOut;
  final bool cancelled;

  const DiscoveryRunResult({
    required this.devices,
    required this.errors,
    required this.timedOut,
    required this.cancelled,
  });
}

class AdvancedDiscoveryCoordinator {
  final List<DiscoveryProvider> providers;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Completer<void>? _cancelSignal;
  bool _isRunning = false;

  AdvancedDiscoveryCoordinator({required Iterable<DiscoveryProvider> providers})
    : providers = List.unmodifiable(providers);

  bool get isRunning => _isRunning;

  Future<DiscoveryRunResult> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_isRunning) {
      throw StateError('A discovery operation is already running.');
    }

    _isRunning = true;
    _cancelSignal = Completer<void>();
    final aggregator = DiscoveryAggregator();
    final errors = <String, Object>{};
    final providerDone = <Future<void>>[];
    var timedOut = false;
    var cancelled = false;
    Timer? timeoutTimer;

    try {
      for (final provider in providers) {
        final done = Completer<void>();
        providerDone.add(done.future);
        try {
          final subscription = provider
              .discover(timeout: timeout)
              .listen(
                aggregator.add,
                onError: (Object error, StackTrace stackTrace) {
                  errors[provider.id] = error;
                },
                onDone: () {
                  if (!done.isCompleted) done.complete();
                },
                cancelOnError: false,
              );
          _subscriptions.add(subscription);
        } catch (error) {
          errors[provider.id] = error;
          done.complete();
        }
      }

      final allDone = Future.wait(providerDone);
      final timeoutSignal = Completer<void>();
      timeoutTimer = Timer(timeout, () {
        timedOut = true;
        timeoutSignal.complete();
      });
      await Future.any([allDone, timeoutSignal.future, _cancelSignal!.future]);
      cancelled = _cancelSignal!.isCompleted && !timedOut;
    } finally {
      timeoutTimer?.cancel();
      await _stopProviders();
      _isRunning = false;
      _cancelSignal = null;
    }

    return DiscoveryRunResult(
      devices: aggregator.devices,
      errors: Map.unmodifiable(errors),
      timedOut: timedOut,
      cancelled: cancelled,
    );
  }

  Future<void> cancel() async {
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
    await _stopProviders();
  }

  Future<void> _stopProviders() async {
    final subscriptions = List<StreamSubscription<Object?>>.from(
      _subscriptions,
    );
    _subscriptions.clear();
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
    await Future.wait(providers.map((provider) => provider.cancel()));
  }

  Future<void> dispose() async {
    await cancel();
    await Future.wait(providers.map((provider) => provider.dispose()));
  }
}
