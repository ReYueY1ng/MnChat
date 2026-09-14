import 'dart:math';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import 'sni_menu_item.dart';

/// 纯 Dart 实现的 Linux 系统托盘（StatusNotifierItem over D-Bus）。
///
/// 为什么自研而不是用现成插件：
/// - `tray_manager` / `nativeapi`（后者是前者的新家）的 Linux 后端收到
///   `Activate` / `SecondaryActivate` 后**只返回成功、不转发给 Dart**，
///   因此无法实现"点击托盘开窗口"；
/// - `dart_libayatana_appindicator` 能收到事件，但许可证是 **GPL-3.0**，
///   不能用于本项目。
///
/// 实现上直接按 SNI 规范注册，两个关键点（都是踩过的坑）：
/// 1. 对象**必须**挂在 `/StatusNotifierItem`：向 watcher 注册时只传服务名，
///    宿主会据此推断路径，路径不符会被判定为 "Failed to load tray item"；
/// 2. **必须实现 `Properties.GetAll`**：部分宿主（Quickshell 等）只用 GetAll
///    拉属性，缺失会导致托盘整个不显示（单个 `Get` 却是通的，极易误判）。
///
/// 依赖 `dbus` 包（MPL-2.0，弱 copyleft，可作依赖使用）。
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

  /// 图标像素：**ARGB32、非预乘**（SNI `IconPixmap` 约定）。
  final Uint8List iconArgb;
  final int iconWidth;
  final int iconHeight;

  final List<SniMenuItem> menuItems;

  /// 左键双击（GNOME/Hyprland 的宿主在双击时发 `Activate`）。
  final void Function(int x, int y) onActivate;

  /// 中键单击。
  final void Function(int x, int y) onSecondaryActivate;

  /// 菜单项点击。
  final void Function(int menuId) onMenuActivated;

  final void Function(String message)? onError;

  static const DBusObjectPath itemPath = DBusObjectPath.unchecked(
    '/StatusNotifierItem',
  );
  static const DBusObjectPath menuPath = DBusObjectPath.unchecked(
    '/StatusNotifierItem/Menu',
  );

  DBusClient? _client;

  Future<void> start() async {
    final client = DBusClient.session();
    _client = client;
    final name = 'org.kde.StatusNotifierItem-${_randomSuffix()}';
    await client.requestName(name);
    final item = _SniItemObject(this);
    await client.registerObject(item);
    await client.registerObject(_DbusMenuObject(this));
    await item.emitSignal('org.kde.StatusNotifierItem', 'NewIcon');
    await _registerWithWatcher(client, name);
  }

  Future<void> stop() async {
    final client = _client;
    _client = null;
    if (client == null) return;
    try {
      await client.close();
    } catch (e) {
      onError?.call('关闭 D-Bus 连接失败: $e');
    }
  }

  Future<void> _registerWithWatcher(DBusClient client, String name) async {
    Object? lastError;
    for (final entry in const [
      ('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher'),
      ('org.freedesktop.StatusNotifierWatcher', '/StatusNotifierWatcher'),
    ]) {
      try {
        await DBusRemoteObject(
          client,
          name: entry.$1,
          path: DBusObjectPath.unchecked(entry.$2),
        ).callMethod('org.kde.StatusNotifierWatcher',
            'RegisterStatusNotifierItem', [DBusString(name)]);
        return;
      } catch (e) {
        lastError = e;
      }
    }
    onError?.call('注册到 StatusNotifierWatcher 失败: $lastError');
  }

  static String _randomSuffix() {
    final r = Random.secure();
    return '${r.nextInt(0xFFFFFF)}-${r.nextInt(0xFFFFFF)}';
  }
}

/// `org.kde.StatusNotifierItem` 对象。
class _SniItemObject extends DBusObject {
  _SniItemObject(this.tray) : super(SniTray.itemPath);

