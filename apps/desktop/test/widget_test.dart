import 'package:amnezia_proxy_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Каркас не обещает соединение и переключает тему', (
    tester,
  ) async {
    await tester.pumpWidget(const ProxyManagerApp());
    expect(find.text('Не подключено • каркас приложения'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Переключить тему'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
  });
}
