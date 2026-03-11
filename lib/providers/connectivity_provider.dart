import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider() {
    _init();
  }

  bool _isOnline = true;
  ConnectivityResult _lastResult = ConnectivityResult.wifi;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _pollTimer;

  bool get isOnline => _isOnline;
  ConnectivityResult get lastResult => _lastResult;

  Future<void> _init() async {
    final connectivity = Connectivity();

    try {
      final results = await connectivity.checkConnectivity();
      _updateFromResults(results, notify: false);
    } catch (_) {
      _isOnline = true;
    }

    _subscription = connectivity.onConnectivityChanged.listen(
      (results) => _updateFromResults(results),
    );

    // Periodically re-check in case the platform misses events
    _pollTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) async {
        try {
          final results = await connectivity.checkConnectivity();
          _updateFromResults(results);
        } catch (_) {
          // Ignore polling errors
        }
      },
    );
  }

  void _updateFromResults(
    List<ConnectivityResult> results, {
    bool notify = true,
  }) {
    final primary =
        results.isNotEmpty ? results.first : ConnectivityResult.none;
    _lastResult = primary;

    final online = results.any((result) => result != ConnectivityResult.none);

    if (online != _isOnline) {
      _isOnline = online;
      if (notify) {
        notifyListeners();
      }
    } else if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}
