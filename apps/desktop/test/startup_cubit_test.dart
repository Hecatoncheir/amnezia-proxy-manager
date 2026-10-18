import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amnezia_proxy_manager/settings/startup_cubit.dart';

void main() {
  test(
    'Оба переключателя выключены по умолчанию; чтение не включает автозапуск',
    () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      final settings = StartupCubit(
        autostartCommand: (action) async {
          calls.add(action);
          return false;
        },
      );
      await settings.load();
      expect(settings.state.autostart, false);
      expect(settings.state.autoconnect, false);
      expect(calls, ['status']);
      await settings.close();
    },
  );
  test(
    'Автоподключение сохраняется между запусками отдельно от автозапуска',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = StartupCubit(autostartCommand: (_) async => false);
      await first.load();
      await first.setAutoconnect(true);
      await first.close();
      final second = StartupCubit(autostartCommand: (_) async => false);
      await second.load();
      expect(second.state.autoconnect, true);
      expect(second.state.autostart, false);
      await second.setAutoconnect(false);
      await second.close();
    },
  );
  test(
    'Переключатель подтверждает состояние ОС и откатывается при ошибке',
    () async {
      SharedPreferences.setMockInitialValues({});
      var enabled = false;
      var failed = false;
      final settings = StartupCubit(
        autostartCommand: (action) async {
          if (failed) throw StateError('fixture');
          if (action == 'enable') enabled = true;
          if (action == 'disable') enabled = false;
          return enabled;
        },
      );
      await settings.load();
      await settings.setAutostart(true);
      expect(settings.state.autostart, true);
      failed = true;
      await settings.setAutostart(false);
      expect(settings.state.autostart, true);
      expect(settings.state.message, isNotNull);
      failed = false;
      await settings.setAutostart(false);
      expect(settings.state.autostart, false);
      await settings.close();
    },
  );
}
