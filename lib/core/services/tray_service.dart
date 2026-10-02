import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tray_manager/tray_manager.dart' as tm;
import 'package:window_manager/window_manager.dart';

import '../utils/log.dart';
import 'sni_menu_item.dart';
import 'sni_tray_stub.dart' if (dart.library.io) 'sni_tray.dart' as sni;

/// 本模块日志标签。
const String _logTag = 'TrayService';

/// 桌面端（linux / windows）系统托盘 + 「关闭到托盘」。
///
/// 两个平台走**不同后端**：
/// - **Windows**：`tray_manager`（MIT）。左键单击显示窗口、右键弹菜单。
/// - **Linux**：自研 SNI（见 `sni_tray.dart`，仅依赖 MPL-2.0 的 `dbus` 包）。
///   现有插件在 Linux 上都不转发点击：`tray_manager` 与它的后继 `nativeapi`
///   收到 `Activate` 后直接返回成功、丢弃事件；唯一能收到事件的
///   `dart_libayatana_appindicator` 又是 GPL-3.0，不能用于本项目，故自研。
///   自研实现支持**左键双击 / 中键开窗口**，以及菜单项。
///
/// 非桌面平台（android）全部为空操作，避免调用未注册的平台通道。
class TrayService {
  TrayService._();

  static const int _menuShow = 1;
  static const int _menuSeparator = 99;
  static const int _menuExit = 2;

  static bool _initialized = false;
  static bool _closeToTray = true;

  /// 托盘是否真的注册成功（[init] 的返回值）。
  ///
  /// Linux 上没有 StatusNotifierWatcher（等于没跑有托盘区的状态栏/waybar）时注册
  /// 会失败，此时必须把「关闭到托盘」关掉 —— 否则关窗后应用既不可见也没法召回。
  /// 设置页用 [trayAvailable] 把这条降级告诉用户。
  static bool _trayReady = false;
  static bool get trayAvailable => _trayReady;

  static _WindowCloseListener? _windowListener;
  static _TrayClickListener? _trayListener;
  static sni.SniTray? _sni;

  static bool get _isLinux => defaultTargetPlatform == TargetPlatform.linux;

  static bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  static bool get _isDesktop => _isLinux || _isWindows;

  /// 当前平台是否有系统托盘这一套（linux / windows）。
  ///
  /// 非桌面端 [init] 直接返回 false，调用方不要把它当成「注册失败」去降级。
  static bool get isDesktop => _isDesktop;

  /// 初始化托盘与窗口关闭拦截；仅在桌面端生效。
  ///
  /// [closeToTray] 为 true 时，关闭窗口仅隐藏到托盘；否则直接退出。
  ///
  /// 返回**托盘是否真的注册成功**。调用方在 false 且用户本意是「关闭到托盘」时
  /// 必须降级：没有可点的托盘图标还拦截关窗，应用会变成关不掉又找不回来的幽灵。
  static Future<bool> init({bool closeToTray = true}) async {
    if (!_isDesktop) return false;
    if (_initialized) return _trayReady;
    _closeToTray = closeToTray;

    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      _windowListener = _WindowCloseListener();
      windowManager.addListener(_windowListener!);
    } catch (e) {
      log.warn('window_manager 初始化失败: $e', tag: _logTag);
    }

