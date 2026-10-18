import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/engine_manager.dart';
import '../engine/engine_store.dart';
import '../profiles/profile_codec.dart';
import '../profiles/profiles_cubit.dart';
import '../updates/app_updates.dart' show installedAppVersion;
import 'supervisor_client.dart';

enum ConnectionStatus { disconnected, starting, running, stopping, error }

class ProxyConnectionState {
  const ProxyConnectionState(
    this.status, {
    this.connectivity = '',
    this.message,
  });
  final ConnectionStatus status;
  final String connectivity;
  final String? message;
  bool get active =>
      status == ConnectionStatus.starting ||
      status == ConnectionStatus.running ||
      status == ConnectionStatus.stopping;
}

class ConnectionCubit extends Cubit<ProxyConnectionState> {
  ConnectionCubit({
    required this.profiles,
    required this.awg,
    required this.xray,
    this.prepare,
    SupervisorClient? client,
  }) : client = client ?? SupervisorClient(),
       super(const ProxyConnectionState(ConnectionStatus.disconnected)) {
    _subscription = this.client.events.listen(_event);
  }
  final ProfilesCubit profiles;
  final EngineManager awg, xray;
  final Future<void> Function()? prepare;
  final SupervisorClient client;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  var _generation = 0;
  var _stopping = false;
  Future<void>? _closed;

  void _event(Map<String, dynamic> value) {
    if (isClosed || _closed != null) return;
    final status = ConnectionStatus.values
        .where((s) => s.name == value['status'])
        .firstOrNull;
    if (status == null) return;
    if (_stopping &&
        (status == ConnectionStatus.starting ||
            status == ConnectionStatus.running)) {
      return;
    }
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error) {
      profiles.lockForConnection(false);
      _stopping = false;
    }
    emit(
      ProxyConnectionState(
        status,
        connectivity:
            const {
              'checking',
              'verified',
              'unverified',
            }.contains(value['connectivity'])
            ? value['connectivity'] as String
            : '',
        message: status == ConnectionStatus.error
            ? _message(value['code'])
            : null,
      ),
    );
  }

  Future<void> toggle() async {
    if (state.status == ConnectionStatus.stopping || _closed != null) return;
    if (state.active) {
      await stop();
      return;
    }
    final generation = ++_generation;
    _stopping = false;
    emit(const ProxyConnectionState(ConnectionStatus.starting));
    try {
      await prepare?.call();
      if (generation != _generation || _closed != null) return;
      await profiles.withSelectedForConnection((family, configuration) async {
        final engine = family == 'xray' ? xray : awg;
        try {
          await engine.ensureReady();
        } catch (_) {
          throw const SessionProblem('missing_engine');
        }
        if (generation != _generation || _closed != null) return;
        final store = EngineStore(
          await engine.directory(),
          policy: engine.policy,
        );
        final release = await store.installed(
          await installedAppVersion(),
          engine.platform,
        );
        if (generation != _generation || _closed != null) return;
        if (release == null) throw const SessionProblem('missing_engine');
        await client.start(
          family: family,
          binary: store.executable(release).absolute.path,
          sha256: release.binary.sha256,
          configuration: configuration,
        );
      });
    } catch (error) {
      if (generation == _generation && !isClosed && _closed == null) {
        profiles.lockForConnection(false);
        emit(
          ProxyConnectionState(
            ConnectionStatus.error,
            message: error is ProfileProblem
                ? error.message
                : _message(error is SessionProblem ? error.code : 'ipc_failed'),
          ),
        );
      }
    }
  }

  Future<void> stop() async {
    ++_generation;
    _stopping = true;
    if (!isClosed) emit(const ProxyConnectionState(ConnectionStatus.stopping));
    try {
      await client.stop();
      if (!isClosed && _closed == null) {
        emit(const ProxyConnectionState(ConnectionStatus.disconnected));
      }
    } catch (_) {
      // При потере IPC уничтожаем supervisor; Windows Job Object убирает дерево.
      await client.abort();
      if (!isClosed && _closed == null) {
        emit(
          ProxyConnectionState(
            ConnectionStatus.error,
            message: _message('ipc_failed'),
          ),
        );
      }
    } finally {
      _stopping = false;
      profiles.lockForConnection(false);
    }
  }

  @override
  Future<void> close() async {
    await (_closed ??= _close());
    await super.close();
  }

  Future<void> _close() async {
    ++_generation;
    await client.close();
    await _subscription.cancel();
    profiles.lockForConnection(false);
  }
}

String _message(Object? code) => switch (code) {
  'missing_engine' => 'Не удалось подготовить движок. Проверьте доступ к GitHub; повторить загрузку можно в меню «Движки».',
  'port_in_use' => 'Порт 1080 или 8080 занят другим приложением.',
  'untrusted_engine' => 'Движок не прошёл проверку. Скачайте его заново.',
  'invalid_config' =>
    'Движок отклонил профиль. Проверьте или импортируйте его заново.',
  'engine_exited' => 'Движок завершился. Можно повторить подключение.',
  'listener_timeout' => 'Движок не открыл локальный прокси.',
  'cleanup_failed' => 'Не удалось удалить временную конфигурацию.',
  'private_config_failed' => 'Не удалось защитить временную конфигурацию.',
  _ => 'Не удалось запустить или остановить движок. Повторите попытку.',
};
