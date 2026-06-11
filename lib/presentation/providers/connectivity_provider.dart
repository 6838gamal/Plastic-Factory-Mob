import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/api_datasource.dart';
import 'auth_provider.dart';

enum ConnectivityStatus { unknown, online, offline }

class ConnectivityNotifier extends AsyncNotifier<ConnectivityStatus> {
  static const _interval = Duration(seconds: 20);
  Timer? _timer;

  @override
  Future<ConnectivityStatus> build() async {
    ref.onDispose(() => _timer?.cancel());
    final status = await _check();
    _startPolling();
    return status;
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) async {
      final status = await _check();
      state = AsyncData(status);
    });
  }

  Future<ConnectivityStatus> _check() async {
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.checkHealth();
      return ConnectivityStatus.online;
    } catch (_) {
      return ConnectivityStatus.offline;
    }
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    final status = await _check();
    state = AsyncData(status);
    if (status == ConnectivityStatus.online) _startPolling();
  }
}

final connectivityProvider =
    AsyncNotifierProvider<ConnectivityNotifier, ConnectivityStatus>(
        ConnectivityNotifier.new);
