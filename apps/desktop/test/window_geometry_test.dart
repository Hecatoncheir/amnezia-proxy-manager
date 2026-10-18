import 'dart:ui';

import 'package:amnezia_proxy_manager/settings/window_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = Rect.fromLTWH(0, 0, 1920, 1040);
  test('Первый запуск: размер с примера, окно в центре рабочей области', () {
    final bounds = fitWindowToDisplays(null, [screen]);
    expect(bounds.size, const Size(540, 840));
    expect(bounds.center, screen.center);
  });
  test('Размер, координаты и развёрнутое состояние сохраняются', () {
    const saved = WindowGeometry(
      Rect.fromLTWH(140, 80, 620, 900),
      maximized: true,
    );
    final restored = WindowGeometry.decode(saved.encode())!;
    expect(restored.bounds, saved.bounds);
    expect(restored.maximized, true);
    expect(fitWindowToDisplays(restored.bounds, [screen]), saved.bounds);
  });
  test('Отключённый монитор и слишком большое окно возвращаются на экран', () {
    final bounds = fitWindowToDisplays(
      const Rect.fromLTWH(3000, -900, 2500, 1500),
      [screen],
    );
    expect(bounds, screen);
  });
  test('Второй монитор с отрицательными координатами сохраняется', () {
    const secondary = Rect.fromLTWH(-1280, 0, 1280, 1024);
    const saved = Rect.fromLTWH(-1000, 100, 540, 840);
    expect(fitWindowToDisplays(saved, [screen, secondary]), saved);
  });
  test(
    'Маленький экран ограничивает размер, испорченные настройки игнорируются',
    () {
      const small = Rect.fromLTWH(0, 0, 320, 480);
      expect(fitWindowToDisplays(null, [small]), small);
      for (final source in [
        null,
        '',
        '{}',
        '[]',
        '{"x":0,"y":0,"width":-1,"height":2}',
      ]) {
        expect(WindowGeometry.decode(source), isNull);
      }
    },
  );
}
