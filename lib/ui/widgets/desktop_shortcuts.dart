/// 桌面快捷键包装：Ctrl+F 搜索、Ctrl+K 快速切换会话、Esc 返回。
///
/// 抽成独立 widget 是为了单独测试按键绑定（MainShell 需要整棵 provider 树）。
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

/// 桌面快捷键包装层。
class DesktopShortcuts extends StatelessWidget {
  const DesktopShortcuts({
    super.key,
    required this.onSearch,
    required this.onQuickSwitch,
    required this.onEscape,
    required this.child,
  });

  final VoidCallback onSearch;
  final VoidCallback onQuickSwitch;
  final VoidCallback onEscape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): onSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            onQuickSwitch,
        const SingleActivator(LogicalKeyboardKey.escape): onEscape,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
