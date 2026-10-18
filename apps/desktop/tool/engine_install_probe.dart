// Локальная проверка runtime настоящим бинарником; HTTP-каталог контролируемый.
import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_release.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final binary = await File(arguments[0]).readAsBytes();
  final root = Directory(arguments[1]);
  const tag = 'v0.0.1';
  final manifest = utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'cliContract': 1,
      'sourceRevision': engineSourceRevision,
      'minAppVersion': '0.1.1',
      'maxAppVersionExclusive': '0.2.0',
      'assets': engineAssetNames,
    }),
  );
  Map asset(String name, List<int> data) => {
    'name': name,
    'size': data.length,
    'digest': 'sha256:${sha256.convert(data)}',
    'browser_download_url':
        'https://github.com/$engineRepository/releases/download/$tag/$name',
  };
  final catalog = [
    {
      'tag_name': tag,
      'draft': false,
      'prerelease': false,
      'assets': [
        asset('engine.json', manifest),
        asset(engineAssetNames['windows-x64']!, binary),
      ],
    },
  ];
  final manager = EngineManager(
    platform: 'windows-x64',
    readVersion: () async => '0.1.1',
    directory: () async => root,
    client: MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode(catalog), 200);
      }
      if (request.url.path.endsWith('engine.json')) {
        return http.Response.bytes(manifest, 200);
      }
      return http.Response.bytes(binary, 200);
    }),
  );
  await manager.check();
  await manager.download();
  final restored = await EngineStore(root).installed('0.1.1', 'windows-x64');
  final passed = manager.state.status == EngineStatus.ready && restored != null;
  await File('${root.path}/probe-result.json').writeAsString(
    jsonEncode({
      'passed': passed,
      'catalog': 'fixture',
      'nativeBinary': true,
      'status': manager.state.status.name,
      'restored': restored?.tag,
    }),
  );
  await manager.close();
  exit(passed ? 0 : 1);
}
