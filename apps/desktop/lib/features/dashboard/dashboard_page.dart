import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../settings/settings_cubit.dart';
import '../updates/updates_view.dart';
import '../engine/engine_manager.dart';
import '../engine/engine_view.dart';
import '../profiles/profiles_cubit.dart';
import '../profiles/profiles_view.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, this.engine, this.profiles});
  final EngineManager? engine;
  final ProfilesCubit? profiles;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const _Header(),
              const SizedBox(height: 24),
              if (engine != null) ...[
                EngineView(manager: engine!),
                const SizedBox(height: 16),
              ],
              const _ConnectionCard(),
              const SizedBox(height: 16),
              if (profiles != null)
                ProfilesView(manager: profiles!)
              else
                const _ProfileCard(),
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
  const _Header();

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
          icon: Icon(Icons.tune, color: colors.onSurfaceVariant),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => BlocProvider.value(
              value: context.read<SettingsCubit>(),
              child: const _SettingsDialog(),
            ),
          ),
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
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.power_settings_new,
                    size: 32,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Tooltip(
              message: 'Подключение станет доступно после реализации управления VPN-процессом',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: colors.primary.withValues(
                    alpha: 0.55,
                  ),
                  disabledForegroundColor: colors.onPrimary,
                ),
                onPressed: null,
                child: const Text('Подключить SOCKS5'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

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
              'ПРОФИЛЬ VPN',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.dns_outlined, color: colors.secondary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'AmneziaWG · профиль не выбран',
                    style: TextStyle(fontSize: 18),
                  ),
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
