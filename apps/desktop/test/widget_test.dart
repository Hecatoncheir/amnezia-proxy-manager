import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_view.dart';
import 'package:amnezia_proxy_manager/main.dart';
import 'package:amnezia_proxy_manager/settings/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryVault implements ProfileVault {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String? next, {required String? expected}) async {}
}

void main() {
  testWidgets('Профили доступны из меню повторно и не закрывают хранилище', (
    tester,
  ) async {
    final profiles = ProfilesCubit(
      vault: _MemoryVault(),
      validate: (_) async {},
    );
    await tester.pumpWidget(ProxyManagerApp(profiles: profiles));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilesView), findsNothing);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Меню'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Профили'));
      await tester.pumpAndSettle();
      expect(find.text('Добавить'), findsOneWidget);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(profiles.isClosed, isFalse);
      expect(find.byType(ProfilesView), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
  test('Тема переключается через Cubit', () async {
    final cubit = SettingsCubit();
    expect(cubit.state, ThemeMode.dark);
    cubit.toggleTheme();
    expect(cubit.state, ThemeMode.light);
    cubit.toggleTheme();
    expect(cubit.state, ThemeMode.dark);
    await cubit.close();
  });

  testWidgets('Настройки меняют тему, подключение не имитируется', (
    tester,
  ) async {
    await tester.pumpWidget(const ProxyManagerApp());
    expect(find.text('Отключено'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.power_settings_new),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('— КБ/с'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Меню'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
    expect(find.text('ЛОКАЛЬНЫЙ ПРОКСИ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Узкое окно и увеличенный текст не вызывают переполнения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const ProxyManagerApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Настройки помещаются в минимальное окно', (tester) async {
    tester.view.physicalSize = const Size(380, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const ProxyManagerApp());
    await tester.tap(find.byTooltip('Меню'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Проверить обновления'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
