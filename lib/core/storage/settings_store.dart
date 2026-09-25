/// 应用设置持久化 —— 基于 Drift `settings` 表的 key-value 存储。
///
/// 用 Drift 表替代原 path_provider JSON 文件：走原生 SQLite，避免
/// `getApplicationSupportDirectory()`/`File` 的可用性问题。
library;

import 'dart:convert';

import '../crypto/credential_cipher.dart' show decryptPassword, encryptPassword;
import 'app_database.dart' show AppDatabase;

/// 设置项 key 常量。
class SettingsKeys {
  static const String autoLogin = 'auto_login'; // '1'/'0'
  static const String savedUin = 'saved_uin'; // string（当前账号）
  static const String savedPassword = 'saved_password'; // string
  static const String lastUin = 'last_uin'; // 最后登录账号（账号选择高亮）
  static const String accounts = 'accounts'; // JSON 数组：已保存的多账号
  static const String notifyEnabled = 'notify_enabled'; // 新消息通知 '1'/'0'
  static const String themeMode = 'theme_mode'; // 'system'|'light'|'dark'
  static const String keepAlive = 'keep_alive'; // 后台保活 '1'/'0'
  static const String sortMode = 'sort_mode'; // 'time'|'name'|'unread'
  static const String quickPhrases = 'quick_phrases'; // JSON 数组：快捷短语
  static const String mutedSessions = 'muted_sessions'; // JSON: {key: '1'} 免打扰
  static const String pinnedSessions = 'pinned_sessions'; // JSON: {key: '1'} 置顶

  // ── 通用 / 显示 ─────────────────────────────────────────────────────
  static const String animatedFrames = 'animated_frames'; // 头像框动画 '1'/'0'
  static const String richTextRaw = 'rich_text_raw'; // 富文本显示原文本 '1'/'0'
  static const String chatFontScale = 'chat_font_scale'; // 聊天字号缩放 double 字符串
  static const String seedColor = 'seed_color'; // 主题强调色 ARGB int 字符串

  // ── 消息与输入 ──────────────────────────────────────────────────────
  static const String sendOnEnter = 'send_on_enter'; // 回车发送 '1'/'0'
  static const String autoMarkRead = 'auto_mark_read'; // 进会话自动已读 '1'/'0'
  static const String hideNotifyContent = 'hide_notify_content'; // 通知隐藏内容

  // ── 免打扰时段 ──────────────────────────────────────────────────────
  static const String dndEnabled = 'dnd_enabled'; // '1'/'0'
  static const String dndStart = 'dnd_start'; // 分钟数 0..1439
  static const String dndEnd = 'dnd_end'; // 分钟数 0..1439

  // ── 隐私 ────────────────────────────────────────────────────────────
  static const String lockEnabled = 'app_lock_enabled'; // 应用锁 '1'/'0'
  static const String lockPinHash = 'app_lock_pin_hash'; // PIN 的 SHA-256
  static const String lockPinSalt = 'app_lock_pin_salt'; // PIN 盐
  static const String leaveVisitTrace = 'leave_visit_trace'; // 访问主页留下踪迹 '1'/'0'

  // ── 桌面端 ──────────────────────────────────────────────────────────
  static const String closeToTray = 'close_to_tray'; // 关闭到托盘 '1'/'0'

  /// 会话设置 key（免打扰/置顶），形如 "friend_123" / "group_456"。
  static String sessionKey(String type, int id) => '${type}_$id';
}

/// 自动登录凭据。
class SavedCredentials {
  final int uin;
  final String password;
  const SavedCredentials({required this.uin, required this.password});
}

/// 已保存的账号（切换账号用）。
class SavedAccount {
  final int uin;
  final String password; // 已解密明文
  final String? name;
  const SavedAccount({required this.uin, required this.password, this.name});

  Map<String, Object?> toJson() => {
        'uin': uin,
        'pwd': password,
        'name': name,
      };

  static SavedAccount fromJson(Map<String, Object?> m) => SavedAccount(
        uin: (m['uin'] as num?)?.toInt() ?? 0,
        password: m['pwd']?.toString() ?? '',
        name: m['name']?.toString(),
      );
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

