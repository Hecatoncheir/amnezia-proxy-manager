import 'package:amnezia_proxy_manager/settings/app_tray.dart';
import 'package:amnezia_proxy_manager/settings/tray_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class TestTray implements AppTray {
  bool available = true, disposed = false;
  late Future<void> Function() openWindow, hideWindow, exitApp;
  @override
  Future<bool> create({
    required Future<void> Function() open,
    required Future<void> Function() hide,
    required Future<void> Function() exit,
  }) async {
    openWindow = open;
    hideWindow = hide;
    exitApp = exit;
    return available;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test('Скрытый запуск, открытие и выход через трей', () async {
    final tray = TestTray();
    var shown = 0, hidden = 0, exited = 0;
    final cubit = TrayCubit(
      tray: tray,
      showWindow: () async {
        shown++;
      },
      hideWindow: () async {
        hidden++;
      },
      exitApplication: () async {
        exited++;
      },
    );
    await cubit.start(hidden: true);
    expect(shown, 0);
    expect(hidden, 1);
    expect(cubit.state.hidden, true);
    await tray.openWindow();
    expect(shown, 1);
    expect(cubit.state.hidden, false);
    await tray.exitApp();
    expect(exited, 1);
    await cubit.close();
    expect(tray.disposed, true);
  });

  test('Без доступного трея приложение остаётся видимым', () async {
    final tray = TestTray()..available = false;
    var shown = 0, hidden = 0;
    final cubit = TrayCubit(
      tray: tray,
      showWindow: () async {
        shown++;
      },
      hideWindow: () async {
        hidden++;
      },
      exitApplication: () async {},
    );
    await cubit.start(hidden: true);
    expect(shown, 1);
    expect(hidden, 0);
    expect(cubit.state.ready, false);
    await cubit.close();
  });
}
