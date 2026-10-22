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
  final catalogStatus = manager.state.status.name;
  final offline = manager.state.offline;
  await manager.download();
  final restored = await EngineStore(root).installed('0.1.1', manager.platform);
  final passed = manager.state.status == EngineStatus.ready && restored != null;
  await root.create(recursive: true);
  final report = jsonEncode({
    'passed': passed,
    'catalog': 'github',
    'catalogStatus': catalogStatus,
    'offline': offline,
    'platform': manager.platform,
    'status': manager.state.status.name,
    'restored': restored?.tag,
  });
  await File('${root.path}/probe-result.json').writeAsString(report);
  stdout.writeln(report);
  await manager.close();
  exit(passed ? 0 : 1);
}
