import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/features/engine/engine_catalog.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_release.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object> manifest() => {
  'schemaVersion': 1,
  'cliContract': 1,
  'sourceRevision': engineSourceRevision,
  'minAppVersion': '0.1.1',
  'maxAppVersionExclusive': '0.2.0',
  'assets': engineAssetNames,
};

Map<String, Object> release(String tag, List<int> binary, {Map? contract}) {
  final description = utf8.encode(jsonEncode(contract ?? manifest()));
  Map asset(String name, List<int> bytes) => {
    'name': name,
    'size': bytes.length,
    'digest': 'sha256:${sha256.convert(bytes)}',
    'browser_download_url':
        'https://github.com/$engineRepository/releases/download/$tag/$name',
  };
  return {
    'tag_name': tag,
    'draft': false,
    'prerelease': false,
    'assets': [
      asset('engine.json', description),
      asset(engineAssetNames['windows-x64']!, binary),
    ],
  };
}

void main() {
  late Directory temporary;
  final binary = utf8.encode('тестовый пакет движка');
  setUp(
    () async => temporary = await Directory.systemTemp.createTemp(
      'amnezia-engine-test-',
    ),
  );
  tearDown(() async {
    assert(
      temporary.absolute.parent.path == Directory.systemTemp.absolute.path,
    );
    await temporary.delete(recursive: true);
  });

  http.Client client(List<Map> releases, {List<int>? received}) =>
      MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(jsonEncode(releases), 200);
        }
        if (request.url.path.endsWith('engine.json')) {
          return http.Response(jsonEncode(manifest()), 200);
        }
        return http.Response.bytes(received ?? binary, 200);
      });

  EngineManager manager(http.Client client, {bool rejectProbe = false}) =>
      EngineManager(
        client: client,
        platform: 'windows-x64',
        readVersion: () async => '0.1.1+2',
        directory: () async => temporary,
        probe: (_, _) async {
          if (rejectProbe) throw const FormatException('Неверная архитектура');
        },
      );

  test('Ошибка обновления сохраняет активный движок', () async {
    final initial = manager(client([release('v1.0.0', binary)]));
    await initial.check();
    await initial.download();
    await initial.close();
    final pointer = await File('${temporary.path}/active.json').readAsString();
    final update = manager(
      client([
        release('v1.1.0', [...binary, 1]),
      ], received: List.filled(binary.length + 1, 0)),
    );
    addTearDown(update.close);
    await update.check();
    expect(update.state.status, EngineStatus.available);
    await update.download();
    expect(update.state.status, EngineStatus.failed);
    expect(update.state.installed!.tag, 'v1.0.0');
    expect(await File('${temporary.path}/active.json').readAsString(), pointer);
  });

  test(
    'Чужое перенаправление отклоняется до запроса к чужому серверу',
    () async {
      var calls = 0;
      final engine = manager(
        MockClient((_) async {
          calls++;
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.org/releases'},
          );
        }),
      );
      addTearDown(engine.close);
      await engine.check();
      expect(engine.state.status, EngineStatus.failed);
      expect(calls, 1);
    },
  );

  test('Нет релизов — нет ложного состояния готовности', () async {
    final engine = manager(client([]));
    addTearDown(engine.close);
    await engine.check();
    expect(engine.state.status, EngineStatus.unavailable);
  });

  test(
    'Новейший совместимый выпуск выбирается по версии, не порядку API',
    () async {
      final connection = client([
        release('v1.0.0', binary),
        release('v1.2.0', binary),
        release('v1.1.0', binary),
      ]);
      addTearDown(connection.close);
      expect(
        (await EngineCatalog(
          connection,
        ).latestCompatible('0.1.1', 'windows-x64'))!.tag,
        'v1.2.0',
      );
    },
  );

  test('Скачивание, проверка, активация и повторный запуск без сети', () async {
    final engine = manager(client([release('v1.0.0', binary)]));
    await engine.check();
    expect(engine.state.status, EngineStatus.available);
    await engine.download();
    expect(engine.state.status, EngineStatus.ready);
    expect(await File('${temporary.path}/active.json').exists(), true);
    await engine.close();
    final offline = manager(
      MockClient((_) async => http.Response('offline', 503)),
    );
    addTearDown(offline.close);
    await offline.check();
    expect(offline.state.status, EngineStatus.ready);
    expect(offline.state.offline, true);
  });

  test('Подмена и несовместимый CLI не активируют пакет', () async {
    for (final rejectProbe in [false, true]) {
      final engine = manager(
        client([
          release('v1.0.0', binary),
        ], received: rejectProbe ? binary : List.filled(binary.length, 0)),
        rejectProbe: rejectProbe,
      );
      await engine.check();
      await engine.download();
      expect(engine.state.status, EngineStatus.failed);
      expect(await File('${temporary.path}/active.json').exists(), false);
      await engine.close();
    }
  });

  test('Неизвестная ревизия, контракт, диапазон и чужой URL отвергаются', () {
    final metadata = release('v1.0.0', binary);
    for (final contract in [
      manifest()..['cliContract'] = 2,
      manifest()..['sourceRevision'] = '0' * 40,
      manifest()..['minAppVersion'] = '0.2.0',
      manifest()..['maxAppVersionExclusive'] = '0.1.1',
    ]) {
      expect(
        EngineRelease.compatible(
          metadata,
          contract,
          applicationVersion: '0.1.1',
          platform: 'windows-x64',
        ),
        isNull,
      );
    }
    final assets = metadata['assets'] as List;
    (assets.last as Map)['browser_download_url'] =
        'https://example.org/engine.exe';
    expect(
      EngineRelease.compatible(
        metadata,
        manifest(),
        applicationVersion: '0.1.1',
        platform: 'windows-x64',
      ),
      isNull,
    );
  });

  test(
    'Повреждение установленного файла обнаруживается при следующем запуске',
    () async {
      final engine = manager(client([release('v1.0.0', binary)]));
      await engine.check();
      await engine.download();
      final installed = engine.state.installed!;
      final store = EngineStore(temporary, probe: (_, _) async {});
      await store
          .executable(installed)
          .writeAsBytes(List.filled(binary.length, 0));
      expect(await store.installed('0.1.1', 'windows-x64'), isNull);
      await engine.close();
    },
  );
}
