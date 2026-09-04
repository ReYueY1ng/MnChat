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

  /// 弹出系统通知。
  static Future<bool> showNotification({
    required String title,
    required String text,
    required String sessionKey,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('showNotification', {
        'title': title,
        'text': text,
        'sessionKey': sessionKey,
      }) ??
          false;
    } catch (_) {
      return false;
    }
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