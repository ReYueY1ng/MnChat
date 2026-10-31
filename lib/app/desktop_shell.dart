/// 桌面壳层：系统托盘、关闭到托盘、窗口尺寸记忆。
///
/// 从 `main.dart` 拆出，让入口只负责装配。所有失败都降级为日志，
/// 不影响已经渲染出来的界面。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart' show Size;
import 'package:window_manager/window_manager.dart';

import '../core/services/tray_service.dart';
import '../core/storage/app_database.dart';
import '../core/storage/settings_store.dart';
import '../core/utils/log.dart';

const String _logTag = 'DesktopShell';

/// 初始化桌面壳层（仅桌面端生效）。
Future<void> initDesktopShell(AppDatabase db) async {
  try {
    final store = SettingsStore(db);
    final closeToTray = await store.getBool(
      SettingsKeys.closeToTray,
      fallback: true,
    );
    final trayReady = await TrayService.init(closeToTray: closeToTray);
    if (TrayService.isDesktop && !trayReady && closeToTray) {
      await TrayService.setCloseToTray(false);
      await store.setBool(SettingsKeys.closeToTray, false);
      log.warn(
        '系统托盘不可用，已自动关闭「关闭到托盘」（关窗现在会直接退出）',
        tag: _logTag,
      );
    }
    await _restoreWindowSize(store);
  } catch (e) {
    log.warn('桌面壳层初始化失败（已忽略）: $e', tag: _logTag);
  }
}

Future<void> _restoreWindowSize(SettingsStore store) async {
  if (!TrayService.isDesktop) return;
  try {
    final w = await store.getInt(SettingsKeys.windowWidth);
    final h = await store.getInt(SettingsKeys.windowHeight);
    if (w != null && h != null && w >= 480 && h >= 360) {
      await windowManager.setSize(Size(w.toDouble(), h.toDouble()));
    }
    _windowKeeper = WindowSizeKeeper(store);
    windowManager.addListener(_windowKeeper!);
  } catch (e) {
    log.warn('窗口尺寸恢复失败（已忽略）: $e', tag: _logTag);
  }
}

WindowSizeKeeper? _windowKeeper;

/// 记住窗口尺寸：拖动过程中会连续触发事件，停手 1.5s 才落盘。
class WindowSizeKeeper with WindowListener {
  WindowSizeKeeper(this._store);

  final SettingsStore _store;
  Timer? _debounce;

  @override
  void onWindowResize() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), _save);
  }

  @override
  void onWindowClose() => _save();

  Future<void> _save() async {
    _debounce?.cancel();
    try {
      final size = await windowManager.getSize();
      await _store.setInt(SettingsKeys.windowWidth, size.width.round());
      await _store.setInt(SettingsKeys.windowHeight, size.height.round());
    } catch (e) {
      log.warn('窗口尺寸保存失败（已忽略）: $e', tag: _logTag);
    }
  }
}
