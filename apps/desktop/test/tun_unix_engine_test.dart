import 'dart:io';
import 'dart:ffi';

import 'package:amnezia_proxy_manager/features/engine/engine_release.dart';
import 'package:amnezia_proxy_manager/features/engine/engine_store.dart';
import 'package:amnezia_proxy_manager/features/engine/tun_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final archiveRoot = Platform.environment['APM_TEST_TUN_ARCHIVES_DIR'];
  for (final platform in ['linux-x64', 'macos-arm64']) {
    test(
      'Настоящий TAR.GZ TUN для $platform: размер, хеш, архитектура и лицензия',
      () async {
        final root = await Directory.systemTemp.createTemp('apm-tun-unix-');
        addTearDown(() => root.delete(recursive: true));
        final name = tunPolicy['assets'][platform] as String;
        final archive = File('$archiveRoot/$name');
        final release = EngineRelease.compatible(
          {
            'tag_name': tunPolicy['tag'],
            'draft': false,
            'prerelease': false,
            'assets': [
              {
                'name': name,
                'size': await archive.length(),
                'digest':
                    'sha256:${tunPolicy['packages'][platform]['archiveSHA256']}',
                'browser_download_url':
                    'https://github.com/SagerNet/sing-box/releases/download/${tunPolicy['tag']}/$name',
              },
            ],
          },
          tunPolicy,
          applicationVersion: '0.1.14',
          platform: platform,
          policy: tunPolicy,
        );
        expect(release, isNotNull);
        final store = EngineStore(
          root,
          policy: tunPolicy,
          probe: (file, target) async {
            expect(await engineArchitectureMatches(file, target), true);
            if (_nativeTarget(target)) {
              await verifyEngineExecutable(file, target, policy: tunPolicy);
            }
          },
        );
        await store.activate(archive, release!, platform);
        expect(await store.installed('0.1.14', platform), isNotNull);
        expect(
          await File('${store.executable(release).parent.path}/LICENSE')
              .exists(),
          true,
        );
      },
      skip: archiveRoot == null
          ? 'Нужен APM_TEST_TUN_ARCHIVES_DIR с проверяемыми TAR.GZ'
          : false,
    );
  }
}

bool _nativeTarget(String target) =>
    (Abi.current() == Abi.linuxX64 && target == 'linux-x64') ||
    (Abi.current() == Abi.macosArm64 && target == 'macos-arm64');