  final SniTray tray;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'org.kde.StatusNotifierItem') {
      return super.handleMethodCall(call);
    }
    switch (call.name) {
      case 'Activate':
        tray.onActivate(
          call.values[0].asInt32(),
          call.values[1].asInt32(),
        );
        break;
      case 'SecondaryActivate':
        tray.onSecondaryActivate(
          call.values[0].asInt32(),
          call.values[1].asInt32(),
        );
        break;
      case 'ContextMenu':
      case 'Scroll':
      case 'ProvideXdgActivationToken':
        break;
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  Map<String, DBusValue> _properties() => {
    'Id': DBusString('mnchat'),
    'Category': DBusString('ApplicationStatus'),
    'Status': DBusString('Active'),
    'Title': DBusString(tray.title),
    'IconName': DBusString(''),
    'IconPixmap': DBusArray(DBusSignature('(iiay)'), [
      DBusStruct([
        DBusInt32(tray.iconWidth),
        DBusInt32(tray.iconHeight),
        DBusArray.byte(tray.iconArgb),
      ]),
    ]),
    'AttentionIconName': DBusString(''),
    'AttentionIconPixmap': DBusArray(DBusSignature('(iiay)'), []),
    'IconThemePath': DBusString(''),
    'Menu': SniTray.menuPath,
    'ItemIsMenu': DBusBoolean(false),
    'WindowId': DBusUint32(0),
    'ToolTip': DBusStruct([
      DBusString(''),
      DBusArray(DBusSignature('(iiay)'), []),
      DBusString(''),
      DBusString(''),
    ]),
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != 'org.kde.StatusNotifierItem') {
      return DBusMethodErrorResponse.unknownProperty();
    }
    final value = _properties()[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusMethodSuccessResponse([value]);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(
      interface == 'org.kde.StatusNotifierItem' ? _properties() : const {},
    );
  }
}

/// `com.canonical.dbusmenu` 对象（宿主据此渲染右键菜单）。
class _DbusMenuObject extends DBusObject {
  _DbusMenuObject(this.tray) : super(SniTray.menuPath);

  final SniTray tray;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'com.canonical.dbusmenu') {
      return super.handleMethodCall(call);
    }
    switch (call.name) {
      case 'GetLayout':
        // 规范：GetLayout(out u revision, out (ia{sv}av) layout) —— 两个 out 参数，
        // 不是一个包住两者的 struct（否则宿主报 InvalidSignature）。
        return DBusMethodSuccessResponse([DBusUint32(1), _layout()]);
      case 'GetGroupProperties':
        final ids = call.values[0]
            .asArray()
            .map((v) => v.asInt32())
            .toSet();
        return DBusMethodSuccessResponse([_groupProperties(ids)]);
      case 'GetProperty':
        final id = call.values[0].asInt32();
        final prop = call.values[1].asString();
        final value = _itemProperties(id)[prop];
        return value == null
            ? DBusMethodErrorResponse.unknownProperty()
            : DBusMethodSuccessResponse([DBusVariant(value)]);
      case 'Event':
        final id = call.values[0].asInt32();
        final eventId = call.values[1].asString();
        if (eventId == 'clicked') tray.onMenuActivated(id);
        return DBusMethodSuccessResponse();
      case 'AboutToShow':
        return DBusMethodSuccessResponse([DBusBoolean(false)]);
      case 'AboutToShowGroup':
        return DBusMethodSuccessResponse([
          DBusStruct([
            DBusArray(DBusSignature('i'), const []),
            DBusArray(DBusSignature('i'), const []),
          ]),
        ]);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  DBusValue _layout() {
    final children = <DBusValue>[
      for (final item in tray.menuItems)
        DBusVariant(
          DBusStruct([
            DBusInt32(item.id),
            DBusDict.stringVariant(_itemProperties(item.id)),
            DBusArray(DBusSignature('v'), const []),
          ]),
        ),
    ];
    return DBusStruct([
      DBusInt32(0),
      DBusDict.stringVariant(const {
        'children-display': DBusString('submenu'),
      }),
      DBusArray(DBusSignature('v'), children),
    ]);
  }

  DBusValue _groupProperties(Set<int> ids) {
    return DBusArray(DBusSignature('(ia{sv})'), [
      for (final id in ids)
        DBusStruct([DBusInt32(id), DBusDict.stringVariant(_itemProperties(id))]),
    ]);
  }

  Map<String, DBusValue> _itemProperties(int id) {
    if (id == 0) return const {'children-display': DBusString('submenu')};
    final item = tray.menuItems.where((i) => i.id == id).firstOrNull;
    if (item == null) return const {};
    if (item.separator) return const {'type': DBusString('separator')};
    return {
      'label': DBusString(item.label),
      'enabled': DBusBoolean(true),
      'visible': DBusBoolean(true),
    };
  }

  Map<String, DBusValue> _properties() => {
    'Version': DBusUint32(3),
    'Status': DBusString('normal'),
    'TextDirection': DBusString('ltr'),
    'IconThemePath': DBusArray(DBusSignature('s'), const []),
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != 'com.canonical.dbusmenu') {
      return DBusMethodErrorResponse.unknownProperty();
    }
    final value = _properties()[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusMethodSuccessResponse([value]);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(
      interface == 'com.canonical.dbusmenu' ? _properties() : const {},
    );
  }
}
