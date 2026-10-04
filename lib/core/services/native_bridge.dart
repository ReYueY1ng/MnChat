/// 原生侧桥接：后台前台服务 / 系统通知 / 隐藏到后台。
/// 通过 MethodChannel "mnchat/native" 与 MainActivity/ChatBackgroundService 通信。
library;

import 'package:flutter/services.dart';

/// 新消息通知（由 ChatService 收到推送时调用）。
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('mnchat/native');

  /// 启动前台服务（后台收推送保活）。
  static Future<bool> startBackgroundService() async {
    try {
      return await _channel.invokeMethod<bool>('startBackgroundService') ?? false;
    } catch (_) {
      return false; // 非 Android / 调试环境静默失败
    }
  }

  /// 停止前台服务。
  static Future<bool> stopBackgroundService() async {
    try {
      return await _channel.invokeMethod<bool>('stopBackgroundService') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 是否已在运行（前台服务）。
  static Future<bool> isBackgroundServiceRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isBackgroundServiceRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 请求系统通知权限（Android 13+ 运行时申请）。
  ///
  /// 低版本 / 非 Android 返回 true（无需申请）。
  static Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
          true;
    } catch (_) {
      return true; // 非 Android / 无实现：按「无需权限」处理
    }
  }

  /// 弹出一条**按会话区分**的消息通知。
  ///
  /// 通知 id 由原生侧用 `sessionKey` 推导，不同会话各自一条、互不覆盖；
  /// 同一会话重复收到则原地更新。
  static Future<bool> showMessageNotification({
    required String sessionKey,
    required String title,
    required String text,
    List<String> lines = const [],
    bool group = false,
    String? avatarUrl,
    String? avatarAsset,
    bool sound = true,
    bool vibrate = true,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('showMessageNotification', {
            'sessionKey': sessionKey,
            'title': title,
            'text': text,
            'lines': lines,
            'group': group,
            'avatarUrl': avatarUrl,
            'avatarAsset': avatarAsset,
            'sound': sound,
            'vibrate': vibrate,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 取消某个会话的通知。
  static Future<bool> cancelMessageNotification(String sessionKey) async {
    try {
      return await _channel.invokeMethod<bool>('cancelMessageNotification', {
            'sessionKey': sessionKey,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 清空全部消息通知（不含常驻通知）。
  static Future<bool> cancelAllMessageNotifications() async {
    try {
      return await _channel.invokeMethod<bool>(
            'cancelAllMessageNotifications',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 冷启动：应用由点击通知拉起时，取回那次通知的会话 key（只交付一次）。
  static Future<String?> initialNotificationSessionKey() async {
    try {
      return await _channel.invokeMethod<String>(
        'getInitialNotificationSessionKey',
      );
    } catch (_) {
      return null;
    }
  }

  /// 原生 → Dart：用户点击了消息通知。
  ///
  /// 冷启动经 [initialNotificationSessionKey]，热启动经这里回调。
  static void setNotificationTapHandler(void Function(String sessionKey) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onNotificationTap') return null;
      final args = call.arguments;
      final key = args is Map ? args['sessionKey']?.toString() : null;
      if (key != null && key.isNotEmpty) handler(key);
      return null;
    });
  }

  /// 把应用隐藏到后台（不退出，前台服务继续收推送）。
  static Future<bool> moveTaskToBack() async {
    try {
      return await _channel.invokeMethod<bool>('moveTaskToBack') ?? false;
    } catch (_) {
      return false;
    }
  }
}