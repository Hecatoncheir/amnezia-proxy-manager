import 'package:amnezia_proxy_manager/features/engine/engine_release.dart';
import 'package:amnezia_proxy_manager/features/engine/xray_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_catalog.dart';

void main() {
  test('Каталог ищет закреплённый prerelease на следующей странице', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.queryParameters['per_page'], '10');
      expect(request.url.queryParameters['page'], '$calls');
      if (calls == 1) {
        return http.Response(
          jsonEncode(
            List.generate(
              10,
              (i) => {
                'tag_name': 'v99.1.${i + 1}',
                'draft': false,
                'prerelease': true,
              },
            ),
          ),
          200,
        );
      }
      const platform = 'windows-x64';
      final name = xrayPolicy['assets'][platform];
      return http.Response(
        jsonEncode([
          {
            'tag_name': xrayPolicy['tag'],
            'draft': false,
            'prerelease': true,
            'assets': [
              {
                'name': name,
                'size': 20987981,
                'digest':
                    'sha256:${xrayPolicy['packages'][platform]['archiveSHA256']}',
                'browser_download_url':
                    'https://github.com/XTLS/Xray-core/releases/download/${xrayPolicy['tag']}/$name',
              },
            ],
          },
        ]),
        200,
      );
    });
    addTearDown(client.close);
    final release = await EngineCatalog(
      client,
      policy: xrayPolicy,
    ).latestCompatible('0.1.1', 'windows-x64');
    expect(release?.tag, xrayPolicy['tag']);
    expect(calls, 2);
  });
  test('Проверенный Xray отделён от AWG: URL, пакет и бинарник', () {
    for (final platform in ['windows-x64', 'linux-x64', 'macos-arm64']) {
      final name = xrayPolicy['assets'][platform];
      final data = {
        'tag_name': xrayPolicy['tag'],
        'draft': false,
        'prerelease': true,
        'assets': [
          {
            'name': name,
            'size': 20913304,
            'digest':
                'sha256:${xrayPolicy['packages'][platform]['archiveSHA256']}',
            'browser_download_url':
                'https://github.com/XTLS/Xray-core/releases/download/${xrayPolicy['tag']}/$name',
          },
        ],
      };
      final release = EngineRelease.compatible(
        data,
        xrayPolicy,
        applicationVersion: '0.1.1',
        platform: platform,
        policy: xrayPolicy,
      );
      expect(release!.family, 'xray');
      final foreignPreview = Map<String, dynamic>.from(data)
        ..['tag_name'] = 'v99.1.1';
      expect(
        EngineRelease.compatible(
          foreignPreview,
          xrayPolicy,
          applicationVersion: '0.1.1',
          platform: platform,
          policy: xrayPolicy,
        ),
        isNull,
      );
      final noPreviewPolicy = Map<String, dynamic>.from(xrayPolicy)
        ..['allowPrerelease'] = false;
      expect(
        EngineRelease.compatible(
          data,
          noPreviewPolicy,
          applicationVersion: '0.1.1',
          platform: platform,
          policy: noPreviewPolicy,
        ),
        isNull,
      );
      expect(
        release.binaryName,
        platform == 'windows-x64' ? 'xray.exe' : 'xray',
      );
      expect(
        EngineRelease.compatible(
          data,
          enginePolicy,
          applicationVersion: '0.1.1',
          platform: platform,
        ),
        isNull,
      );
      (data['assets'] as List).first['digest'] = 'sha256:${'0' * 64}';
      expect(
        EngineRelease.compatible(
          data,
          xrayPolicy,
          applicationVersion: '0.1.1',
          platform: platform,
          policy: xrayPolicy,
        ),
        isNull,
      );
    }
  });
}