  /// 读取 double 设置；不存在或非法返回 null。
  Future<double?> getDouble(String key) async =>
      double.tryParse(await getString(key) ?? '');

  Future<void> setDouble(String key, double value) => setString(key, '$value');

  /// 读取 int 设置；不存在或非法返回 null。
  Future<int?> getInt(String key) async =>
      int.tryParse(await getString(key) ?? '');

  Future<void> setInt(String key, int value) => setString(key, '$value');

  /// 保存自动登录凭据（当前账号，密码加密落库）。
  Future<void> saveCredentials(int uin, String password) async {
    await _db.setSetting(SettingsKeys.savedUin, '$uin');
    await _db.setSetting(
      SettingsKeys.savedPassword,
      encryptPassword(password, uin),
    );
  }

  /// 读取当前账号的自动登录凭据；未保存或密文被篡改返回 null。
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

  // ── 多账号切换 ────────────────────────────────────────────────────────

  /// 保存/更新一个账号（加入账号列表 + 设为最后登录账号）。
  /// 密码用账号 uin 派生密钥加密后落库；name 仅作展示。
  /// 注意：不写入"自动登录凭据"（saved_uin/saved_password）——
  /// 那由 [saveCredentials] 单独按 autoLogin 开关控制。
  Future<void> saveAccount(
    int uin,
    String password, {
    String? name,
  }) async {
    final accounts = await _loadAccounts();
    accounts.removeWhere((a) => a['uin'] == uin);
    accounts.add({
      'uin': uin,
      'pwd': encryptPassword(password, uin),
      'name': name,
    });
    await _saveAccounts(accounts);
    await _db.setSetting(SettingsKeys.lastUin, '$uin');
  }

  /// 保存/更新一个已登录账号（不额外重加密——login 成功后调用，
  /// 密码已是当前会话使用过的明文，仍加密落库）。
  Future<void> upsertAccount(SavedAccount account) =>
      saveAccount(account.uin, account.password, name: account.name);

  /// 已保存账号列表（解密后的明文密码）。
  Future<List<SavedAccount>> listAccounts() async {
    final accounts = await _loadAccounts();
    final out = <SavedAccount>[];
    for (final a in accounts) {
      final uin = (a['uin'] as num?)?.toInt() ?? 0;
      final enc = a['pwd']?.toString() ?? '';
      if (uin == 0 || enc.isEmpty) continue;
      final plain = decryptPassword(enc, uin);
      if (plain == null) continue; // 密文被篡改/密钥不符 → 跳过
      out.add(
        SavedAccount(uin: uin, password: plain, name: a['name']?.toString()),
      );
    }
    // 最后登录的账号排最前
    final last = await getString(SettingsKeys.lastUin);
    out.sort((a, b) {
      if ('${a.uin}' == last) return -1;
      if ('${b.uin}' == last) return 1;
      return a.uin.compareTo(b.uin);
    });
    return out;
  }

  /// 删除一个已保存账号；若删的是当前账号，同时清当前凭据。
  Future<void> removeAccount(int uin) async {
    final accounts = await _loadAccounts();
    accounts.removeWhere((a) => a['uin'] == uin);
    await _saveAccounts(accounts);
    final cur = await getString(SettingsKeys.savedUin);
    if (cur == '$uin') {
      await clearCredentials();
    }
  }

