import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'settings_cubit.dart';
import 'startup_cubit.dart';
import 'vpn_options_cubit.dart';
import 'vpn_options_view.dart';
import '../features/connection/connection_cubit.dart';

class GeneralSettingsView extends StatelessWidget {
  const GeneralSettingsView({
    super.key,
    this.startup,
    this.vpn,
    this.connection,
    this.onUnblock,
  });
  final StartupCubit? startup;
  final VpnOptionsCubit? vpn;
  final ConnectionCubit? connection;
  final Future<void> Function()? onUnblock;
  @override
  Widget build(BuildContext context) => Column(
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
      if (startup != null) _startupSettings(),
      if (vpn != null) ...[
        const Divider(height: 32),
        VpnOptionsView(
          options: vpn!,
          connection: connection,
          onUnblock: onUnblock,
        ),
      ],
      const Divider(height: 32),
      const Text(
        'Восстановление соединения',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'После аварии движка или двух неудачных проверок сети приложение повторит подключение. Ручное отключение отменяет повторы.',
      ),
    ],
  );

  Widget _startupSettings() => BlocBuilder<StartupCubit, StartupOptions>(
    bloc: startup,
    builder: (context, state) => _startupSwitches(state),
  );

  Widget _startupSwitches(StartupOptions state) => Column(
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
        title: const Text('Автозапуск свёрнутым в трей'),
        subtitle: const Text('При входе в систему, без открытия окна'),
        value: state.startInTray,
        onChanged: state.busy ? null : startup!.setStartInTray,
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
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Сворачивать в трей'),
        subtitle: const Text(
          'При сворачивании и закрытии окна. Для завершения работы выберите «Выход» в меню трея.',
        ),
        value: state.minimizeToTray,
        onChanged: state.busy ? null : startup!.setMinimizeToTray,
      ),
      _message(state),
    ],
  );

  Widget _message(StartupOptions state) => state.message == null
      ? const SizedBox.shrink()
      : Text(state.message!, style: const TextStyle(fontSize: 12));
}
