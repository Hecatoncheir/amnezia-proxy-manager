import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/dashboard/dashboard_page.dart';
import 'features/engine/engine_manager.dart';
import 'features/engine/xray_policy.dart';
import 'features/profiles/profile_validator.dart';
import 'features/profiles/profile_vault.dart';
import 'features/profiles/profiles_cubit.dart';
import 'settings/settings_cubit.dart';
import 'settings/window_placement.dart';
import 'settings/startup_cubit.dart';
import 'settings/tray_cubit.dart';
import 'theme/gruvbox.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  await WindowPlacement.initialize(showWindow: false);
  final tray = TrayCubit();
  WindowPlacement.afterClose = tray.close;
  WindowPlacement.tryHideToTray = () => tray.minimizeIfEnabled(
    preferences.getBool(StartupCubit.minimizeToTrayKey) ?? false,
  );
  WindowPlacement.tryCloseToTray = () =>
      tray.minimizeIfEnabled(StartupCubit.shouldCloseToTray(preferences));
  await tray.start(
    hidden: StartupCubit.shouldStartInTray(arguments, preferences),
  );
  final engine = EngineManager();
  final xray = EngineManager(policy: xrayPolicy);
  final profiles = ProfilesCubit(
    vault: SystemProfileVault(),
    validate: EngineProfileValidator(engine, xray: xray).validate,
  );
  runApp(ProxyManagerApp(engine: engine, xray: xray, profiles: profiles));
}

class ProxyManagerApp extends StatelessWidget {
  const ProxyManagerApp({super.key, this.engine, this.profiles, this.xray});
  final EngineManager? engine;
  final EngineManager? xray;
  final ProfilesCubit? profiles;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SettingsCubit(),
    child: BlocBuilder<SettingsCubit, ThemeMode>(
      builder: (context, mode) => MaterialApp(
        title: 'Amnezia Proxy',
        debugShowCheckedModeBanner: false,
        theme: gruvboxTheme(Brightness.light),
        darkTheme: gruvboxTheme(Brightness.dark),
        themeMode: mode,
        themeAnimationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        home: DashboardPage(engine: engine, xray: xray, profiles: profiles),
      ),
    ),
  );
}
