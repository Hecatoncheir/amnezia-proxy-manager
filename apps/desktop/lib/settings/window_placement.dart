import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'window_geometry.dart';

class WindowPlacement with WindowListener {
  WindowPlacement(
    this.preferences,
    this.normalBounds,
    this.preferenceKey, [
    this._maximized = false,
  ]);
  static Future<void> Function()? beforeClose;
  static Future<void> Function()? afterClose;
  static Future<void> quit() async => _active?.close();
  static Future<void> show() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    if (_active?._maximized == true) await windowManager.maximize();
    await windowManager.focus();
  }

  static Future<void> hide() async {
    await flush();
    await windowManager.hide();
  }

  static const storageKey = 'window-placement-v1';
  static WindowPlacement? _active;
  static Future<void> flush() => _active?.save() ?? Future.value();
  final SharedPreferences preferences;
  final String preferenceKey;
  Rect normalBounds;
  bool _maximized;
  Timer? _timer;
  bool _closing = false;
  Future<void> _writes = Future.value();

  static Future<void> initialize({
    String preferenceKey = storageKey,
    bool showWindow = true,
  }) async {
    await windowManager.ensureInitialized();
    final preferences = await SharedPreferences.getInstance();
    final saved = WindowGeometry.decode(preferences.getString(preferenceKey));
    final displays = await screenRetriever.getAllDisplays();
    final areas = displays
        .map(
          (display) =>
              (display.visiblePosition ?? Offset.zero) &
              (display.visibleSize ?? display.size),
        )
        .toList();
    final bounds = fitWindowToDisplays(saved?.bounds, areas);
    final placement = WindowPlacement(
      preferences,
      bounds,
      preferenceKey,
      saved?.maximized ?? false,
    );
    _active = placement;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: bounds.size,
        minimumSize: Size(
          math.min(minimumWindowSize.width, bounds.width),
          math.min(minimumWindowSize.height, bounds.height),
        ),
        title: 'Amnezia Proxy',
      ),
    );
    await windowManager.setBounds(bounds);
    await windowManager.setPreventClose(true);
    windowManager.addListener(placement);
    if (showWindow) await show();
  }

  void scheduleSave() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () => unawaited(save()));
  }

  Future<void> save() {
    _writes = _writes
        .then((_) async {
          final minimized = await windowManager.isMinimized();
          final maximized = minimized
              ? _maximized
              : await windowManager.isMaximized();
          _maximized = maximized;
          if (!maximized && !minimized && !await windowManager.isFullScreen()) {
            normalBounds = await windowManager.getBounds();
          }
          await preferences.setString(
            preferenceKey,
            WindowGeometry(normalBounds, maximized: maximized).encode(),
          );
        })
        .catchError((Object error) {
          debugPrint('Не удалось сохранить положение окна: $error');
        });
    return _writes;
  }

  @override
  void onWindowMove() => scheduleSave();
  @override
  void onWindowResize() => scheduleSave();
  @override
  void onWindowMaximize() => scheduleSave();
  @override
  void onWindowUnmaximize() => scheduleSave();
  @override
  void onWindowClose() => unawaited(close());

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (beforeClose != null) await beforeClose!();
    await save();
    if (afterClose != null) await afterClose!();
    await windowManager.destroy();
  }
}