    _trayReady = _isLinux ? await _initLinux() : await _initWindows();
    _initialized = true;
    return _trayReady;
  }

  // ── Linux：自研 SNI ────────────────────────────────────────────────────

  static Future<bool> _initLinux() async {
    try {
      final icon = await loadIconArgb();
      if (icon == null) {
        log.warn('托盘图标解码失败，跳过 Linux 托盘', tag: _logTag);
        return false;
      }
      final tray = sni.SniTray(
        title: 'MnChat',
        iconArgb: icon.$1,
        iconWidth: icon.$2,
        iconHeight: icon.$3,
        menuItems: const [
          SniMenuItem.label(_menuShow, '显示主窗口'),
          SniMenuItem.separator(_menuSeparator),
          SniMenuItem.label(_menuExit, '退出 MnChat'),
        ],
        onActivate: (_, _) {
          log.debug('双击托盘 → 显示主窗口', tag: _logTag);
          _showWindow();
        },
        onSecondaryActivate: (_, _) {
          log.debug('中键托盘 → 显示主窗口', tag: _logTag);
          _showWindow();
        },
        onMenuActivated: _onMenuActivated,
        onError: (message) => log.warn(message, tag: _logTag),
      );
      await tray.start();
      _sni = tray;
      if (!tray.registeredWithWatcher) {
        // start() 不会因此报错（它只在自己那边记一条 onError），但图标永远不出
        // 现 —— 对调用方而言这就是失败。
        log.warn(
          '系统里没有 StatusNotifierWatcher，托盘图标不会显示',
          tag: _logTag,
        );
        return false;
      }
      return true;
    } catch (e) {
      log.warn('Linux 托盘初始化失败: $e', tag: _logTag);
      return false;
    }
  }

  /// 托盘图标边长（逻辑像素）。
  ///
  /// SNI 的 `IconPixmap` 是裸 ARGB 字节、经 D-Bus 传递。实测 512×512（1 MiB）
  /// 会让宿主的 `GetAll` 调用超时（>30s），图标拿不到 → 托盘整个不显示；
  /// 64×64（16 KiB）往返约 20ms。故不论资源文件多大，都按此尺寸解码。
  @visibleForTesting
  static const int trayIconSize = 64;

  /// 把随包 PNG 解码成 SNI `IconPixmap` 需要的 ARGB32（非预乘）字节。
  ///
  /// 公开仅为让回归测试能断言载荷上限，业务上只由 [_initLinux] 调用。
  @visibleForTesting
  static Future<(Uint8List, int, int)?> loadIconArgb() async {
    try {
      final data = await rootBundle.load('assets/tray_icon.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: trayIconSize,
        targetHeight: trayIconSize,
      );
      final image = (await codec.getNextFrame()).image;
      final width = image.width;
      final height = image.height;
      final rgba = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      codec.dispose();
      if (rgba == null) return null;
      final src = rgba.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.lengthInBytes,
      );
      final argb = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        argb[i * 4] = src[i * 4 + 3];
        argb[i * 4 + 1] = src[i * 4];
        argb[i * 4 + 2] = src[i * 4 + 1];
        argb[i * 4 + 3] = src[i * 4 + 2];
      }
      return (argb, width, height);
    } catch (e) {
      log.warn('图标解码失败: $e', tag: _logTag);
      return null;
    }
  }

  static void _onMenuActivated(int id) {
    switch (id) {
      case _menuShow:
        _showWindow();
      case _menuExit:
        _quit();
    }
  }

  // ── Windows：tray_manager ──────────────────────────────────────────────

  static Future<bool> _initWindows() async {
    try {
      // setIcon 会把相对路径解析到 `data/flutter_assets/` 下。
      await tm.trayManager.setIcon('assets/tray_icon.png');
    } catch (e) {
      log.warn('setIcon 失败: $e', tag: _logTag);
      return false; // 连图标都没有，后续无意义
    }

    try {
      await tm.trayManager.setContextMenu(
        tm.Menu(
          items: [
            tm.MenuItem(key: 'show', label: '显示主窗口'),
            tm.MenuItem.separator(),
            tm.MenuItem(key: 'exit', label: '退出 MnChat'),
          ],
        ),
      );
    } catch (e) {
      log.warn('setContextMenu 失败: $e', tag: _logTag);
    }

    _trayListener = _TrayClickListener();
    tm.trayManager.addListener(_trayListener!);

    try {
      await tm.trayManager.setToolTip('MnChat');
    } catch (e) {
      log.warn('setToolTip 失败: $e', tag: _logTag);
    }
    return true;
  }

  /// 运行期切换「关闭到托盘」（设置页调用）。
  static Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
  }

  /// 退出时清理托盘。
  static Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await _sni?.stop();
      _sni = null;
      if (_trayListener != null) {
        tm.trayManager.removeListener(_trayListener!);
        _trayListener = null;
      }
      if (_windowListener != null) {
        windowManager.removeListener(_windowListener!);
        _windowListener = null;
      }
      if (_isWindows) await tm.trayManager.destroy();
    } catch (e) {
      log.warn('dispose 失败: $e', tag: _logTag);
    }
    _initialized = false;
  }

  static Future<void> _showWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      log.warn('_showWindow failed: $e', tag: _logTag);
    }
  }

  static Future<void> _quit() async {
    try {
      await windowManager.destroy();
    } catch (e) {
      log.warn('_quit failed: $e', tag: _logTag);
    }
  }
}

/// 拦截窗口关闭：按设置隐藏到托盘或直接退出。
class _WindowCloseListener with WindowListener {
  @override
  void onWindowClose() async {
    if (TrayService._closeToTray) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }
}

/// Windows（tray_manager）的托盘事件；Linux 走自研 SNI 的回调。
class _TrayClickListener with tm.TrayListener {
  @override
  void onTrayIconMouseDown() {
    TrayService._showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    tm.trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(tm.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        TrayService._showWindow();
        break;
      case 'exit':
        TrayService._quit();
        break;
    }
  }
}
