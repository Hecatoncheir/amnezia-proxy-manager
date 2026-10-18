import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:amnezia_proxy_manager/features/updates/app_updates.dart';

Map<String, dynamic> release(String tag, {bool draft = false}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': false,
  'html_url': 'https://github.com/$appRepository/releases/tag/$tag',
  'assets': [
    for (final name in appReleaseAssets)
      {
        'name': name,
        'size': 10485760,
        'digest': 'sha256:${'a' * 64}',
        'browser_download_url':
            'https://github.com/$appRepository/releases/download/$tag/$name',
      },
  ],
  'body': '- Исправления',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Версии сравниваются численно, preview предшествует обычному выпуску',
    () {
      expect(
        AppVersion.parse('v0.2.10')!.compareTo(AppVersion.parse('0.2.9+2')!),
        greaterThan(0),
      );
      expect(
        AppVersion.parse('0.3.0-rc.2')!
            .compareTo(AppVersion.parse('0.3.0-rc.10')!),
        lessThan(0),
      );
      expect(
        AppVersion.parse('0.3.0')!.compareTo(AppVersion.parse('0.3.0-rc.10')!),
        greaterThan(0),
      );
      for (final value in [
        'main',
        '01.2.3',
        'v0.2',
        '0.2.0-..',
        '0.2.0-rc.01',
      ]) {
        expect(AppVersion.parse(value), isNull);
      }
    },
  );
  test(
    'Версия берётся из включённого в сборку pubspec, включая build number',
    () async {
      final expected = RegExp(
        r'^version: (.+)$',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
      expect(await installedAppVersion(), expected);
    },
  );
  test(
    'Проверка выбирает новый полный релиз и не отправляет авторизацию сервера',
    () async {
      final updates = AppUpdates(
        readVersion: () async => '0.2.9+2',
        client: MockClient((request) async {
          expect(request.url.host, 'api.github.com');
          expect(request.url.path, '/repos/$appRepository/releases');
          expect(request.headers.containsKey('authorization'), false);
          return http.Response(
            jsonEncode([
              release('v0.2.10'),
              release('v0.2.9'),
              release('v9.0.0', draft: true),
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(updates.close);
      await updates.check();
      expect(updates.status, AppUpdateStatus.available);
      expect(updates.release!.tag, 'v0.2.10');
    },
  );
  test('Пакет выбирается по системе; чужой URL и неверный digest отклоняются', () async {
    for (final platform in [...appPackages.keys, 'unsupported']) {
      final updates = AppUpdates(
        platform: platform,
        readVersion: () async => '0.2.0',
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode([release('v0.3.0')])),
            200,
          ),
        ),
      );
      await updates.check();
      expect(updates.package?.name, appPackages[platform]);
      updates.close();
    }
    final data = release('v0.3.0');
    final asset = (data['assets'] as List).first as Map;
    asset['browser_download_url'] = 'https://example.org/package.exe';
    expect(
      AppRelease.fromJson(data)!.packages.containsKey(asset['name']),
      false,
    );
    asset['browser_download_url'] =
        'https://github.com/$appRepository/releases/download/v0.3.0/${asset['name']}';
    asset['digest'] = 'sha256:invalid';
    expect(
      AppRelease.fromJson(data)!.packages.containsKey(asset['name']),
      false,
    );
  });
  test('Неполный релиз и ссылка на посторонний адрес не принимаются', () {
    expect(AppRelease.fromJson(release('v0.3.0')..['assets'] = []), isNull);
    expect(
      AppRelease.fromJson(
        release('v0.3.0')..['html_url'] = 'https://example.org/download',
      ),
      isNull,
    );
  });
  test(
    'Ошибка GitHub допускает повтор; параллельная проверка не запускается',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final updates = AppUpdates(
        readVersion: () async => '0.2.0+2',
        client: MockClient((_) {
          calls++;
          return calls == 1
              ? response.future
              : Future.value(
                  http.Response.bytes(
                    utf8.encode(jsonEncode([release('v0.2.0')])),
                    200,
                  ),
                );
        }),
      );
      addTearDown(updates.close);
      final first = updates.check();
      await Future<void>.delayed(Duration.zero);
      await updates.check();
      expect(calls, 1);
      response.complete(http.Response('rate limit', 403));
      await first;
      expect(updates.status, AppUpdateStatus.failed);
      await updates.check();
      expect(updates.status, AppUpdateStatus.current);
    },
  );
}
