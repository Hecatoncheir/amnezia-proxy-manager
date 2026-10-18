import 'dart:io';

import 'package:dbus/dbus.dart';

/// В Linux нужна не только шина D-Bus, но и панель, отображающая значки.
Future<bool> trayHostAvailable() async {
  if (!Platform.isLinux) return true;
  final client = DBusClient.session();
  try {
    final watcher = DBusRemoteObject(
      client,
      name: 'org.kde.StatusNotifierWatcher',
      path: DBusObjectPath('/StatusNotifierWatcher'),
    );
    final value = await watcher
        .getProperty(
          'org.kde.StatusNotifierWatcher',
          'IsStatusNotifierHostRegistered',
          signature: DBusSignature('b'),
        )
        .timeout(const Duration(seconds: 3));
    return value.asBoolean();
  } catch (_) {
    return false;
  } finally {
    await client.close();
  }
}
