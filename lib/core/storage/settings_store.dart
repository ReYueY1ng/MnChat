/// 应用设置持久化 —— 基于 Drift `settings` 表的 key-value 存储。
///
/// 用 Drift 表替代原 path_provider JSON 文件：Drift 在 Web 走 WASM/IndexedDB、
/// 原生走 SQLite，同一套代码跨平台统一（原文件方案在 Web 上不可用，
/// 会因 `getApplicationSupportDirectory()`/`File` 抛错）。
library;

import '../crypto/credential_cipher.dart' show decryptPassword, encryptPassword;
import 'app_database.dart' show AppDatabase;

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

/// 设置存储：直接读写 Drift 设置表。
class SettingsStore {
  final AppDatabase _db;

  SettingsStore(this._db);

  /// 读取字符串设置；不存在返回 null。
  Future<String?> getString(String key) => _db.getSetting(key);

  /// 读取布尔设置。
  Future<bool> getBool(String key, {bool fallback = false}) async {
    final v = await getString(key);
    return v == null ? fallback : v == '1';
  }

  Future<void> setString(String key, String value) =>
      _db.setSetting(key, value);

  Future<void> setBool(String key, bool value) =>
      setString(key, value ? '1' : '0');

  /// 保存自动登录凭据（密码以 v1 密文形式落库，避免明文泄露）。
  Future<void> saveCredentials(int uin, String password) async {
    await _db.setSetting(SettingsKeys.savedUin, '$uin');
    await _db.setSetting(
      SettingsKeys.savedPassword,
      encryptPassword(password, uin),
    );
  }

  /// 读取自动登录凭据；未保存或密文被篡改返回 null。
  /// 旧版明文密码由 decryptPassword 内部兼容处理，无需额外迁移逻辑。
  Future<SavedCredentials?> loadCredentials() async {
    final uinStr = await getString(SettingsKeys.savedUin);
    final pwd = await getString(SettingsKeys.savedPassword);
    final uin = int.tryParse(uinStr ?? '');
    if (uin == null || pwd == null || pwd.isEmpty) return null;
    final plain = decryptPassword(pwd, uin);
    if (plain == null) return null;
    return SavedCredentials(uin: uin, password: plain);
  }

  /// 清除自动登录凭据。
  Future<void> clearCredentials() async {
    await _db.clearSetting(SettingsKeys.savedUin);
    await _db.clearSetting(SettingsKeys.savedPassword);
  }
}
