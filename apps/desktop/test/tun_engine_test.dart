import 'dart:io';

import 'package:amnezia_proxy_manager/features/engine/engine_release.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:amnezia_proxy_manager/features/engine/tun_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final archive = Platform.environment['APM_TEST_TUN_ARCHIVE'];
  test(
    'Настоящий пакет TUN устанавливается и запускается без соседних DLL',
    () async {
      final root = await Directory.systemTemp.createTemp('apm-tun-probe-');
      addTearDown(() => root.delete(recursive: true));
      final file = File(archive!);
      final name = tunPolicy['assets']['windows-x64'] as String;
      final release = EngineRelease.compatible(
        {
          'tag_name': tunPolicy['tag'],
          'draft': false,
          'prerelease': false,
          'assets': [
            {
              'name': name,
              'size': await file.length(),
              'digest':
                  'sha256:${tunPolicy['packages']['windows-x64']['archiveSHA256']}',
              'browser_download_url':
                  'https://github.com/SagerNet/sing-box/releases/download/${tunPolicy['tag']}/$name',
            },
          ],
        },
        tunPolicy,
        applicationVersion: '0.1.14',
        platform: 'windows-x64',
        policy: tunPolicy,
      );
      expect(release, isNotNull);
      final store = EngineStore(root, policy: tunPolicy);
      await store.activate(file, release!, 'windows-x64');
      expect(await store.installed('0.1.14', 'windows-x64'), isNotNull);
      expect(
        await File('${store.executable(release).parent.path}/LICENSE').exists(),
        true,
      );
      expect(
        await File('${store.executable(release).parent.path}/libcronet.dll')
            .exists(),
        false,
      );
    },
    skip: !Platform.isWindows || archive == null
        ? 'Нужен APM_TEST_TUN_ARCHIVE с проверяемым Windows-архивом'
        : false,
  );
}
