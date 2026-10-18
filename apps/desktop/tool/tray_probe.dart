// Нативная проверка трея без профилей и пользовательских настроек.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:amnezia_proxy_manager/settings/tray_cubit.dart';
import 'package:amnezia_proxy_manager/settings/window_placement.dart';
import 'package:amnezia_proxy_manager/settings/window_geometry.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'tray-probe': WindowGeometry(
      const Rect.fromLTWH(40, 40, 540, 540),
      maximized: true,
    ).encode(),
  });
  await WindowPlacement.initialize(
    preferenceKey: 'tray-probe',
    showWindow: false,
  );
  runApp(const SizedBox());
  final tray = TrayCubit();
  final report = <String, Object?>{};
  try {
    await tray.start(hidden: true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    report['trayReady'] = tray.state.ready;
    report['hiddenAtStart'] = !await windowManager.isVisible();
    await tray.open();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    report['opened'] = await windowManager.isVisible();
    report['maximizedRestored'] = await windowManager.isMaximized();
    await tray.hide();
    report['hiddenAgain'] = !await windowManager.isVisible();
    final preferences = await SharedPreferences.getInstance();
    report['maximizedSaved'] =
        WindowGeometry.decode(preferences.getString('tray-probe'))?.maximized ==
        true;
    await tray.close();
    report['success'] = report.values.every((value) => value == true);
    await File(arguments.single).writeAsString(jsonEncode(report));
    exit(report['success'] == true ? 0 : 1);
  } catch (error) {
    await File(arguments.single)
        .writeAsString(jsonEncode({'error': error.runtimeType.toString()}));
    exit(1);
  }
}
