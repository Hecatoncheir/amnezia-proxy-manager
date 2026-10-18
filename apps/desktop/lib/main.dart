import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/dashboard/dashboard_page.dart';
import 'features/engine/engine_manager.dart';
import 'settings/settings_cubit.dart';
import 'settings/window_placement.dart';
import 'theme/gruvbox.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowPlacement.initialize();
  runApp(ProxyManagerApp(engine: EngineManager()));
}

class ProxyManagerApp extends StatelessWidget {
  const ProxyManagerApp({super.key, this.engine});
  final EngineManager? engine;

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
        home: DashboardPage(engine: engine),
      ),
    ),
  );
}
