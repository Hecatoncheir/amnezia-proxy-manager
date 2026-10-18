// Испытание сохранения окна через реальные платформенные плагины.
import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/settings/window_placement.dart';
import 'package:amnezia_proxy_manager/settings/window_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> arguments) async {
  try {
    await _probe(arguments);
  } catch (_) {
    if (arguments.length > 1) {
      await File('${arguments[1]}.error.json')
          .writeAsString(jsonEncode({'error': 'window_geometry_failed'}));
    }
    exit(2);
  }
}

Future<void> _probe(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowPlacement.initialize(preferenceKey: 'window-placement-probe-v2');
  runApp(const SizedBox());
  if (arguments.first == 'write') {
    final current = await windowManager.getBounds();
    await windowManager.setBounds(
      Rect.fromLTWH(
        current.left + 10,
        current.top + 10,
        (current.width - 20)
            .clamp(minimumWindowSize.width, current.width)
            .toDouble(),
        (current.height - 20)
            .clamp(minimumWindowSize.height, current.height)
            .toDouble(),
      ),
    );
    await WindowPlacement.flush();
  }
  final bounds = await windowManager.getBounds();
  await File(arguments[1]).writeAsString(
    jsonEncode({
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    }),
  );
  await windowManager.close();
}
