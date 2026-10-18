import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:amnezia_proxy_manager/features/updates/app_updates.dart';

void main() {
  late Directory directory;
  final bytes = utf8.encode('проверенный пакет');
  final hash = sha256.convert(bytes).toString();
  final package = AppPackage(
    'AmneziaProxyManager-Setup-windows-x64.exe',
    Uri.parse(
      'https://github.com/$appRepository/releases/download/v0.3.0/AmneziaProxyManager-Setup-windows-x64.exe',
    ),
    bytes.length,
    'sha256:$hash',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('space-update-test-');
  });
  tearDown(() async {
    assert(
      directory.absolute.parent.path == Directory.systemTemp.absolute.path,
    );
    await directory.delete(recursive: true);
  });
  AppUpdates model(http.Client client) =>
      AppUpdates(
          client: client,
          downloadDirectory: () async => directory,
          platform: 'windows-x64',
        )
        ..status = AppUpdateStatus.available
        ..release = AppRelease(
          'v0.3.0',
          package.url,
          '',
          AppVersion.parse('0.3.0')!,
          {package.name: package},
        );

  test('Проверенная загрузка используется повторно без сети; повреждённая скачивается снова', () async {
    var calls = 0;
    final updates = model(
      MockClient((_) async {
        calls++;
        return http.Response.bytes(bytes, 200);
      }),
    );
    addTearDown(updates.close);
    await updates.download();
    expect(updates.downloadFailed, false);
    expect(await updates.downloadedPackage!.readAsBytes(), bytes);
    await updates.download();
    expect(calls, 1);
    await updates.downloadedPackage!.writeAsBytes(List.filled(bytes.length, 0));
    await updates.download();
    expect(calls, 2);
    expect(await updates.downloadedPackage!.readAsBytes(), bytes);
  });
  test('Частичный файл докачивается только с правильным диапазоном', () async {
    final partial = File('${directory.path}/$hash-${package.name}.part');
    await partial.writeAsBytes(bytes.take(5).toList());
    final updates = model(
      MockClient((request) async {
        expect(request.headers['Range'], 'bytes=5-');
        return http.Response.bytes(
          bytes.sublist(5),
          206,
          headers: {
            'content-range': 'bytes 5-${bytes.length - 1}/${bytes.length}',
          },
        );
      }),
    );
    addTearDown(updates.close);
    await updates.download();
    expect(updates.downloadFailed, false);
    expect(await updates.downloadedPackage!.readAsBytes(), bytes);
  });
  test('Если Range проигнорирован, файл записывается заново', () async {
    await File('${directory.path}/$hash-${package.name}.part')
        .writeAsBytes(bytes.take(5).toList());
    final updates = model(
      MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    addTearDown(updates.close);
    await updates.download();
    expect(await updates.downloadedPackage!.readAsBytes(), bytes);
  });
  test('Неполный ответ сохраняется для повтора; неверная сумма и превышение удаляются', () async {
    var calls = 0;
    final updates = model(
      MockClient((_) async {
        calls++;
        return http.Response.bytes(
          calls == 1 ? bytes.take(5).toList() : List.filled(bytes.length, 0),
          200,
        );
      }),
    );
    addTearDown(updates.close);
    // Без Content-Length оборванный поток допускает сохранение принятой части.
    final short = model(
      MockClient.streaming(
        (_, body) async =>
            http.StreamedResponse(Stream.value(bytes.take(5).toList()), 200),
      ),
    );
    addTearDown(short.close);
    await short.download();
    expect(short.downloadFailed, true);
    expect(
      await File('${directory.path}/$hash-${package.name}.part').length(),
      5,
    );
    await updates.download();
    expect(updates.downloadFailed, true);
    await updates.download();
    expect(updates.downloadedPackage, isNull);
    expect(
      await File('${directory.path}/$hash-${package.name}.part').exists(),
      false,
    );
    final oversized = model(
      MockClient.streaming(
        (_, body) async =>
            http.StreamedResponse(Stream.value([...bytes, 0]), 200),
      ),
    );
    addTearDown(oversized.close);
    await oversized.download();
    expect(oversized.downloadFailed, true);
    expect(
      await File('${directory.path}/$hash-${package.name}.part').exists(),
      false,
    );
  });
  test('Постороннее перенаправление отклоняется до второго запроса', () async {
    var calls = 0;
    final updates = model(
      MockClient((_) async {
        calls++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://example.org/package'},
        );
      }),
    );
    addTearDown(updates.close);
    await updates.download();
    expect(updates.downloadFailed, true);
    expect(calls, 1);
  });
  test('Неверный Content-Range не дописывает частичный файл', () async {
    final partial = File('${directory.path}/$hash-${package.name}.part');
    await partial.writeAsBytes(bytes.take(5).toList());
    final updates = model(
      MockClient(
        (_) async => http.Response.bytes(
          bytes.sublist(5),
          206,
          headers: {'content-range': 'bytes 0-4/5'},
        ),
      ),
    );
    addTearDown(updates.close);
    await updates.download();
    expect(updates.downloadFailed, true);
    expect(updates.downloadedPackage, isNull);
    expect(await partial.length(), 5);
  });
  test(
    'Повторное нажатие и проверка выпуска не запускают второй запрос',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final updates = model(
        MockClient((_) {
          calls++;
          return response.future;
        }),
      );
      addTearDown(updates.close);
      final first = updates.download();
      while (calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await updates.download();
      await updates.check();
      expect(calls, 1);
      response.complete(http.Response.bytes(bytes, 200));
      await first;
      expect(updates.downloadFailed, false);
      expect(updates.downloadedPackage, isNotNull);
    },
  );
}
