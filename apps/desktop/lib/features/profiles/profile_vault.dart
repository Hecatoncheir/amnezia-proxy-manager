import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract interface class ProfileVault {
  Future<String?> read();
  Future<void> write(String? value, {required String? expected});
}

class SystemProfileVault implements ProfileVault {
  SystemProfileVault({this.key = 'amnezia_profiles_v1'});
  final String key;
  // Отдельный Keychain без sharing/provisioning для распространяемого macOS .app.
  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String? value, {required String? expected}) async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final lock = await File('${directory.path}/profiles.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      if (await read() != expected) {
        throw StateError('Хранилище изменено другим экземпляром приложения');
      }
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
      if (await read() != value) {
        throw StateError('Хранилище не подтвердило запись');
      }
    } finally {
      await lock.close();
    }
  }
}
