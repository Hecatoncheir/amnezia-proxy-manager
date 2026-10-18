// Отдельная точка входа для проверки интерфейса средствами Flutter Driver.
import 'package:amnezia_proxy_manager/main.dart' as app;
import 'package:flutter_driver/driver_extension.dart';

Future<void> main() async {
  enableFlutterDriverExtension();
  await app.main(const []);
}
