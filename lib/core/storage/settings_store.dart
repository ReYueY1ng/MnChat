/// 应用设置持久化 —— 基于 path_provider 的 JSON 文件存储。
/// 用于：自动登录凭据（uin/密码）、自动登录开关、服务器地址等。
///
/// 为什么不用 drift 表：增加 drift 表需要 build_runner 重新生成 .g.dart，
/// 在当前（Termux/aarch64）构建环境里 build_runner 极易挂起；而
/// path_provider 已是项目依赖且原生插件已构建进 APK，文件存储零新增依赖。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 设置项 key 常量。
class SettingsKeys {
  static const String autoLogin = 'auto_login'; // '1'/'0'
  static const String savedUin = 'saved_uin'; // string
  static const String savedPassword = 'saved_password'; // string
  static const String serverBase = 'server_base'; // 服务器地址（留空=默认）
  static const String notifyEnabled = 'notify_enabled'; // 新消息通知 '1'/'0'
  static const String sortMode = 'sort_mode'; // 'time'|'name'|'unread'
}

/// 自动登录凭据。
class SavedCredentials {
  final int uin;
  final String password;
  const SavedCredentials({required this.uin, required this.password});
}

/// 设置存储：读取/写入 JSON 文件 `mnchat_settings.json`。
class SettingsStore {
  File? _file;
  Map<String, Object?> _cache = {};

  Future<File> _settingsFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/mnchat_settings.json');
    return _file!;
  }

  Future<void> _load() async {
    if (_cache.isNotEmpty) return;
    try {
      final f = await _settingsFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _cache = decoded.cast<String, Object?>();
        }
      }
    } catch (_) {
      _cache = {};
    }
  }

  Future<void> _save() async {
    final f = await _settingsFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(_cache));
  }

  /// 读取字符串设置；不存在返回 null。
  Future<String?> getString(String key) async {
    await _load();
    return _cache[key]?.toString();
  }

  /// 读取布尔设置。
  Future<bool> getBool(String key, {bool fallback = false}) async {
    final v = await getString(key);
    return v == null ? fallback : v == '1';
  }

  Future<void> setString(String key, String value) async {
    await _load();
    _cache[key] = value;
    await _save();
  }

  Future<void> setBool(String key, bool value) =>
      setString(key, value ? '1' : '0');

  /// 保存自动登录凭据。
  Future<void> saveCredentials(int uin, String password) async {
    await _load();
    _cache[SettingsKeys.savedUin] = '$uin';
    _cache[SettingsKeys.savedPassword] = password;
    await _save();
  }

  /// 读取自动登录凭据；未保存返回 null。
  Future<SavedCredentials?> loadCredentials() async {
    final uinStr = await getString(SettingsKeys.savedUin);
    final pwd = await getString(SettingsKeys.savedPassword);
    final uin = int.tryParse(uinStr ?? '');
    if (uin == null || pwd == null || pwd.isEmpty) return null;
    return SavedCredentials(uin: uin, password: pwd);
  }

  /// 清除自动登录凭据。
  Future<void> clearCredentials() async {
    await _load();
    _cache.remove(SettingsKeys.savedUin);
    _cache.remove(SettingsKeys.savedPassword);
    await _save();
  }
}
