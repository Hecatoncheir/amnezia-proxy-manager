import 'package:tray_manager/tray_manager.dart';

import 'tray_host.dart';

abstract class AppTray {
  Future<bool> create({
    required Future<void> Function() open,
    required Future<void> Function() hide,
    required Future<void> Function() exit,
  });
  void dispose();
}

class NativeAppTray implements AppTray {
  TrayIcon? _icon;
  Menu? _menu;
  Image? _image;
  ListenerId? _clickListener;
  final _items = <MenuItem, ListenerId>{};

  @override
  Future<bool> create({
    required Future<void> Function() open,
    required Future<void> Function() hide,
    required Future<void> Function() exit,
  }) async {
    if (!await trayHostAvailable()) return false;
    if (!TrayManager.instance.isSupported()) return false;
    if (!_createResources()) return false;
    _icon!.icon = _image;
    _icon!.setTooltip('Amnezia Proxy');
    _addItem('Открыть', open);
    _addItem('Свернуть в трей', hide);
    _menu!.addSeparator();
    _addItem('Выйти', exit);
    _icon!.setContextMenu(_menu);
    _icon!.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    _clickListener = _icon!.addListener((event) async {
      await _openOnClick(event, open);
    });
    return _icon!.setVisible(true);
  }

  bool _createResources() {
    _icon = TrayIcon.create();
    _menu = Menu.create();
    _image = ImageAsset.fromAsset('assets/branding/app_icon_256.png');
    return _icon != null && _menu != null && _image != null;
  }

  Future<void> _openOnClick(
    TrayIconEvent event,
    Future<void> Function() open,
  ) async {
    if (event is TrayIconClickedEvent) await open();
  }

  void _addItem(String title, Future<void> Function() action) {
    final item = MenuItem.createWithLabelAndType(title, MenuItemType.normal);
    if (item == null) throw StateError('Не удалось создать меню трея');
    _items[item] = item.addListener((event) async {
      if (event is MenuItemClickedEvent) await action();
    });
    _menu!.addItem(item);
  }

  @override
  void dispose() {
    for (final entry in _items.entries) {
      entry.key.removeListener(entry.value);
      entry.key.dispose();
    }
    _items.clear();
    final listener = _clickListener;
    if (listener != null) _icon?.removeListener(listener);
    _icon?.dispose();
    _menu?.dispose();
    _image?.dispose();
    _icon = null;
    _menu = null;
    _image = null;
    _clickListener = null;
  }
}
