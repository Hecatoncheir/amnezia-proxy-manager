import 'dart:convert';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StartupOptions {
  const StartupOptions({
    this.autostart = false,
    this.autoconnect = false,
    this.startInTray = false,
    this.minimizeToTray = false,
    this.closeToTray = false,
    this.busy = false,
    this.message,
  });
  final bool autostart,
      autoconnect,
      startInTray,
      minimizeToTray,
      closeToTray,
      busy;
  final String? message;
}

class StartupCubit extends Cubit<StartupOptions> {
  StartupCubit({this.autostartCommand, this.preferences})
    : super(const StartupOptions());
  final Future<bool> Function(String)? autostartCommand;
  SharedPreferences? preferences;
  static const autoConnectKey = 'auto-connect-v1';
  static const startInTrayKey = 'start-in-tray-v1';
  static const closeToTrayKey = 'close-to-tray-v1';
  static bool shouldCloseToTray(SharedPreferences preferences) =>
      preferences.getBool(closeToTrayKey) ??
      preferences.getBool(minimizeToTrayKey) ??
      false;
  static const minimizeToTrayKey = 'minimize-to-tray-v1';
  static bool shouldStartInTray(
    List<String> arguments,
    SharedPreferences preferences,
  ) =>
      arguments.contains('--autostart') &&
      (preferences.getBool(startInTrayKey) ?? false);
  bool _busy = false;
  Future<bool> _command(String action) async {
    if (autostartCommand != null) return autostartCommand!(action);
    final helper =
        '${File(Platform.resolvedExecutable).parent.path}/${Platform.isWindows ? 'proxy-engine.exe' : 'proxy-engine'}';
    final result = await Process.run(helper, [
      '--autostart',
      action,
      Platform.resolvedExecutable,
    ], runInShell: false).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) throw const FormatException();
    return (jsonDecode(result.stdout as String) as Map)['enabled'] == true;
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    _publish(busy: true);
    try {
      preferences ??= await SharedPreferences.getInstance();
      if (!preferences!.containsKey(closeToTrayKey)) {
        await preferences!.setBool(
          closeToTrayKey,
          shouldCloseToTray(preferences!),
        );
      }
      final autoconnect = preferences!.getBool(autoConnectKey) ?? false;
      final startInTray = preferences!.getBool(startInTrayKey) ?? false;
      final minimizeToTray = preferences!.getBool(minimizeToTrayKey) ?? false;
      _publish(
        autoconnect: autoconnect,
        startInTray: startInTray,
        minimizeToTray: minimizeToTray,
        closeToTray: shouldCloseToTray(preferences!),
        busy: true,
      );
      final enabled = await _command('status');
      _publish(autostart: enabled, autoconnect: autoconnect);
    } catch (_) {
      _publish(message: 'Не удалось проверить автозапуск.');
    } finally {
      _busy = false;
    }
  }

  Future<void> setMinimizeToTray(bool enabled) async {
    if (_busy) return;
    _busy = true;
    _publish(busy: true);
    try {
      preferences ??= await SharedPreferences.getInstance();
      if (!await preferences!.setBool(minimizeToTrayKey, enabled)) {
        throw const FormatException();
      }
      _publish(minimizeToTray: enabled);
    } catch (_) {
      _publish(message: 'Не удалось сохранить настройку сворачивания в трей.');
    } finally {
      _busy = false;
    }
  }

  Future<void> setCloseToTray(bool enabled) async {
    if (_busy) return;
    _busy = true;
    _publish(busy: true);
    try {
      preferences ??= await SharedPreferences.getInstance();
      if (!await preferences!.setBool(closeToTrayKey, enabled)) {
        throw const FormatException();
      }
      _publish(closeToTray: enabled);
    } catch (_) {
      _publish(message: 'Не удалось сохранить настройку сворачивания в трей.');
    } finally {
      _busy = false;
    }
  }

  Future<void> setStartInTray(bool enabled) async {
    if (_busy) return;
    _busy = true;
    _publish(busy: true);
    try {
      await _writeStartInTray(enabled);
      _publish(startInTray: enabled);
    } catch (_) {
      _publish(
        message: 'Не удалось настроить автозапуск в трей. Повторите попытку.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _writeStartInTray(bool enabled) async {
    // Перерегистрируем старые записи без признака автозапуска.
    if (enabled) await _enableAutostart();
    preferences ??= await SharedPreferences.getInstance();
    if (!await preferences!.setBool(startInTrayKey, enabled)) {
      throw const FormatException();
    }
  }

  Future<void> _enableAutostart() async {
    if (!await _command('enable')) throw const FormatException();
    _publish(autostart: true, busy: true);
  }

  Future<void> setAutostart(bool enabled) async {
    if (_busy) return;
    _busy = true;
    _publish(busy: true);
    try {
      final actual = await _command(enabled ? 'enable' : 'disable');
      if (actual != enabled) throw const FormatException();
      _publish(autostart: actual);
    } catch (_) {
      _publish(
        message: 'Не удалось изменить автозапуск. Проверьте разрешения и настройки автозагрузки системы.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> setAutoconnect(bool enabled) async {
    if (_busy) return;
    _busy = true;
    _publish(busy: true);
    try {
      preferences ??= await SharedPreferences.getInstance();
      if (!await preferences!.setBool(autoConnectKey, enabled)) {
        throw const FormatException();
      }
      _publish(autoconnect: enabled);
    } catch (_) {
      _publish(message: 'Не удалось сохранить автоподключение.');
    } finally {
      _busy = false;
    }
  }

  void _publish({
    bool? autostart,
    bool? autoconnect,
    bool? startInTray,
    bool? minimizeToTray,
    bool? closeToTray,
    bool busy = false,
    String? message,
  }) {
    if (!isClosed) {
      emit(
        StartupOptions(
          autostart: autostart ?? state.autostart,
          autoconnect: autoconnect ?? state.autoconnect,
          startInTray: startInTray ?? state.startInTray,
          minimizeToTray: minimizeToTray ?? state.minimizeToTray,
          closeToTray: closeToTray ?? state.closeToTray,
          busy: busy,
          message: message,
        ),
      );
    }
  }
}
