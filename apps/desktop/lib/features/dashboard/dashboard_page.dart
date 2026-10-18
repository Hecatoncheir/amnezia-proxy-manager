import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/settings_cubit.dart';
import '../updates/updates_view.dart';
import '../engine/engine_manager.dart';
import '../engine/engine_view.dart';
import '../engine/engine_panel.dart';
import '../profiles/profiles_cubit.dart';
import '../profiles/profiles_view.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.engine, this.profiles, this.xray});
  final EngineManager? engine;
  final EngineManager? xray;
  final ProfilesCubit? profiles;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    if (widget.engine != null) unawaited(widget.engine!.check());
    if (widget.xray != null) unawaited(widget.xray!.check());
    if (widget.profiles != null) unawaited(widget.profiles!.load());
  }

  @override
  void dispose() {
    if (widget.engine != null) unawaited(widget.engine!.close());
    if (widget.xray != null) unawaited(widget.xray!.close());
    if (widget.profiles != null) unawaited(widget.profiles!.close());
    super.dispose();
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
              child: const _SettingsDialog(),
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
              const _ConnectionCard(),
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
  const _SettingsDialog();

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
  const _ConnectionCard();

  @override
  Widget build(BuildContext context) {
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
                      const Text(
                        'Отключено',
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
                  tooltip: 'Подключение станет доступно после реализации управления VPN-процессом',
                  onPressed: null,
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(18),
                    disabledBackgroundColor: colors.onSurface.withValues(
                      alpha: 0.08,
                    ),
                    disabledForegroundColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xffc7785b)
                        : const Color(0xffa34f38),
                  ),
                  icon: const Icon(Icons.power_settings_new, size: 32),
                ),
              ],
            ),
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
