import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/connection/diagnostics_cubit.dart';
import '../features/engine/engine_manager.dart';
import '../features/engine/engine_view.dart';
import '../features/profiles/profiles_cubit.dart';
import '../features/profiles/profiles_view.dart';
import '../features/updates/updates_view.dart';
import 'general_settings_view.dart';
import 'vpn_options_cubit.dart';
import '../features/connection/connection_cubit.dart';
import 'startup_cubit.dart';

enum SettingsSection {
  home('Настройки'),
  general('Общие'),
  profiles('Профили'),
  engines('Движки'),
  diagnostics('Диагностика'),
  updates('Обновления');

  const SettingsSection(this.title);
  final String title;
}

class SettingsNavigation extends Cubit<SettingsSection> {
  SettingsNavigation() : super(SettingsSection.home);
  void open(SettingsSection section) => emit(section);
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    this.startup,
    this.profiles,
    this.awg,
    this.xray,
    this.diagnostics,
    this.vpn,
    this.connection,
    this.tun,
    this.onUnblock,
  });
  final StartupCubit? startup;
  final ProfilesCubit? profiles;
  final EngineManager? awg, xray;
  final DiagnosticsCubit? diagnostics;
  final VpnOptionsCubit? vpn;
  final ConnectionCubit? connection;
  final EngineManager? tun;
  final Future<void> Function()? onUnblock;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SettingsNavigation(),
    child: BlocBuilder<SettingsNavigation, SettingsSection>(
      builder: (context, section) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Назад',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (section == SettingsSection.home) {
                Navigator.pop(context);
                return;
              }
              context.read<SettingsNavigation>().open(SettingsSection.home);
            },
          ),
          title: Text(section.title),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [_content(context, section)],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, SettingsSection section) {
    final pages = <SettingsSection, Widget Function()>{
      SettingsSection.home: () => _sections(context),
      SettingsSection.general: () => GeneralSettingsView(
        startup: startup,
        vpn: vpn,
        connection: connection,
        onUnblock: onUnblock,
      ),
      SettingsSection.profiles: () => profiles == null
          ? const Text('Профили недоступны')
          : ProfilesView(manager: profiles!, ownsManager: false),
      SettingsSection.engines: _engines,
      SettingsSection.diagnostics: () => DiagnosticsView(manager: diagnostics),
      SettingsSection.updates: () => const UpdatesView(),
    };
    return pages[section]!();
  }

  Widget _engines() => Column(
    children: [
      const Text(
        'Движок выбирается автоматически по профилю. Каждый загружается отдельно.',
      ),
      const SizedBox(height: 16),
      if (awg != null) EngineView(manager: awg!, ownsManager: false),
      const SizedBox(height: 16),
      if (xray != null) EngineView(manager: xray!, ownsManager: false),
      if (tun != null) ...[
        const SizedBox(height: 16),
        EngineView(manager: tun!, ownsManager: false),
      ],
    ],
  );

  Widget _sections(BuildContext context) => Column(
    children: [
      _tile(
        context,
        SettingsSection.general,
        Icons.tune,
        'Тема и запуск приложения',
      ),
      _tile(
        context,
        SettingsSection.profiles,
        Icons.vpn_key_outlined,
        'Выбор, импорт и проверка',
      ),
      _tile(
        context,
        SettingsSection.engines,
        Icons.memory_outlined,
        'AmneziaWG и VLESS · Xray',
      ),
      _tile(
        context,
        SettingsSection.diagnostics,
        Icons.health_and_safety_outlined,
        'Проверить подключение и найти причину сбоя',
      ),
      _tile(
        context,
        SettingsSection.updates,
        Icons.system_update_outlined,
        'Версия приложения и новые выпуски',
      ),
    ],
  );

  Widget _tile(
    BuildContext context,
    SettingsSection section,
    IconData icon,
    String description,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon),
      title: Text(section.title),
      subtitle: Text(description),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.read<SettingsNavigation>().open(section),
    ),
  );
}

class DiagnosticsView extends StatelessWidget {
  const DiagnosticsView({super.key, this.manager});
  final DiagnosticsCubit? manager;
  @override
  Widget build(BuildContext context) {
    if (manager == null) return const Text('Диагностика недоступна');
    return BlocBuilder<DiagnosticsCubit, DiagnosticsState>(
      bloc: manager,
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Проверим профиль, движок, порты и HTTPS через прокси. Если прокси отключён, проверка временно подключит его и затем отключит.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: state.busy ? null : manager!.run,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(state.busy ? 'Проверяем…' : 'Проверить подключение'),
          ),
          const SizedBox(height: 16),
          for (final step in state.steps) _DiagnosticTile(step),
        ],
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  const _DiagnosticTile(this.step);
  final DiagnosticStep step;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: step.status == CheckStatus.checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(_icon),
      title: Text(step.title),
      subtitle: step.detail.isEmpty ? null : Text(step.detail),
    ),
  );
  IconData get _icon => switch (step.status) {
    CheckStatus.passed => Icons.check_circle_outline,
    CheckStatus.failed => Icons.error_outline,
    _ => Icons.circle_outlined,
  };
}
