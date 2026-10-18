import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/features/engine/engine_catalog.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_manager.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_release.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> release({String tag = engineTag}) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': false,
  'assets': [
    for (final platform in engineAssetNames.keys)
      {
        'name': engineAssetNames[platform],
        'size': 4690621,
        'digest':
            'sha256:${enginePolicy['packages'][platform]['archiveSHA256']}',
        'browser_download_url':
            'https://github.com/$engineRepository/releases/download/$tag/${engineAssetNames[platform]}',
      },
  ],
};

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('awg проверка '),
  );
  tearDown(() async => root.delete(recursive: true));
  EngineManager manager(http.Client client) => EngineManager(
    client: client,
    platform: 'windows-x64',
    readVersion: () async => '0.1.1',
    directory: () async => root,
  );

  test('Выбирается проверенная версия, будущие выпуски пропускаются', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/repos/bropines/awg-wireproxy/releases');
      return http.Response(
        jsonEncode([release(tag: 'v3.0.0'), release()]),
        200,
      );
    });
    addTearDown(client.close);
    final result = await EngineCatalog(client)
        .latestCompatible('0.1.1', 'windows-x64');
    expect(result!.tag, engineTag);
    expect(result.binaryName, 'wireproxy.exe');
    expect(calls, 1);
  });

  test('Подмена хеша, URL, draft и неверная платформа отклоняются', () {
    final cases = [
      release()..['draft'] = true,
      release()..['prerelease'] = true,
    ];
    final hash = release();
    (hash['assets'] as List).first['digest'] = 'sha256:${'0' * 64}';
    cases.add(hash);
    final url = release();
    (url['assets'] as List).first['browser_download_url'] =
        'https://example.org/engine.zip';
    cases.add(url);
    for (final value in cases) {
      expect(
        EngineRelease.compatible(
          value,
          enginePolicy,
          applicationVersion: '0.1.1',
          platform: 'windows-x64',
        ),
        isNull,
      );
    }
    expect(
      EngineRelease.compatible(
        release(),
        enginePolicy,
        applicationVersion: '0.2.0',
        platform: 'windows-x64',
      ),
      isNull,
    );
    expect(
      EngineRelease.compatible(
        release(),
        enginePolicy,
        applicationVersion: '0.1.1',
        platform: 'linux-arm64',
      ),
      isNull,
    );
  });

  test('Нет релизов — нет ложной готовности', () async {
    final engine = manager(MockClient((_) async => http.Response('[]', 200)));
    addTearDown(engine.close);
    await engine.check();
    expect(engine.state.status, EngineStatus.unavailable);
  });

  test(
    'Автоподготовка объединяет запросы и отклоняет повреждённую загрузку',
    () async {
      var catalogs = 0, downloads = 0;
      final engine = manager(
        MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            catalogs++;
            return http.Response(jsonEncode([release()]), 200);
          }
          downloads++;
          return http.Response.bytes([1, 2], 200);
        }),
      );
      addTearDown(engine.close);
      final first = engine.ensureReady();
      final second = engine.ensureReady();
      expect(identical(first, second), true);
      await expectLater(first, throwsStateError);
      expect(catalogs, 1);
      expect(downloads, 1);
      expect(engine.state.installed, isNull);
      await expectLater(engine.ensureReady(), throwsStateError);
      expect(downloads, 2);
    },
  );

  test(
    'Процент обновляется по полученным байтам, затем начинается проверка',
    () async {
      const total = 4690621;
      const chunk = 1024 * 1024;
      final engine = manager(
        MockClient.streaming((request, _) async {
          if (request.url.host == 'api.github.com') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode([release()]))),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable([
              List.filled(chunk, 0),
              List.filled(chunk, 0),
              List.filled(total - chunk * 2, 0),
            ]),
            200,
            contentLength: total,
          );
        }),
      );
      addTearDown(engine.close);
      final states = <EngineState>[];
      final subscription = engine.stream.listen(states.add);
      await engine.check();
      await engine.download();
      await subscription.cancel();
      final percentages = states
          .where((s) => s.status == EngineStatus.downloading)
          .map((s) => (s.progress * 100).floor())
          .toList();
      expect(percentages, containsAllInOrder([0, 22, 44, 100]));
      expect(states.any((s) => s.status == EngineStatus.installing), true);
      // Синтетический поток не совпадает с закреплённым SHA-256 и не активируется.
      expect(engine.state.status, EngineStatus.failed);
    },
  );

  test('Чужой сервер не запрашивается после перенаправления', () async {
    var calls = 0;
    final engine = manager(
      MockClient((_) async {
        calls++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://example.org/'},
        );
      }),
    );
    addTearDown(engine.close);
    await engine.check();
    expect(engine.state.status, EngineStatus.failed);
    expect(calls, 1);
  });

  test('Оборванная загрузка сохраняет старую запись', () async {
    final pointer = File('${root.path}/active.json');
    await pointer.writeAsString('{"old":true}');
    final engine = manager(
      MockClient(
        (request) async => request.url.host == 'api.github.com'
            ? http.Response(jsonEncode([release()]), 200)
            : http.Response.bytes([1, 2], 200),
      ),
    );
    addTearDown(engine.close);
    await engine.check();
    await engine.download();
    expect(engine.state.status, EngineStatus.failed);
    expect(await pointer.readAsString(), '{"old":true}');
    expect(
      root.listSync().whereType<File>().any((f) => f.path.endsWith('.part')),
      false,
    );
  });

  for (final zip in [true, false]) {
    test(
      'Распаковка ${zip ? 'ZIP' : 'tar.gz'} без извлечения посторонних путей',
      () async {
        final binary = utf8.encode('проверяемый файл');
        final archive = Archive()
          ..addFile(
            ArchiveFile('wireproxy${zip ? '.exe' : ''}', binary.length, binary),
          )
          ..addFile(ArchiveFile('LICENSE', 3, [73, 83, 67]))
          ..addFile(ArchiveFile('../outside', 1, [0]));
        final bytes = zip
            ? ZipEncoder().encode(archive)
            : gzip.encode(TarEncoder().encode(archive));
        final sum = sha256.convert(bytes).toString();
        final fixture = EngineRelease(
          engineTag,
          engineSourceRevision,
          EngineAsset(
            zip ? 'fixture.zip' : 'fixture.tar.gz',
            Uri.parse('https://github.com/'),
            bytes.length,
            sum,
          ),
          {
            'packages': {
              'test': {
                'archiveSHA256': sum,
                'binarySHA256': sha256.convert(binary).toString(),
                'binarySize': binary.length,
              },
            },
          },
        );
        final store = EngineStore(root, probe: (_, _) async {});
        final partial = File('${root.path}/archive.part');
        await partial.writeAsBytes(bytes);
        final executable = await store.activate(
          partial,
          fixture,
          zip ? 'windows-x64' : 'linux-x64',
        );
        expect(await executable.readAsBytes(), binary);
        expect(
          await File('${executable.parent.path}/LICENSE').readAsString(),
          'ISC',
        );
        expect(await File('${root.path}/outside').exists(), false);
        await executable.writeAsBytes([0]);
        expect(await store.valid(executable, fixture.binary), false);
      },
    );
  }

  test(
    'Настоящий GitHub Release: загрузка, CLI, повторный запуск без сети',
    () async {
      final engine = manager(http.Client());
      addTearDown(engine.close);
      await engine.ensureReady();
      expect(engine.state.status, EngineStatus.ready);
      final store = EngineStore(root);
      final restored = await store.installed('0.1.1', 'windows-x64');
      expect(restored!.tag, engineTag);
      final offline = manager(MockClient((_) async => http.Response('', 503)));
      addTearDown(offline.close);
      await offline.check();
      expect(offline.state.status, EngineStatus.ready);
      expect(offline.state.offline, true);
      await store.executable(restored).writeAsBytes([0]);
      expect(await store.installed('0.1.1', 'windows-x64'), isNull);
    },
    skip: !const bool.fromEnvironment('LIVE_ENGINE') || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
