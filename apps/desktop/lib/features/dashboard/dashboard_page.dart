import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/settings_cubit.dart';
import '../../settings/startup_cubit.dart';
import '../../settings/window_placement.dart';
import '../connection/connection_cubit.dart';
import '../updates/updates_view.dart';
import '../engine/engine_manager.dart';
import '../engine/engine_view.dart';
import '../engine/engine_panel.dart';
import '../profiles/profiles_cubit.dart';
import '../profiles/profiles_view.dart';
import 'preparation_cubit.dart';
import 'preparation_view.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.engine, this.profiles, this.xray});
  final EngineManager? engine;
  final EngineManager? xray;
  final ProfilesCubit? profiles;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  ConnectionCubit? _connection;
  StartupCubit? _startup;
  late final Future<void> _initialization;
  @override
  void initState() {
    super.initState();
    if (widget.engine != null &&
        widget.xray != null &&
        widget.profiles != null) {
      _connection = ConnectionCubit(
        profiles: widget.profiles!,
        awg: widget.engine!,
        xray: widget.xray!,
        prepare: () async {
          await _initialization;
          await widget.profiles!.importDetected();
        },
      );
      WindowPlacement.beforeClose = _connection!.close;
      _startup = StartupCubit();
    }
    if (widget.engine != null) unawaited(widget.engine!.check());
    if (widget.xray != null) unawaited(widget.xray!.check());
    _initialization = _loadProfileAndStartup();
    unawaited(_autoconnect());
  }

  Future<void> _loadProfileAndStartup() async {
    await Future.wait<void>([
      if (widget.profiles != null) widget.profiles!.load(),
      if (_startup != null) _startup!.load(),
    ]);
    if (Platform.isWindows && widget.profiles != null) {
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
      await _connection?.toggle();
    }
  }

  @override
  void dispose() {
    WindowPlacement.beforeClose = null;
    unawaited(_disposeManagers());
    super.dispose();
  }

  Future<void> _disposeManagers() async {
    await _connection?.close();
    await _startup?.close();
    if (widget.engine != null) await widget.engine!.close();
    if (widget.xray != null) await widget.xray!.close();
    if (widget.profiles != null) await widget.profiles!.close();
  }

  void _openMenu(String section) {
    final content = switch (section) {
      'profiles' =>
        widget.profiles == null
            ? const Text('Профили пока недоступны')
            : ProfilesView(manager: widget.profiles!, ownsManager: false),
      'engines' =>
        widget.engine == null
            ? const Text('Движки пока недоступны')
            : widget.xray != null && widget.profiles != null
            ? EnginePanel(
                awg: widget.engine!,
                xray: widget.xray!,
                profiles: widget.profiles!,
                ownsManagers: false,
              )
            : EngineView(manager: widget.engine!, ownsManager: false),
      _ => null,
    };
    showDialog<void>(
      context: context,
      builder: (_) => section == 'settings'
          ? BlocProvider.value(
              value: context.read<SettingsCubit>(),
              child: _SettingsDialog(startup: _startup),
            )
          : AlertDialog(
              title: Text(section == 'profiles' ? 'Профили' : 'Движки'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(child: content),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Готово'),
                ),
              ],
            ),
    );
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
              _Header(onSelected: _openMenu),
              const SizedBox(height: 24),
              _ConnectionCard(connection: _connection),
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
              const _TrafficCards(),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onSelected});
  final ValueChanged<String> onSelected;

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
        PopupMenuButton<String>(
          tooltip: 'Меню',
          icon: Icon(Icons.menu, color: colors.onSurfaceVariant),
          onSelected: onSelected,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'profiles',
              child: ListTile(
                leading: Icon(Icons.vpn_key_outlined),
                title: Text('Профили'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'engines',
              child: ListTile(
                leading: Icon(Icons.memory_outlined),
                title: Text('Движки'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'settings',
              child: ListTile(
                leading: Icon(Icons.tune),
                title: Text('Настройки'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({this.startup});
  final StartupCubit? startup;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Настройки'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocBuilder<SettingsCubit, ThemeMode>(
              builder: (context, mode) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Тёмная тема'),
                value: mode == ThemeMode.dark,
                onChanged: (_) => context.read<SettingsCubit>().toggleTheme(),
              ),
            ),
            const Divider(height: 24),
            if (startup != null)
              BlocBuilder<StartupCubit, StartupOptions>(
                bloc: startup,
                builder: (context, state) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Автозапуск'),
                      subtitle: const Text('При входе в систему'),
                      value: state.autostart,
                      onChanged: state.busy ? null : startup!.setAutostart,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Автоподключение'),
                      subtitle: const Text(
                        'Подключать выбранный профиль при запуске приложения',
                      ),
                      value: state.autoconnect,
                      onChanged: state.busy ? null : startup!.setAutoconnect,
                    ),
                    if (state.message != null)
                      Text(
                        state.message!,
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            const Divider(height: 32),
            const UpdatesView(),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Готово'),
      ),
    ],
  );
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({this.connection});
  final ConnectionCubit? connection;

  @override
  Widget build(BuildContext context) => connection == null
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
    final busy =
        state.status == ConnectionStatus.starting ||
        state.status == ConnectionStatus.stopping;
    final label = switch (state.status) {
      ConnectionStatus.disconnected => 'Отключено',
      ConnectionStatus.starting => 'Подключение…',
      ConnectionStatus.stopping => 'Отключение…',
      ConnectionStatus.error => 'Не подключено',
      ConnectionStatus.running =>
        state.connectivity == 'verified' ? 'Подключено' : 'Прокси запущен',
    };
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
                        '127.0.0.1:1080',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: running
                      ? 'Отключить'
                      : state.status == ConnectionStatus.starting
                      ? 'Отменить подключение'
                      : 'Подключить',
                  onPressed:
                      connection == null ||
                          state.status == ConnectionStatus.stopping
                      ? null
                      : connection!.toggle,
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(18),
                    disabledBackgroundColor: colors.onSurface.withValues(
                      alpha: 0.08,
                    ),
                    foregroundColor: running
                        ? colors.primary
                        : Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xffc7785b)
                        : const Color(0xffa34f38),
                    backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                    disabledForegroundColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xffc7785b)
                        : const Color(0xffa34f38),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new, size: 32),
                ),
              ],
            ),
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

class _TrafficCards extends StatelessWidget {
  const _TrafficCards();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final download = _TrafficCard(
      label: 'Загрузка',
      icon: Icons.south,
      color: colors.secondary,
    );
    final upload = _TrafficCard(
      label: 'Отправка',
      icon: Icons.north,
      color: colors.tertiary,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            children: [download, const SizedBox(height: 12), upload],
          );
        }
        return Row(
          children: [
            Expanded(child: download),
            const SizedBox(width: 12),
            Expanded(child: upload),
          ],
        );
      },
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.label,
    required this.icon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final Color color;

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
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '— КБ/с',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text('Нет данных', style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
