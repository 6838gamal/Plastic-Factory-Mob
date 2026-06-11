import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';

enum ConnectivityStatus { unknown, online, offline }

class ConnectivityNotifier extends AsyncNotifier<ConnectivityStatus> {
  static const _interval = Duration(seconds: 20);
  static const _timeout = Duration(seconds: 8);
  Timer? _timer;
  bool _disposed = false;

  @override
  Future<ConnectivityStatus> build() async {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    final status = await _ping();
    if (!_disposed) _startPolling();
    return status;
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) async {
      if (_disposed) return;
      final status = await _ping();
      if (!_disposed) {
        try {
          state = AsyncData(status);
        } catch (_) {
          // Ref was disposed between the ping and state update — ignore.
        }
      }
    });
  }

  /// Pings /api/health independently of Riverpod (no ref.read inside async).
  Future<ConnectivityStatus> _ping() async {
    if (_disposed) return ConnectivityStatus.offline;
    try {
      final base = AppConfig.apiBaseUrl;
      final uri = Uri.parse('$base/api/health');
      final res = await http.get(uri).timeout(_timeout);
      return res.statusCode < 400
          ? ConnectivityStatus.online
          : ConnectivityStatus.offline;
    } catch (_) {
      return ConnectivityStatus.offline;
    }
  }

  Future<void> retry() async {
    if (_disposed) return;
    try {
      state = const AsyncLoading();
    } catch (_) {
      return;
    }
    final status = await _ping();
    if (!_disposed) {
      try {
        state = AsyncData(status);
      } catch (_) {}
    }
    if (status == ConnectivityStatus.online && !_disposed) _startPolling();
  }
}

final connectivityProvider =
    AsyncNotifierProvider<ConnectivityNotifier, ConnectivityStatus>(
        ConnectivityNotifier.new);
