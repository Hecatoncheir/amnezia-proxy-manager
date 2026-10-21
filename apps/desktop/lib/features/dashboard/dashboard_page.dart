import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/settings_page.dart';
import '../../settings/startup_cubit.dart';
import '../../settings/proxy_ports_cubit.dart';
import '../../settings/vpn_options_cubit.dart';
import '../../settings/vpn_options_view.dart';
import '../../settings/window_placement.dart';
import '../connection/connection_cubit.dart';
import '../connection/recovery_cubit.dart';
import '../connection/diagnostics_cubit.dart';
import '../connection/traffic_cubit.dart';
import '../engine/engine_manager.dart';
import '../engine/tun_policy.dart';
import '../profiles/profiles_cubit.dart';
import 'preparation_cubit.dart';
import 'preparation_view.dart';
import 'proxy_ports_view.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.engine, this.profiles, this.xray});
  final EngineManager? engine;
  final EngineManager? xray;
  final ProfilesCubit? profiles;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  ConnectionCubit? _connection;
  StartupCubit? _startup;
  RecoveryCubit? _recovery;
  DiagnosticsCubit? _diagnostics;
  TrafficCubit? _traffic;
  final _ports = ProxyPortsCubit();
  final _vpn = VpnOptionsCubit();
  final _tun = EngineManager(policy: tunPolicy);
  late final Future<void> _initialization;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.engine != null &&
        widget.xray != null &&
        widget.profiles != null) {
      _connection = ConnectionCubit(
        profiles: widget.profiles!,
        awg: widget.engine!,
        xray: widget.xray!,
        readPorts: _ports.forConnection,
        readVpnOptions: () => _vpn.state,
        tun: _tun,
        prepare: () async {
          await _initialization;
          await widget.profiles!.importDetected();
        },
      );
      _recovery = RecoveryCubit(_connection!);
      _traffic = TrafficCubit(_connection!.client.events);
      _diagnostics = DiagnosticsCubit(
        connection: _connection!,
        profiles: widget.profiles!,
        ports: _ports.forConnection,
        onFinished: () => _recovery?.reevaluate(),
        prepare: () async {
          await _initialization;
          await widget.profiles!.importDetected();
        },
      );
      WindowPlacement.beforeClose = _closeConnection;
      _startup = StartupCubit();
    }
    if (widget.engine != null) unawaited(widget.engine!.check());
    if (widget.xray != null) unawaited(widget.xray!.check());
    unawaited(_tun.check());
    _initialization = _loadProfileAndStartup();
    unawaited(_autoconnect());
  }

  Future<void> _loadProfileAndStartup() async {
    await Future.wait<void>([
      if (widget.profiles != null) widget.profiles!.load(),
      if (_startup != null) _startup!.load(),
      _ports.load(),
      _vpn.load(),
    ]);
    if (widget.profiles != null) {
      final preferences = await SharedPreferences.getInstance();
      if (!(preferences.getBool('automatic-profile-discovery-v1') ?? false)) {
        await widget.profiles!.discoverLocal();
        // Найденная конфигурация пока только в памяти: до её сохранения
        // повторяем поиск после закрытия приложения.
        if (!widget.profiles!.hasDetectedProfile) {
          await preferences.setBool('automatic-profile-discovery-v1', true);
        }
      }
    }
  }

  Future<void> _autoconnect() async {
    await _initialization;
    if (mounted && _startup?.state.autoconnect == true) {
      await _recovery?.connect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WindowPlacement.beforeClose = null;
    unawaited(_disposeManagers());
    super.dispose();
  }

  Future<void> _disposeManagers() async {
    await _closeConnection();
    await _traffic?.close();
    await _startup?.close();
    await _ports.close();
    await _vpn.close();
    await _tun.close();
    if (widget.engine != null) await widget.engine!.close();
    if (widget.xray != null) await widget.xray!.close();
    if (widget.profiles != null) await widget.profiles!.close();
  }

  Future<void>? _closing;
  Future<void> _closeConnection() => _closing ??= _finishConnection();
  Future<void> _finishConnection() async {
    await _recovery?.close();
    await _connection?.close();
    await _diagnostics?.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_recovery?.resumed());
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          startup: _startup,
          profiles: widget.profiles,
          awg: widget.engine,
          xray: widget.xray,
          diagnostics: _diagnostics,
          vpn: _vpn,
          connection: _connection,
          tun: _tun,
          onUnblock: _unblockInternet,
        ),
      ),
    );
  }

  Future<void> _unblockInternet() async {
    await _recovery?.stop();
    await _connection?.unblockInternet();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              _Header(onSettings: _openSettings),
              const SizedBox(height: 24),
              _ConnectionCard(
                connection: _connection,
                ports: _ports,
                recovery: _recovery,
                diagnostics: _diagnostics,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: VpnOptionsView(
                    options: _vpn,
                    connection: _connection,
                    onUnblock: _unblockInternet,
                  ),
                ),
              ),
              if (widget.profiles != null &&
                  widget.engine != null &&
                  widget.xray != null)
                BlocProvider(
                  create: (_) => PreparationCubit(
                    profiles: widget.profiles!,
                    awg: widget.engine!,
                    xray: widget.xray!,
                  ),
                  child: const PreparationView(),
                ),
              const SizedBox(height: 16),
              _TrafficCards(traffic: _traffic),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Image.asset(
          'assets/branding/app_icon.png',
          width: 52,
          height: 52,
          semanticLabel: 'Amnezia Proxy',
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Amnezia Proxy',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'ЛОКАЛЬНЫЙ ПРОКСИ',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Настройки',
          onPressed: onSettings,
          icon: Icon(Icons.tune, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    this.connection,
    required this.ports,
    this.recovery,
    this.diagnostics,
  });
  final DiagnosticsCubit? diagnostics;
  final RecoveryCubit? recovery;
  final ConnectionCubit? connection;
  final ProxyPortsCubit ports;

  @override
  Widget build(BuildContext context) {
    if (diagnostics == null) return _connectionBuilder(context);
    return BlocBuilder<DiagnosticsCubit, DiagnosticsState>(
      bloc: diagnostics,
      builder: (context, _) => _connectionBuilder(context),
    );
  }

  Widget _connectionBuilder(BuildContext context) => connection == null
      ? _content(
          context,
          const ProxyConnectionState(ConnectionStatus.disconnected),
        )
      : BlocBuilder<ConnectionCubit, ProxyConnectionState>(
          bloc: connection,
          builder: _content,
        );

  Widget _content(BuildContext context, ProxyConnectionState state) {
    final running = state.status == ConnectionStatus.running;
    final label = _connectionLabel(state);
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'СОСТОЯНИЕ ПРОКСИ',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '127.0.0.1',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _PowerButton(
                  connection: connection,
                  recovery: recovery,
                  state: state,
                ),
              ],
            ),
            if (recovery != null)
              BlocBuilder<RecoveryCubit, RecoveryState>(
                bloc: recovery,
                builder: (_, state) => state.waiting
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Восстановление соединения · попытка ${state.attempt}',
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ProxyPortsView(cubit: ports, locked: state.active),
            if (state.internetBlocked) ...[
              const SizedBox(height: 12),
              Text(
                running ? 'Блокировка обхода VPN включена.' : 'Сетевые ограничения сохранены. Повторите подключение или снимите блокировку интернета.',
              ),
            ],
            if (state.message != null || running) ...[
              const SizedBox(height: 12),
              Text(
                state.message ??
                    switch (state.connectivity) {
                      'verified' => 'HTTPS через прокси проверен',
                      'checking' => 'Проверяем доступ к сети…',
                      _ => 'Локальный прокси работает. Доступ к сети не подтверждён.',
                    },
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _connectionLabel(ProxyConnectionState state) {
  if (state.status == ConnectionStatus.running) {
    return state.connectivity == 'verified' ? 'Подключено' : 'Прокси запущен';
  }
  return const {
    ConnectionStatus.disconnected: 'Отключено',
    ConnectionStatus.starting: 'Подключение…',
    ConnectionStatus.stopping: 'Отключение…',
    ConnectionStatus.error: 'Не подключено',
  }[state.status]!;
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.connection,
    required this.recovery,
    required this.state,
  });
  final ConnectionCubit? connection;
  final RecoveryCubit? recovery;
  final ProxyConnectionState state;
  @override
  Widget build(BuildContext context) {
    if (recovery == null) return _button(context, false);
    return BlocBuilder<RecoveryCubit, RecoveryState>(
      bloc: recovery,
      builder: (context, value) => _button(context, value.waiting),
    );
  }

  Widget _button(BuildContext context, bool waiting) {
    final colors = Theme.of(context).colorScheme;
    final terracotta = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xffc7785b)
        : const Color(0xffa34f38);
    return IconButton.filled(
      tooltip: _tooltip(waiting),
      onPressed: _action,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(18),
        foregroundColor: state.status == ConnectionStatus.running
            ? colors.primary
            : terracotta,
        disabledForegroundColor: terracotta,
        backgroundColor: colors.onSurface.withValues(alpha: 0.08),
        disabledBackgroundColor: colors.onSurface.withValues(alpha: 0.08),
      ),
      icon: _busy
          ? const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.power_settings_new, size: 32),
    );
  }

  bool get _busy => const {
    ConnectionStatus.starting,
    ConnectionStatus.stopping,
  }.contains(state.status);
  VoidCallback? get _action {
    if (connection == null ||
        connection!.diagnosing ||
        state.status == ConnectionStatus.stopping) {
      return null;
    }
    return recovery?.toggle ?? connection!.toggle;
  }

  String _tooltip(bool waiting) {
    if (waiting) return 'Отменить восстановление';
    if (state.status == ConnectionStatus.running) return 'Отключить';
    if (state.status == ConnectionStatus.starting) {
      return 'Отменить подключение';
    }
    return 'Подключить';
  }
}

class _TrafficCards extends StatelessWidget {
  const _TrafficCards({this.traffic});
  final TrafficCubit? traffic;
  @override
  Widget build(BuildContext context) {
    if (traffic == null) return _content(context, const TrafficState());
    return BlocBuilder<TrafficCubit, TrafficState>(
      bloc: traffic,
      builder: _content,
    );
  }

  Widget _content(BuildContext context, TrafficState state) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _TrafficCard(
            label: 'Загрузка',
            icon: Icons.south,
            color: colors.secondary,
            speed: state.downSpeed,
            total: state.download,
            available: state.available,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TrafficCard(
            label: 'Отправка',
            icon: Icons.north,
            color: colors.tertiary,
            speed: state.upSpeed,
            total: state.upload,
            available: state.available,
          ),
        ),
      ],
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.speed,
    required this.total,
    required this.available,
  });
  final String label;
  final IconData icon;
  final Color color;
  final double speed;
  final int total;
  final bool available;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Flexible(child: Text(label)),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              available ? '${formatBytes(speed)}/с' : '— КБ/с',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            available ? '${formatBytes(total)} за сеанс' : 'Нет данных',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