  Future<List<Map<String, Object?>>> _loadAccounts() async {
    final raw = await getString(SettingsKeys.accounts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final d = jsonDecode(raw);
      if (d is List) {
        return d
            .whereType<Map>()
            .map((m) => m.cast<String, Object?>())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveAccounts(List<Map<String, Object?>> accounts) async {
    await setString(SettingsKeys.accounts, jsonEncode(accounts));
  }

  // ── 快捷短语（对齐游戏 SecretQuickMsg 本地 kv）────────────────────────

  /// 快捷短语列表（默认三条，与游戏一致）。
  Future<List<String>> quickPhrases() async {
    final raw = await getString(SettingsKeys.quickPhrases);
    if (raw == null || raw.isEmpty) {
      const defaults = ['嗨~', '一起来玩呀', '在干嘛'];
      await setString(SettingsKeys.quickPhrases, jsonEncode(defaults));
      return defaults;
    }
    try {
      final d = jsonDecode(raw);
      if (d is List) return d.map((e) => '$e').toList();
    } catch (_) {}
    return const ['嗨~', '一起来玩呀', '在干嘛'];
  }

  /// 新增快捷短语（去重，插到最前，最多 20 条）。返回是否成功。
  Future<bool> addQuickPhrase(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final list = await quickPhrases();
    if (list.contains(t)) return false;
    list.remove(t);
    list.insert(0, t);
    if (list.length > 20) list.removeRange(20, list.length);
    await setString(SettingsKeys.quickPhrases, jsonEncode(list));
    return true;
  }

  /// 删除快捷短语。
  Future<void> removeQuickPhrase(String text) async {
    final list = await quickPhrases();
    list.remove(text);
    await setString(SettingsKeys.quickPhrases, jsonEncode(list));
  }

  // ── 会话免打扰 / 置顶（本地配置）───────────────────────────────────────

  Future<Set<String>> _sessionFlagSet(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      if (d is Map) {
        final out = <String>{};
        for (final e in d.entries) {
          if (e.value.toString() == '1') out.add('${e.key}');
        }
        return out;
      }
    } catch (_) {}
    return {};
  }

  Future<void> _setSessionFlag(String key, String sessionKey2, bool on) async {
    final set = await _sessionFlagSet(key);
    if (on) {
      set.add(sessionKey2);
    } else {
      set.remove(sessionKey2);
    }
    final m = <String, Object?>{for (final k in set) k: '1'};
    await setString(key, jsonEncode(m));
  }

  /// 会话是否免打扰。
  Future<bool> isMuted(String sessionKey2) async {
    final set = await _sessionFlagSet(SettingsKeys.mutedSessions);
    return set.contains(sessionKey2);
  }

  /// 设置会话免打扰。
  Future<void> setMuted(String sessionKey2, bool on) =>
      _setSessionFlag(SettingsKeys.mutedSessions, sessionKey2, on);

  /// 会话是否置顶。
  Future<bool> isPinned(String sessionKey2) async {
    final set = await _sessionFlagSet(SettingsKeys.pinnedSessions);
    return set.contains(sessionKey2);
  }

  /// 设置会话置顶。
  Future<void> setPinned(String sessionKey2, bool on) =>
      _setSessionFlag(SettingsKeys.pinnedSessions, sessionKey2, on);

  // ── 好友备注 / 上线通知（本地，按 uin）─────────────────────────────────

  /// 好友备注名（无则 null）。
  Future<String?> friendNote(int uin) async {
    final v = await getString('friend_note_$uin');
    return (v == null || v.isEmpty) ? null : v;
  }

  /// 设置好友备注名（空白则清除）。
  Future<void> setFriendNote(int uin, String note) async {
    final t = note.trim();
    if (t.isEmpty) {
      await _db.clearSetting('friend_note_$uin');
    } else {
      await setString('friend_note_$uin', t);
    }
  }

  /// 是否开启该好友的上线通知。
  Future<bool> friendOnlineNotify(int uin) => getBool('online_notify_$uin');

  /// 设置好友上线通知。
  Future<void> setFriendOnlineNotify(int uin, bool on) =>
      setBool('online_notify_$uin', on);

  // ── 访客记录（本地，按 uin）───────────────────────────────────────────

  /// 上次向该玩家发送访问记录的时间（epoch 秒）；从未发送返回 0。
  Future<int> visitSentAt(int uin) async {
    final v = await getInt('visit_sent_$uin');
    return v ?? 0;
  }

  /// 记录向该玩家发送访问记录的时间（epoch 秒），用于 24h 去重。
  Future<void> setVisitSentAt(int uin, int epochSeconds) =>
      setInt('visit_sent_$uin', epochSeconds);
}
