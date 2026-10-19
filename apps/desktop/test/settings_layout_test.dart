import 'package:amnezia_proxy_manager/settings/general_settings_view.dart';
import 'package:amnezia_proxy_manager/settings/settings_cubit.dart';
import 'package:amnezia_proxy_manager/settings/startup_cubit.dart';
import 'package:amnezia_proxy_manager/features/updates/app_updates.dart';
import 'package:amnezia_proxy_manager/features/updates/updates_view.dart';
import 'package:amnezia_proxy_manager/features/engine/download_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Автозапуск в трей находится сразу под автозапуском; настройка сворачивания работает',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final startup = StartupCubit(autostartCommand: (_) async => false);
      final theme = SettingsCubit();
      await startup.load();
      await tester.pumpWidget(
        BlocProvider.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GeneralSettingsView(startup: startup),
              ),
            ),
          ),
        ),
      );
      final autorun = tester.getTopLeft(find.text('Автозапуск')).dy;
      final tray = tester
          .getTopLeft(find.text('Автозапуск свёрнутым в трей'))
          .dy;
      final connect = tester.getTopLeft(find.text('Автоподключение')).dy;
      expect(autorun, lessThan(tray));
      expect(tray, lessThan(connect));
      await tester.ensureVisible(find.text('Сворачивать в трей'));
      await tester.tap(find.text('Сворачивать в трей'));
      await tester.pumpAndSettle();
      expect(startup.state.minimizeToTray, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await startup.close();
      await theme.close();
    },
  );

  testWidgets('Обновление показывает кольцо с процентами вместо полосы', (
    tester,
  ) async {
    final uri = Uri.parse(
      'https://github.com/Hecatoncheir/amnezia-proxy-manager/releases/tag/v0.2.0',
    );
    final package = AppPackage(
      'AmneziaProxyManager-Setup-windows-x64.exe',
      uri,
      100,
      'sha256:${'a' * 64}',
    );
    final updates =
        AppUpdates(
            readVersion: () async => '0.1.0',
            installationDirectory: () async => null,
            platform: 'windows-x64',
          )
          ..status = AppUpdateStatus.available
          ..downloading = true
          ..downloadedBytes = 50
          ..release = AppRelease(
            'v0.2.0',
            uri,
            '',
            AppVersion.parse('0.2.0')!,
            {package.name: package},
          );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: UpdatesView(controller: updates)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DownloadRing), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await updates.close();
  });
}
