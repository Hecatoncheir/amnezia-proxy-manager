import 'dart:convert';
import 'dart:io';

import 'package:amnezia_proxy_manager/features/updates/app_updates.dart';
import 'package:amnezia_proxy_manager/features/updates/updates_view.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  final bytes = utf8.encode('проверенный установщик');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('amnezia-update-test-');
    file = await File('${directory.path}/setup.exe').writeAsBytes(bytes);
  });
  tearDown(() async {
    assert(
      directory.absolute.parent.path == Directory.systemTemp.absolute.path,
    );
    await directory.delete(recursive: true);
  });

  AppUpdates model(
    List<String> events, {
    bool installed = true,
    bool fail = false,
  }) {
    final package = AppPackage(
      appPackages['windows-x64']!,
      Uri.parse('https://github.com'),
      bytes.length,
      'sha256:${sha256.convert(bytes)}',
    );
    return AppUpdates(
        platform: 'windows-x64',
        readVersion: () async => '0.1.0',
        downloadDirectory: () async => directory,
        installationDirectory: () async => installed ? directory : null,
        closeApplication: () => events.add('close'),
        launchInstaller: (_, arguments) async {
          if (fail) throw const ProcessException('setup.exe', [], 'Ошибка');
          expect(arguments, contains('/RELAUNCH'));
          expect(arguments, contains('/DIR=${directory.path}'));
          events.add('launch');
        },
      )
      ..downloadedPackage = file
      ..status = AppUpdateStatus.available
      ..release = AppRelease(
        'v0.2.0',
        Uri.parse('https://github.com'),
        'Исправления',
        AppVersion.parse('0.2.0')!,
        {package.name: package},
      );
  }

  test('Приложение закрывается после запуска установщика', () async {
    final events = <String>[];
    final updates = model(events);
    addTearDown(updates.close);
    await updates.install();
    expect(events, ['launch', 'close']);
    expect(updates.installFailed, false);
  });

  test(
    'Переносимая копия, подмена и ошибка запуска не закрывают приложение',
    () async {
      for (var scenario = 0; scenario < 3; scenario++) {
        await file.writeAsBytes(bytes);
        final events = <String>[];
        final updates = model(
          events,
          installed: scenario != 0,
          fail: scenario == 2,
        );
        if (scenario == 1) {
          await file.writeAsBytes(List.filled(bytes.length, 0));
        }
        await updates.install();
        expect(events, isEmpty);
        expect(updates.installFailed, true);
        await updates.close();
      }
    },
  );

  testWidgets('Установка требует подтверждения, отмена не запускает Setup', (
    tester,
  ) async {
    final events = <String>[];
    final updates = model(events);
    addTearDown(updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UpdatesView(controller: updates)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить и перезапустить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    expect(updates.installing, false);
  });
}
