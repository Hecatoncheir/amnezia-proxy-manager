import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/proxy_ports.dart';
import '../profiles/profile_codec.dart';
import '../profiles/profiles_cubit.dart';
import 'connection_cubit.dart';

enum CheckStatus { waiting, checking, passed, failed }

class DiagnosticStep {
  const DiagnosticStep(
    this.title, {
    this.status = CheckStatus.waiting,
    this.detail = '',
  });
  final String title, detail;
  final CheckStatus status;
}

class DiagnosticsState {
  const DiagnosticsState({this.steps = const [], this.busy = false});
  final List<DiagnosticStep> steps;
  final bool busy;
}

class DiagnosticsCubit extends Cubit<DiagnosticsState> {
  DiagnosticsCubit({
    required this.connection,
    required this.profiles,
    required this.ports,
    required this.prepare,
    this.onFinished,
  }) : super(const DiagnosticsState());
  final ConnectionCubit connection;
  final ProfilesCubit profiles;
  final Future<ProxyPorts> Function() ports;
  final Future<void> Function() prepare;
  final void Function()? onFinished;
  Future<void>? _running;

  Future<void> run() {
    if (_transitioning || isClosed) return Future.value();
    return _running ??= _run().whenComplete(() => _running = null);
  }

  bool get _transitioning => const {
    ConnectionStatus.starting,
    ConnectionStatus.stopping,
  }.contains(connection.state.status);

  Future<void> _run() async {
    connection.diagnosing = true;
    emit(
      const DiagnosticsState(
        busy: true,
        steps: [
          DiagnosticStep('Профиль и движок'),
          DiagnosticStep('Локальные порты'),
          DiagnosticStep('Запуск прокси'),
          DiagnosticStep('HTTPS через прокси'),
        ],
      ),
    );
    final temporary = !connection.state.active;
    try {
      await _checkStep(
        0,
        _profile,
        'Конфигурация принята проверенным движком.',
      );
      await _checkStep(
        1,
        () async => _checkPorts(await ports(), temporary),
        temporary
            ? 'Выбранные порты свободны.'
            : 'Оба локальных входа доступны.',
      );
      await _checkStep(
        2,
        () => _startProxy(temporary),
        'Движок работает, SOCKS5 и HTTP готовы.',
      );
      await _checkStep(
        3,
        _https,
        'HTTPS-запрос прошёл через SOCKS5 без прямого подключения.',
      );
    } catch (_) {
      // Причина уже записана в соответствующий шаг.
    } finally {
      if (temporary) await connection.stop();
      connection.diagnosing = false;
      onFinished?.call();
      if (!isClosed) emit(DiagnosticsState(steps: state.steps));
    }
  }

  Future<void> _checkStep(
    int index,
    Future<void> Function() check,
    String success,
  ) async {
    _step(index, CheckStatus.checking);
    try {
      await check();
      _step(index, CheckStatus.passed, success);
    } catch (error) {
      _step(index, CheckStatus.failed, _reason(error));
      rethrow;
    }
  }

  Future<void> _profile() async {
    await prepare();
    await profiles.validateSelected();
  }

  Future<void> _startProxy(bool temporary) async {
    if (temporary) await connection.toggle();
    await _waitFor((value) => value.status == ConnectionStatus.running);
  }

  Future<void> _https() async {
    await connection.checkNetwork();
    await _waitFor((value) => value.connectivity == 'verified');
  }

  bool _interrupted(ProxyConnectionState value) =>
      const {
        ConnectionStatus.error,
        ConnectionStatus.disconnected,
      }.contains(value.status) ||
      value.connectivity == 'unverified';

  Future<void> _waitFor(bool Function(ProxyConnectionState) ready) async {
    if (ready(connection.state)) return;
    _throwIfFailed(connection.state);
    final value = await connection.stream
        .firstWhere((value) => ready(value) || _interrupted(value))
        .timeout(const Duration(seconds: 40));
    _throwIfFailed(value);
    if (!ready(value)) {
      throw const ProfileProblem('Подключение прервано. Повторите проверку.');
    }
  }

  void _throwIfFailed(ProxyConnectionState value) {
    if (value.status == ConnectionStatus.error) {
      throw ProfileProblem(value.message ?? 'Движок не запустился.');
    }
    if (value.connectivity == 'unverified') {
      throw const ProfileProblem(
        'HTTPS не отвечает через прокси. Проверьте интернет и работу этого профиля в AmneziaVPN; затем обновите импортированный профиль.',
      );
    }
  }

  Future<void> _checkPorts(ProxyPorts value, bool bind) async {
    try {
      if (bind) {
        await _reservePorts(value);
        return;
      }
      for (final port in [value.socks, value.http]) {
        await _connectPort(port);
      }
    } on SocketException {
      throw const ProfileProblem(
        'Порт занят или недоступен. Измените порты на главном экране и повторите проверку.',
      );
    }
  }

  Future<void> _reservePorts(ProxyPorts value) async {
    final reservations = <ServerSocket>[];
    try {
      for (final port in [value.socks, value.http]) {
        reservations.add(
          await ServerSocket.bind(InternetAddress.loopbackIPv4, port),
        );
      }
    } finally {
      for (final socket in reservations) {
        await socket.close();
      }
    }
  }

  Future<void> _connectPort(int port) async {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(seconds: 2),
    );
    socket.destroy();
  }

  void _step(int index, CheckStatus status, [String detail = '']) {
    if (isClosed) return;
    final steps = [...state.steps];
    steps[index] = DiagnosticStep(
      steps[index].title,
      status: status,
      detail: detail,
    );
    emit(DiagnosticsState(steps: steps, busy: true));
  }

  String _reason(Object error) {
    if (error is ProfileProblem) return error.message;
    if (error is TimeoutException) {
      return 'Проверка не завершилась вовремя. Проверьте сеть и повторите попытку.';
    }
    return 'Проверка не удалась. Проверьте профиль и доступность движка в настройках.';
  }

  @override
  Future<void> close() async {
    await _running;
    await super.close();
  }
}
