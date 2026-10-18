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
  Future<void> section(String title) async {
    await tap(find.byTooltip('Меню'));
    await tap(find.text(title));
  }

  try {
    await driver.waitFor(find.byTooltip('Подключить'));
    await shot('01-main');
    await tap(find.byTooltip('Меню'));
    await shot('02-menu');
    await tap(find.text('Движки'));
    await driver.waitFor(
      find.text('Готов к работе · v26.7.28'),
      timeout: const Duration(seconds: 60),
    );
    await shot('03-engine');
    await tap(find.text('Готово'));
    await section('Профили');
    await driver.waitFor(find.text('Мой профиль'));
    await shot('04-profiles');
    await tap(find.byTooltip('Добавить профиль'));
    await shot('05-import-menu');
    await tap(find.text('По ссылке'));
    await shot('06-import-link');
    await tap(find.text('Отмена'));
    await tap(find.byTooltip('Действия с профилем'));
    await shot('07-profile-actions');
    await tap(find.text('Проверить'));
    await driver.waitFor(
      find.text(
        'Конфигурация принята движком. VPN-подключение не запускалось.',
      ),
    );
    await shot('09-profile-checked');
    await tap(find.text('Готово'));
    await section('Настройки');
    await shot('08-settings');
    await tap(find.text('Готово'));
  } finally {
    await driver.close();
  }
}
