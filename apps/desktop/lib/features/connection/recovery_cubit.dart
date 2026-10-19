import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'connection_cubit.dart';

class RecoveryState {
  const RecoveryState({this.attempt = 0, this.waiting = false});
  final int attempt;
  final bool waiting;
}

/// Повторы существуют только пока пользователь хочет оставаться подключённым.
class RecoveryCubit extends Cubit<RecoveryState> {
  RecoveryCubit(this.connection, {this.delay = const Duration(seconds: 2)})
    : super(const RecoveryState()) {
    _subscription = connection.stream.listen(_changed);
  }

  final ConnectionCubit connection;
  final Duration delay;
  late final StreamSubscription<ProxyConnectionState> _subscription;
  Timer? _timer;
  bool _wanted = false;
  bool _restarting = false;
  int _failures = 0;
  String _lastConnectivity = '';

  Future<void> toggle() async {
    if (connection.diagnosing) return;
    if (_wanted || connection.state.active) {
      await stop();
      return;
    }
    await connect();
  }

  Future<void> connect() async {
    if (connection.diagnosing) return;
    _wanted = true;
    _failures = 0;
    await connection.toggle();
  }

  Future<void> stop() async {
    _wanted = false;
    _timer?.cancel();
    emit(const RecoveryState());
    await connection.stop();
  }

  void _changed(ProxyConnectionState next) {
    if (!_observing) return;
    if (next.status == ConnectionStatus.error) {
      _onError(next.code);
      return;
    }
    _network(next.connectivity);
  }

  void _onError(String? code) {
    const recoverable = {'engine_exited', 'ipc_failed', 'listener_timeout'};
    if (recoverable.contains(code)) {
      _schedule();
      return;
    }
    _wanted = false;
    _timer?.cancel();
    emit(const RecoveryState());
  }

  void _network(String connectivity) {
    if (_lastConnectivity == connectivity) return;
    _lastConnectivity = connectivity;
    if (connectivity == 'verified') {
      _timer?.cancel();
      _failures = 0;
      emit(const RecoveryState());
      return;
    }
    if (connectivity == 'unverified' && ++_failures >= 2) _schedule();
  }

  void _schedule() {
    if (connection.diagnosing) return;
    if (_timer?.isActive == true) return;
    final attempt = state.attempt + 1;
    final milliseconds = (delay.inMilliseconds * attempt).clamp(1, 30000);
    emit(RecoveryState(attempt: attempt, waiting: true));
    _timer = Timer(Duration(milliseconds: milliseconds), _retry);
  }

  bool get _canRetry => _wanted && !isClosed;
  bool get _observing => _canRetry && !_restarting;

  Future<void> _retry() async {
    if (!_canRetry) return;
    if (connection.diagnosing) {
      _schedule();
      return;
    }
    _restarting = true;
    await connection.stop();
    _restarting = false;
    if (!_canRetry) return;
    _lastConnectivity = '';
    emit(RecoveryState(attempt: state.attempt));
    await connection.toggle();
  }

  void reevaluate() {
    if (!_observing) return;
    if (_needsRecovery) {
      _schedule();
      return;
    }
    _changed(connection.state);
  }

  bool get _needsRecovery =>
      connection.state.connectivity == 'unverified' ||
      connection.state.status == ConnectionStatus.disconnected;

  Future<void> resumed() async {
    if (!_wanted) return;
    await connection.checkNetwork();
  }

  @override
  Future<void> close() async {
    _wanted = false;
    _timer?.cancel();
    await _subscription.cancel();
    await super.close();
  }
}
