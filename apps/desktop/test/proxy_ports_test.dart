import 'package:amnezia_proxy_manager/settings/proxy_ports.dart';
import 'package:amnezia_proxy_manager/settings/proxy_ports_cubit.dart';
import 'package:amnezia_proxy_manager/features/dashboard/proxy_ports_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Диапазон, одинаковые порты и неверные значения', () {
    expect(ProxyPorts.parse('1', '65535').http, 65535);
    for (final text in ['', '0', '-1', '65536', '12a']) {
      expect(() => ProxyPorts.parse(text, '8080'), throwsFormatException);
    }
    expect(() => ProxyPorts.parse('8080', '8080'), throwsFormatException);
  });

  test('Сохранение пары и восстановление при следующем запуске', () async {
    final first = ProxyPortsCubit();
    await first.load();
    expect(first.state.saved.socks, 1080);
    first.editSocks('19080');
    first.editHttp('19081');
    final ports = await first.forConnection();
    expect(ports.socks, 19080);
    expect(ports.http, 19081);
    final next = ProxyPortsCubit();
    await next.load();
    expect(next.state.socks, '19080');
    expect(next.state.http, '19081');
    await first.close();
    await next.close();
  });

  test(
    'Неверный черновик не меняет сохранённую пару и блокирует подключение',
    () async {
      final cubit = ProxyPortsCubit();
      addTearDown(cubit.close);
      await cubit.load();
      cubit.editSocks('8080');
      expect(await cubit.save(), false);
      expect(cubit.state.error, contains('разные порты'));
      expect(cubit.state.saved.socks, 1080);
      await expectLater(cubit.forConnection(), throwsFormatException);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ProxyPortsCubit.preferenceKey), isNull);
    },
  );

  test('Повреждённые настройки заменяются безопасными значениями', () async {
    SharedPreferences.setMockInitialValues({
      ProxyPortsCubit.preferenceKey: '{"socks":0,"http":8080}',
    });
    final cubit = ProxyPortsCubit();
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.saved.socks, 1080);
    expect(cubit.state.saved.http, 8080);
    expect(cubit.state.error, isNotNull);
  });

  testWidgets('Поля сохраняют ввод, во время подключения заблокированы', (
    tester,
  ) async {
    final cubit = ProxyPortsCubit();
    addTearDown(cubit.close);
    await cubit.load();
    Widget view(bool locked) => MaterialApp(
      home: Scaffold(
        body: ProxyPortsView(cubit: cubit, locked: locked),
      ),
    );
    await tester.pumpWidget(view(false));
    await tester.enterText(find.byType(TextFormField).first, '19080');
    await tester.pump();
    await tester.tap(find.byTooltip('Сохранить порты'));
    await tester.pumpAndSettle();
    expect(cubit.state.saved.socks, 19080);
    await tester.pumpWidget(view(true));
    await tester.pumpAndSettle();
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.enabled, false);
    }
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
