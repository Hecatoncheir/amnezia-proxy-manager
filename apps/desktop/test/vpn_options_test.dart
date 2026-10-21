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
    expect(find.text('Пропускать весь трафик через VPN'), findsOneWidget);
    expect(find.text('Блокировать интернет при обрыве VPN'), findsOneWidget);
    final traffic = find.widgetWithText(
      SwitchListTile,
      'Пропускать весь трафик через VPN',
    );
    expect(tester.widget<SwitchListTile>(traffic).onChanged, isNotNull);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(
              SwitchListTile,
              'Блокировать интернет при обрыве VPN',
            ),
          )
          .value,
      true,
    );
    expect(tester.takeException(), isNull);
  });
}
