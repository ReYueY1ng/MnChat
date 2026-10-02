import 'dart:typed_data';

import 'sni_menu_item.dart';

/// 无 `dart:io` 平台（非原生宿主）的空实现：Linux 托盘只在桌面端可用。
class SniTray {
  SniTray({
    required this.title,
    required this.iconArgb,
    required this.iconWidth,
    required this.iconHeight,
    required this.menuItems,
    required this.onActivate,
    required this.onSecondaryActivate,
    required this.onMenuActivated,
    this.onError,
  });

  final String title;
  final Uint8List iconArgb;
  final int iconWidth;
  final int iconHeight;
  final List<SniMenuItem> menuItems;
  final void Function(int x, int y) onActivate;
  final void Function(int x, int y) onSecondaryActivate;
  final void Function(int menuId) onMenuActivated;
  final void Function(String message)? onError;

  Future<void> start() async {}
  Future<void> stop() async {}

  /// 与真实实现同名同义；桩环境永远登不上。
  bool get registeredWithWatcher => false;
}
