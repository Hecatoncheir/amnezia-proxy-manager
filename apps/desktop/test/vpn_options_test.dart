import 'package:amnezia_proxy_manager/settings/vpn_options_cubit.dart';
import 'package:amnezia_proxy_manager/settings/vpn_options_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Защита включена по умолчанию, режимы сохраняются независимо', () async {
    final options = VpnOptionsCubit();
    await options.load();
    expect(options.state.allTraffic, false);
    expect(options.state.killSwitch, true);
    await options.setAllTraffic(true);
    await options.setKillSwitch(false);
    await options.close();
    final restored = VpnOptionsCubit();
    await restored.load();
    expect(restored.state.allTraffic, true);
    expect(restored.state.killSwitch, false);
    await restored.setAllTraffic(false);
    expect(restored.state.killSwitch, false);
    await restored.close();
  });

  testWidgets('Переключатели помещаются в узкое окно с крупным текстом', (
    tester,
  ) async {
    final options = VpnOptionsCubit();
    addTearDown(options.close);
    tester.view.physicalSize = const Size(380, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [VpnOptionsView(options: options)],
          ),
        ),
      ),
    );
    expect(find.text('Весь трафик'), findsOneWidget);
    expect(find.text('Защита при обрыве'), findsOneWidget);
    final traffic = find.widgetWithText(SwitchListTile, 'Весь трафик');
    expect(tester.widget<SwitchListTile>(traffic).onChanged, isNotNull);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Защита при обрыве'),
          )
          .value,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Переключатели стоят рядом и меняют независимые настройки', (
    tester,
  ) async {
    final options = VpnOptionsCubit();
    addTearDown(options.close);
    tester.view.physicalSize = const Size(540, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(48),
            child: VpnOptionsView(options: options),
          ),
        ),
      ),
    );
    final switches = find.byType(SwitchListTile);
    expect(
      tester.getTopLeft(switches.first).dy,
      tester.getTopLeft(switches.last).dy,
    );
    expect(
      tester.getRect(switches.first).right + 16,
      tester.getRect(switches.last).left,
    );
    await tester.tap(find.text('Весь трафик'));
    await tester.pumpAndSettle();
    expect(options.state.allTraffic, true);
    expect(options.state.killSwitch, true);
    await tester.tap(find.text('Защита при обрыве'));
    await tester.pumpAndSettle();
    expect(options.state.allTraffic, true);
    expect(options.state.killSwitch, false);
    expect(tester.takeException(), isNull);
  });
}
