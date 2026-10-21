import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/proxy_ports.dart';
import '../../settings/vpn_options_cubit.dart';

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
    this.code,
    this.internetBlocked = false,
  });
  final ConnectionStatus status;
  final String connectivity;
  final String? message;
  final String? code;
  final bool internetBlocked;
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
    this.readPorts,
    this.readVpnOptions,
    this.tun,
    SupervisorClient? client,
  }) : client = client ?? SupervisorClient(),
       super(const ProxyConnectionState(ConnectionStatus.disconnected)) {
    _subscription = this.client.events.listen(_event);
  }
  final ProfilesCubit profiles;
  final EngineManager awg, xray;
  final EngineManager? tun;
  final VpnOptions Function()? readVpnOptions;
  final Future<void> Function()? prepare;
  final Future<ProxyPorts> Function()? readPorts;
  final SupervisorClient client;
  bool diagnosing = false;
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
        internetBlocked: value['internetBlocked'] == true,
        code: value['code'] as String?,
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
    emit(
      ProxyConnectionState(
        ConnectionStatus.starting,
        internetBlocked: state.internetBlocked,
      ),
    );
    try {
      await prepare?.call();
      final ports = await _portsForConnection();
      final vpn = readVpnOptions?.call() ?? const VpnOptions();
      final tunBinary = await _prepareTun(vpn);
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
          socksPort: ports.socks,
          httpPort: ports.http,
          allTraffic: vpn.allTraffic,
          killSwitch: vpn.killSwitch,
          tunBinary: tunBinary,
        );
      });
    } catch (error) {
      if (generation == _generation && !isClosed && _closed == null) {
        profiles.lockForConnection(false);
        emit(
          ProxyConnectionState(
            ConnectionStatus.error,
            internetBlocked: state.internetBlocked,
            code: error is SessionProblem ? error.code : 'preparation_failed',
            message: error is ProfileProblem
                ? error.message
                : _message(error is SessionProblem ? error.code : 'ipc_failed'),
          ),
        );
      }
    }
  }

  Future<String?> _prepareTun(VpnOptions options) async {
    if (!options.allTraffic) return null;
    final engine = tun;
    if (engine == null) throw const SessionProblem('vpn_runtime_missing');
    await engine.ensureReady();
    final store = EngineStore(await engine.directory(), policy: engine.policy);
    final release = await store.installed(
      await installedAppVersion(),
      engine.platform,
    );
    if (release == null) throw const SessionProblem('vpn_runtime_missing');
    return store.executable(release).absolute.path;
  }

  Future<ProxyPorts> _portsForConnection() async {
    try {
      return await readPorts?.call() ?? const ProxyPorts();
    } on FormatException catch (error) {
      throw ProfileProblem(error.message);
    }
  }

  Future<void> checkNetwork() async {
    if (state.status != ConnectionStatus.running) return;
    emit(
      ProxyConnectionState(
        ConnectionStatus.running,
        connectivity: 'checking',
        internetBlocked: state.internetBlocked,
      ),
    );
    try {
      await client.check();
    } catch (_) {
      /* Потерю IPC обработает поток событий. */
    }
  }

  Future<void> stop({bool preserveProtection = false}) async {
    ++_generation;
    _stopping = true;
    if (!isClosed) {
      emit(
        ProxyConnectionState(
          ConnectionStatus.stopping,
          internetBlocked: state.internetBlocked,
        ),
      );
    }
    try {
      if (state.internetBlocked && !preserveProtection) {
        await client.unblock();
      } else {
        await client.stop(preserveProtection: preserveProtection);
      }
      if (!isClosed && _closed == null) {
        emit(
          ProxyConnectionState(
            ConnectionStatus.disconnected,
            internetBlocked: preserveProtection && state.internetBlocked,
          ),
        );
      }
    } catch (_) {
      // При потере IPC уничтожаем supervisor; Windows Job Object убирает дерево.
      await client.abort();
      if (!isClosed && _closed == null) {
        emit(
          ProxyConnectionState(
            ConnectionStatus.error,
            message: _message('ipc_failed'),
            internetBlocked: state.internetBlocked,
          ),
        );
      }
    } finally {
      _stopping = false;
      profiles.lockForConnection(false);
    }
  }

  Future<void> unblockInternet() async {
    try {
      await client.unblock();
      emit(const ProxyConnectionState(ConnectionStatus.disconnected));
    } catch (_) {
      emit(
        const ProxyConnectionState(
          ConnectionStatus.error,
          internetBlocked: true,
          message: 'Не удалось снять блокировку. Разрешите запрос прав администратора и повторите отключение.',
        ),
      );
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
  'vpn_elevation_denied' =>
    'Запрос прав администратора отменён. Подключение не запущено.',
  'vpn_elevation_failed' => 'Не удалось открыть компонент VPN с правами администратора. Повторите подключение.',
  'vpn_already_running' => 'Режим VPN уже используется другой копией приложения. Отключите его в том окне.',
  'vpn_authorization_unavailable' =>
    'Не найден pkexec. Установите polkit и агент авторизации рабочего стола.',
  'vpn_platform_unsupported' =>
    'Для этой платформы нет проверенного компонента VPN.',
  'vpn_admin_required' =>
    'Для режима всего трафика разрешите запрос прав администратора.',
  'vpn_unsupported' =>
    'Обновите компонент подключения: он не поддерживает режим VPN.',
  'vpn_runtime_missing' =>
    'Не удалось подготовить TUN. Проверьте доступ к GitHub и раздел «Движки».',
  'vpn_endpoint_failed' => 'Не удалось определить адрес VPN-сервера. Проверьте сеть; после сбоя может потребоваться снять блокировку интернета.',
  'vpn_firewall_failed' => 'Не удалось настроить блокировку интернета. VPN не запущен; используйте кнопку снятия блокировки.',
  'vpn_firewall_unavailable' => 'Не найден системный сетевой фильтр. В Linux установите nftables; затем повторите подключение.',
  'vpn_firewall_conflict' => 'Текущие правила PF macOS несовместимы с безопасной блокировкой. VPN не запущен; проверьте настройки PF.',
  'vpn_tun_failed' => 'Не удалось запустить виртуальный адаптер VPN. Проверьте права администратора и другие VPN.',
  'vpn_tun_exited' => 'Виртуальный адаптер VPN остановился.',
  'vpn_interface_busy' => 'Имя виртуального адаптера занято. Отключите другую копию VPN и повторите подключение.',
  'vpn_unblock_failed' => 'Не удалось снять блокировку интернета. Повторите отключение с правами администратора.',
  'missing_engine' => 'Не удалось подготовить движок. Проверьте доступ к GitHub; повторить загрузку можно в настройках движков.',
  'port_in_use' => 'Не удалось открыть выбранные порты: они заняты или недоступны. Измените порты на главном экране.',
  'invalid_ports' => 'Укажите разные порты SOCKS5 и HTTP от 1 до 65535.',
  'unsupported_ports' =>
    'Обновите приложение: компонент подключения не поддерживает выбор портов.',
  'untrusted_engine' => 'Движок не прошёл проверку. Скачайте его заново.',
  'invalid_config' =>
    'Движок отклонил профиль. Проверьте или импортируйте его заново.',
  'engine_exited' => 'Движок завершился. Можно повторить подключение.',
  'listener_timeout' => 'Движок не открыл локальный прокси.',
  'cleanup_failed' => 'Не удалось удалить временную конфигурацию.',
  'private_config_failed' => 'Не удалось защитить временную конфигурацию.',
  _ => 'Не удалось запустить или остановить движок. Повторите попытку.',
};
