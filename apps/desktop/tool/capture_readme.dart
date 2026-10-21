// Снимки реального Flutter UI через Flutter Driver, без рабочего стола и ключей.
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> main(List<String> args) async {
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args.first);
  final output = Directory('../../docs/screenshots');
  await output.create(recursive: true);
  Future<void> shot(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await File('${output.path}/$name.png')
        .writeAsBytes(await driver.screenshot());
    stdout.writeln('Сохранён $name.png');
  }

  Future<void> tap(SerializableFinder finder) =>
      driver.tap(finder, timeout: const Duration(seconds: 10));
  Future<void> back() => tap(find.byTooltip('Назад'));
  try {
    await driver.runUnsynchronized(() async {
      await driver.waitFor(find.byTooltip('Подключить'));
      await driver.requestData('main-window');
      await shot('01-main');
      await tap(find.byTooltip('Настройки'));
      await driver.requestData('compact-window');
      await shot('02-menu');
      await tap(find.text('Движки'));
      await driver.waitForAbsent(
        find.text('Проверяем движок…'),
        timeout: const Duration(seconds: 100),
      );
      await shot('03-engine');
      await back();
      await tap(find.text('Профили'));
      await driver.requestData('profiles-window');
      await driver.waitFor(find.text('Мой профиль'));
      await shot('04-profiles');
      await tap(find.text('Из файла'));
      await shot('05-import-menu');
      await tap(find.text('Отмена'));
      await tap(find.text('По ссылке'));
      await shot('06-import-link');
      await tap(find.text('Отмена'));
      await tap(find.text('Удалить из менеджера'));
      await shot('07-profile-actions');
      await tap(find.text('Отмена'));
      await tap(find.text('Проверить профиль'));
      await driver.waitFor(
        find.text(
          'Конфигурация принята движком. VPN-подключение не запускалось.',
        ),
        timeout: const Duration(seconds: 40),
      );
      await shot('09-profile-checked');
      await back();
      await tap(find.text('Общие'));
      await driver.requestData('settings-window');
      await shot('08-settings');
      await tap(find.text('Пропускать весь трафик через VPN'));
      await driver.scrollIntoView(
        find.text('Снять блокировку интернета'),
        alignment: 0.8,
      );
      await shot('11-vpn-settings');
      await back();
      await tap(find.text('Диагностика'));
      await driver.requestData('compact-window');
      await shot('10-diagnostics');
      await back();
      await back();
      await driver.requestData('main-window');
    });
  } finally {
    await driver.close();
  }
}
