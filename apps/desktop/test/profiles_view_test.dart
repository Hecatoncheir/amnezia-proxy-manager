import 'package:amnezia_proxy_manager/features/engine/download_ring.dart';
import 'package:amnezia_proxy_manager/features/profiles/profile_vault.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_cubit.dart';
import 'package:amnezia_proxy_manager/features/profiles/profiles_view.dart';
import 'package:amnezia_proxy_manager/theme/gruvbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/profile_fixtures.dart';

class _Vault implements ProfileVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next, {required String? expected}) async {
    value = next;
  }
}

void main() {
  testWidgets('Импорт ссылки, проверка и удаление; секреты не отображаются', (
    tester,
  ) async {
    final vault = _Vault();
    final manager = ProfilesCubit(vault: vault, validate: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        theme: gruvboxTheme(Brightness.dark),
        home: Scaffold(
          body: ListView(children: [ProfilesView(manager: manager)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ссылка vpn://'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).last;
    expect(tester.widget<TextField>(field).obscureText, true);
    await tester.enterText(field, vpnUri(exportJson()));
    await tester.tap(find.text('Импортировать'));
    await tester.pumpAndSettle();
    expect(find.text('Профиль 1'), findsOneWidget);
    expect(find.textContaining(testPrivateKey), findsNothing);
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Конфигурация принята'), findsOneWidget);
    await tester.tap(find.text('Удалить').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Удалить').last);
    await tester.pumpAndSettle();
    expect(vault.value, isNull);
    expect(find.text('Профиль не выбран'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Карточка профилей и индикатор помещаются в узком окне с крупным текстом',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final manager = ProfilesCubit(vault: _Vault(), validate: (_) async {});
      await tester.pumpWidget(
        MaterialApp(
          theme: gruvboxTheme(Brightness.light),
          home: Scaffold(
            body: ListView(
              children: [
                const Center(child: DownloadRing(progress: .34)),
                ProfilesView(manager: manager),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('34%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
