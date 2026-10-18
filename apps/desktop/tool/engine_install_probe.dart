// Проверка загрузки из настоящего GitHub Release в отдельный каталог.
import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:flutter/widgets.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(arguments.single);
  final manager = EngineManager(
    readVersion: () async => '0.1.1',
    directory: () async => root,
  );
  await manager.check();
  await manager.download();
  final restored = await EngineStore(root).installed('0.1.1', manager.platform);
  final passed = manager.state.status == EngineStatus.ready && restored != null;
  await root.create(recursive: true);
  await File('${root.path}/probe-result.json').writeAsString(
    jsonEncode({
      'passed': passed,
      'catalog': 'github',
      'status': manager.state.status.name,
      'restored': restored?.tag,
    }),
  );
  await manager.close();
  exit(passed ? 0 : 1);
}
