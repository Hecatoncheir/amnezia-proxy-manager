import 'package:amnezia_proxy_manager/settings/window_placement.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Закрытие в трей сохраняет соединение; явный выход завершает его',
    () async {
      SharedPreferences.setMockInitialValues({});
      var stopped = 0, hidden = 0, destroyed = 0;
      const channel = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isVisible') return false;
            if (call.method == 'destroy') destroyed++;
            return null;
          });
      WindowPlacement.beforeClose = () async {
        stopped++;
      };
      WindowPlacement.tryHideToTray = () async {
        hidden++;
        return true;
      };
      addTearDown(() {
        WindowPlacement.beforeClose = null;
        WindowPlacement.tryHideToTray = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final placement = WindowPlacement(
        await SharedPreferences.getInstance(),
        const Rect.fromLTWH(0, 0, 540, 540),
        'test-window',
      );
      await placement.requestClose();
      expect(hidden, 1);
      expect(stopped, 0);
      expect(destroyed, 0);
      placement.onWindowMinimize();
      await Future<void>.delayed(Duration.zero);
      expect(hidden, 2);
      await placement.close();
      expect(stopped, 1);
      expect(destroyed, 1);
    },
  );
}
