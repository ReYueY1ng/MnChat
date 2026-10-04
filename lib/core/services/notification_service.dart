/// 通知抽象层：把「按会话弹通知 / 点击跳转 / 前后台切换时启停保活」从 UI 与
/// 业务代码里摘出来，按平台选择实现。
///
/// - **Android**：走 `mnchat/native` MethodChannel（原生 `ChatBackgroundService`）。
///   支持按会话区分（不同会话各自一条、互不覆盖）、点击跳回对应会话、
///   退到后台才启动前台服务（所以启动应用时通知栏是干净的）。
/// - **Linux 桌面**：走系统 `org.freedesktop.Notifications`（复用项目已有的
///   `dbus` 依赖，不新增包）。点击动作（ActionInvoked）会反查 sessionKey 抛到
///   [NotificationService.taps]。
/// - **其他平台**（Windows / macOS / 单元测试）：[NoopNotificationService]，
///   任何调用都不抛异常。
library;

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

import '../utils/log.dart';
import 'native_bridge.dart';

/// 一条会话消息通知。
class MessageNotification {
  /// 会话唯一 key，形如 `friend_123` / `group_456`。
  final String sessionKey;

  /// 标题（会话名）。
  final String title;

  /// 正文摘要。
  final String text;

  /// 该会话最近若干条正文（折叠面板展开显示；≤1 条时不展开）。
  final List<String> lines;

  /// 是否群聊（仅用于通知分组）。
  final bool group;

  /// 通知右侧大图标的网络头像地址（可选）。
  final String? avatarUrl;

  /// 通知右侧大图标的本地头像图标 —— Flutter asset key
  /// （如 `assets/heads/skin_1001.png`），优先于 [avatarUrl]。
  final String? avatarAsset;

  /// 是否带提示音（Android 走渠道、Linux 走 `suppress-sound` hint）。
  final bool sound;

  /// 是否震动（仅 Android 渠道有意义，桌面忽略）。
  final bool vibrate;

  const MessageNotification({
    required this.sessionKey,
    required this.title,
    required this.text,
    this.lines = const [],
    this.group = false,
    this.avatarUrl,
    this.avatarAsset,
    this.sound = true,
    this.vibrate = true,
  });
}

/// 平台无关的通知接口。
abstract class NotificationService {
  /// 初始化（注册原生回调 / 连接 dbus）。失败不得抛异常。
  Future<void> init();

  /// 申请通知权限；返回是否可用。
  Future<bool> requestPermission();

  /// 弹出一条会话消息通知。
  Future<void> showMessage(MessageNotification notification);

  /// 取消某个会话的通知。
  Future<void> cancel(String sessionKey);

  /// 取消全部消息通知（不影响常驻通知）。
  Future<void> cancelAll();

  /// 进入 / 离开后台。
  ///
  /// Android 用它启停前台服务（常驻通知只在后台出现）；桌面无操作。
  Future<void> setBackgroundMode(bool background);

  /// 用户点击通知（载荷为 sessionKey）。
  Stream<String> get taps;

  /// 冷启动：应用被通知拉起时那次通知的 sessionKey（无则 null）。
  Future<String?> initialTapSessionKey();

  /// 释放资源。
  void dispose();
}

/// Android：转发到 `mnchat/native`。
class AndroidNotificationService implements NotificationService {
  final _taps = StreamController<String>.broadcast();
  bool _inited = false;

  @override
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    // 热启动：原生点击通知 → 回调 → 转发到 taps
    NativeBridge.setNotificationTapHandler(_taps.add);
  }

  @override
  Future<bool> requestPermission() => NativeBridge.requestNotificationPermission();

  @override
  Future<void> showMessage(MessageNotification n) => NativeBridge.showMessageNotification(
    sessionKey: n.sessionKey,
    title: n.title,
    text: n.text,
    lines: n.lines,
    group: n.group,
    avatarUrl: n.avatarUrl,
    avatarAsset: n.avatarAsset,
    sound: n.sound,
    vibrate: n.vibrate,
  );

  @override
  Future<void> cancel(String sessionKey) =>
      NativeBridge.cancelMessageNotification(sessionKey);

  @override
  Future<void> cancelAll() => NativeBridge.cancelAllMessageNotifications();

  @override
  Future<void> setBackgroundMode(bool background) async {
    if (background) {
      await NativeBridge.startBackgroundService();
    } else {
      await NativeBridge.stopBackgroundService();
    }
  }

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> initialTapSessionKey() =>
      NativeBridge.initialNotificationSessionKey();

  @override
  void dispose() {
    _taps.close();
  }
}

/// Linux 桌面：`org.freedesktop.Notifications`（dbus）。
///
/// 通知 id 与 sessionKey 双向映射：`replaces_id` 用该会话上一次的 id，所以同一
/// 会话的新消息会替换旧通知（不会堆一串），不同会话互不影响。
class LinuxNotificationService implements NotificationService {
  static const _tag = 'notify.linux';
  static const _busName = 'org.freedesktop.Notifications';
  static const _busPath = '/org/freedesktop/Notifications';

  final _taps = StreamController<String>.broadcast();

  DBusClient? _client;
  StreamSubscription<DBusSignal>? _signalSub;

  /// 通知 id（守护进程返回）→ 会话 key，用于点击反查。
  final _idToSession = <int, String>{};

  /// 会话 key → 上次的通知 id，作为 `replaces_id` 实现同会话原地更新。
  final _sessionToId = <String, int>{};

  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      final client = DBusClient.session();
      _client = client;
      // 监听 ActionInvoked：用户点了通知（default 动作或「打开」按钮）
      _signalSub = DBusSignalStream(
        client,
        interface: _busName,
        name: 'ActionInvoked',
      ).listen(_onActionInvoked, onError: (_) {});
      _ready = true;
    } catch (e) {
      // 没有通知守护进程 / 没有 session bus：静默降级为不弹通知
      log.warn('Linux 通知初始化失败: $e', tag: _tag);
    }
  }

  void _onActionInvoked(DBusSignal signal) {
    if (signal.values.isEmpty) return;
    final value = signal.values.first;
    if (value is! DBusUint32) return;
    final key = _idToSession[value.value];
    if (key != null && key.isNotEmpty) _taps.add(key);
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showMessage(MessageNotification n) async {
    final client = _client;
    if (!_ready || client == null) return;
    try {
      final replaces = _sessionToId[n.sessionKey] ?? 0;
      final object = DBusRemoteObject(
        client,
        name: _busName,
        path: DBusObjectPath.unchecked(_busPath),
      );
      final body = n.lines.length > 1
          ? '${n.text}\n${n.lines.join('\n')}'
          : n.text;
      // 桌面端没有「震动」，只处理提示音：关掉时带上 `suppress-sound` hint
      // （org.freedesktop.Notifications 规范里通知服务器认这个键）。
      final hints = <String, DBusValue>{
        if (!n.sound) 'suppress-sound': const DBusBoolean(true),
      };
      final reply = await object.callMethod(_busName, 'Notify', [
        DBusString('MnChat'),
        DBusUint32(replaces),
        DBusString(''),
        DBusString(n.title),
        DBusString(body),
        DBusArray.string(const ['default', '打开']),
        DBusDict.stringVariant(hints),
        DBusInt32(-1),
      ]);
      final returned = reply.values.isNotEmpty ? reply.values.first : null;
      final id = returned is DBusUint32 ? returned.value : replaces;
      if (id > 0) {
        _idToSession[id] = n.sessionKey;
        _sessionToId[n.sessionKey] = id;
      }
    } catch (e) {
      log.warn('Linux 通知发送失败: $e', tag: _tag);
    }
  }

  @override
  Future<void> cancel(String sessionKey) async {
    final client = _client;
    final id = _sessionToId.remove(sessionKey);
    if (!_ready || client == null || id == null) return;
    _idToSession.remove(id);
    try {
      final object = DBusRemoteObject(
        client,
        name: _busName,
        path: DBusObjectPath.unchecked(_busPath),
      );
      await object.callMethod(_busName, 'CloseNotification', [DBusUint32(id)]);
    } catch (e) {
      log.warn('Linux 通知关闭失败: $e', tag: _tag);
    }
  }

  @override
  Future<void> cancelAll() async {
    for (final key in _sessionToId.keys.toList()) {
      await cancel(key);
    }
  }

  /// 桌面端不需要前台服务。
  @override
  Future<void> setBackgroundMode(bool background) async {}

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> initialTapSessionKey() async => null;

  @override
  void dispose() {
    _signalSub?.cancel();
    _signalSub = null;
    final client = _client;
    _client = null;
    _ready = false;
    if (client != null) unawaited(client.close());
    unawaited(_taps.close());
  }
}

/// 其他平台 / 单元测试：什么都不做，也不抛异常。
class NoopNotificationService implements NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showMessage(MessageNotification notification) async {}

  @override
  Future<void> cancel(String sessionKey) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> setBackgroundMode(bool background) async {}

  @override
  Stream<String> get taps => const Stream<String>.empty();

  @override
  Future<String?> initialTapSessionKey() async => null;

  @override
  void dispose() {}
}

/// 按当前平台创建通知服务。
NotificationService createNotificationService() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidNotificationService();
    case TargetPlatform.linux:
      return LinuxNotificationService();
    default:
      return NoopNotificationService();
  }
}
