/// 聊天数据备份 / 恢复服务 —— 导出当前账号的聊天相关数据为 JSON，
/// 或从 JSON 备份文件合并导入。
///
/// 覆盖 Drift 表 [ChatMessages] / [ChatSessions] / [Friends]（按 `ownerUin` 隔离）。
/// 纯 Dart 实现，不依赖 UI；导入为增量合并，绝不删除或覆盖已有数据。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../storage/app_database.dart';

/// 备份文件格式版本（写入 header 的 `version` 字段）。
const int _kBackupVersion = 1;

/// 去重键分隔符（NUL，正常文本内容中不会出现）。
const String _kKeySep = '\u0000';

/// 备份服务：把账号的聊天数据序列化为 JSON 字节，或从 JSON 合并导入。
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// 导出当前账号的聊天相关数据为 JSON 字节。
  ///
  /// 导出 [ChatMessages] / [ChatSessions] / [Friends] 三张表中
  /// `ownerUin` 等于 [ownerUin] 的行，返回 UTF-8 编码的 JSON。
  Future<List<int>> exportJson(int ownerUin) async {
    final messages = await (_db.select(_db.chatMessages)
          ..where((t) => t.ownerUin.equals(ownerUin))
          ..orderBy([
            (t) => OrderingTerm.asc(t.time),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    final sessions = await (_db.select(_db.chatSessions)
          ..where((t) => t.ownerUin.equals(ownerUin))
          ..orderBy([(t) => OrderingTerm.asc(t.sessionKey)]))
        .get();
    final friends = await (_db.select(_db.friends)
          ..where((t) => t.ownerUin.equals(ownerUin))
          ..orderBy([(t) => OrderingTerm.asc(t.uin)]))
        .get();

    final root = <String, dynamic>{
      'app': 'mnchat',
      'version': _kBackupVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'ownerUin': ownerUin,
      'messages': [for (final m in messages) _messageToJson(m)],
      'sessions': [for (final s in sessions) _sessionToJson(s)],
      'friends': [for (final f in friends) _friendToJson(f)],
    };
    return utf8.encode(jsonEncode(root));
  }

  /// 导入 JSON 字节（merge），返回实际插入的 (消息数, 会话数, 好友数)。
  ///
  /// 解析时对 header 与每一行做防御性校验，跳过格式错误的行；为保持幂等，
  /// 跳过主身份已存在的行（消息：`sessionKey`+`uin`+`time`+`content`；
  /// 会话：`sessionKey`+`ownerUin`；好友：`uin`+`ownerUin`）。
  Future<({int messages, int sessions, int friends})> importJson(
    List<int> bytes,
  ) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('备份文件格式不正确');
    }
    final root = Map<String, dynamic>.from(decoded);
    if (root['app'] != 'mnchat') {
      throw const FormatException('不是 MnChat 的备份文件');
    }
    final version = root['version'];
    if (version is! int || version > _kBackupVersion) {
      throw const FormatException('备份文件版本不受支持');
    }
    final headerOwner = root['ownerUin'];
    final fallbackOwner = headerOwner is int ? headerOwner : 0;

    final messageRows = _objects(root['messages']);
    final sessionRows = _objects(root['sessions']);
    final friendRows = _objects(root['friends']);

    // 汇总导入涉及的所有账号归属，一次性加载各自已有身份集合。
    final owners = <int>{
      for (final r in messageRows) _ownerOf(r, fallbackOwner),
      for (final r in sessionRows) _ownerOf(r, fallbackOwner),
      for (final r in friendRows) _ownerOf(r, fallbackOwner),
    };

    return _db.transaction(() async {
      var insertedMessages = 0;
      var insertedSessions = 0;
      var insertedFriends = 0;

      final existingMessageKeys = await _loadMessageKeys(owners);
      final messageCompanions = <ChatMessagesCompanion>[];
      for (final row in messageRows) {
        final sessionKey = _asString(row['sessionKey']);
        final content = row['content'];
        if (sessionKey.isEmpty || content is! String) continue;
        final owner = _ownerOf(row, fallbackOwner);
        final uin = _asInt(row['uin']);
        final time = _asInt(row['time']);
        final keys = existingMessageKeys.putIfAbsent(owner, () => <String>{});
        if (!keys.add(_messageKey(sessionKey, uin, time, content))) continue;
        messageCompanions.add(
          ChatMessagesCompanion(
            content: Value(content),
            sessionKey: Value(sessionKey),
            uin: Value(uin),
            time: Value(time),
            extendData: Value(_asStringOrNull(row['extendData'])),
            isSuccess: Value(_asBool(row['isSuccess'], true)),
            notTime: Value(_asIntOrNull(row['notTime'])),
            srcUserVersion: Value(_asStringOrNull(row['srcUserVersion'])),
            bubble: Value(_asStringOrNull(row['bubble'])),
            interCode: Value(_asStringOrNull(row['interCode'])),
            groupId: Value(_asIntOrNull(row['groupId'])),
            isSystemMsg: Value(_asBool(row['isSystemMsg'])),
            isTime: Value(_asBool(row['isTime'])),
            direction: Value(_asString(row['direction'], 'in')),
            msgType: Value(_asString(row['msgType'], 'text')),
            ownerUin: Value(owner),
          ),
        );
      }
      if (messageCompanions.isNotEmpty) {
        await _db.batch(
          (b) => b.insertAll(_db.chatMessages, messageCompanions),
        );
        insertedMessages = messageCompanions.length;
      }

      final existingSessionKeys = await _loadSessionKeys(owners);
      final sessionCompanions = <ChatSessionsCompanion>[];
      for (final row in sessionRows) {
        final sessionKey = _asString(row['sessionKey']);
        if (sessionKey.isEmpty) continue;
        final owner = _ownerOf(row, fallbackOwner);
        final keys = existingSessionKeys.putIfAbsent(owner, () => <String>{});
        if (!keys.add(_sessionKey(sessionKey, owner))) continue;
        sessionCompanions.add(
          ChatSessionsCompanion(
            sessionKey: Value(sessionKey),
            typeId: Value(_asInt(row['typeId'])),
            name: Value(_asString(row['name'])),
            avatar: Value(_asStringOrNull(row['avatar'])),
            lastTime: Value(_asInt(row['lastTime'])),
            lastReadTime: Value(_asInt(row['lastReadTime'])),
            unreadCount: Value(_asInt(row['unreadCount'])),
            lastUin: Value(_asIntOrNull(row['lastUin'])),
            lastText: Value(_asStringOrNull(row['lastText'])),
            ownerUin: Value(owner),
          ),
        );
      }
      if (sessionCompanions.isNotEmpty) {
        await _db.batch(
          (b) => b.insertAll(_db.chatSessions, sessionCompanions),
        );
        insertedSessions = sessionCompanions.length;
      }

      final existingFriendKeys = await _loadFriendKeys(owners);
      final friendCompanions = <FriendsCompanion>[];
      for (final row in friendRows) {
        final uin = _asIntOrNull(row['uin']);
        if (uin == null) continue;
        final owner = _ownerOf(row, fallbackOwner);
        final keys = existingFriendKeys.putIfAbsent(owner, () => <int>{});
        if (!keys.add(uin)) continue;
        friendCompanions.add(
          FriendsCompanion(
            uin: Value(uin),
            nickname: Value(_asString(row['nickname'])),
            avatar: Value(_asStringOrNull(row['avatar'])),
            isOnline: Value(_asBool(row['isOnline'])),
            gameStatus: Value(_asStringOrNull(row['gameStatus'])),
            updatedAt: Value(_asInt(row['updatedAt'])),
            relation: Value(_asInt(row['relation'])),
            mark: Value(_asInt(row['mark'])),
            ownerUin: Value(owner),
          ),
        );
      }
      if (friendCompanions.isNotEmpty) {
        await _db.batch((b) => b.insertAll(_db.friends, friendCompanions));
        insertedFriends = friendCompanions.length;
      }

      return (
        messages: insertedMessages,
        sessions: insertedSessions,
        friends: insertedFriends,
      );
    });
  }

  /// 加载指定账号集合下已有的消息身份键。
  Future<Map<int, Set<String>>> _loadMessageKeys(Set<int> owners) async {
    final result = <int, Set<String>>{};
    for (final owner in owners) {
      final rows = await (_db.select(_db.chatMessages)
            ..where((t) => t.ownerUin.equals(owner)))
          .get();
      result[owner] = {
        for (final r in rows)
          _messageKey(r.sessionKey, r.uin, r.time, r.content),
      };
    }
    return result;
  }

  /// 加载指定账号集合下已有的会话身份键。
  Future<Map<int, Set<String>>> _loadSessionKeys(Set<int> owners) async {
    final result = <int, Set<String>>{};
    for (final owner in owners) {
      final rows = await (_db.select(_db.chatSessions)
            ..where((t) => t.ownerUin.equals(owner)))
          .get();
      result[owner] = {
        for (final r in rows) _sessionKey(r.sessionKey, owner),
      };
    }
    return result;
  }

  /// 加载指定账号集合下已有的好友身份键。
  Future<Map<int, Set<int>>> _loadFriendKeys(Set<int> owners) async {
    final result = <int, Set<int>>{};
    for (final owner in owners) {
      final rows = await (_db.select(_db.friends)
            ..where((t) => t.ownerUin.equals(owner)))
          .get();
      result[owner] = {for (final r in rows) r.uin};
    }
    return result;
  }
}

String _messageKey(String sessionKey, int uin, int time, String content) =>
    '$sessionKey$_kKeySep$uin$_kKeySep$time$_kKeySep$content';

String _sessionKey(String sessionKey, int ownerUin) =>
    '$sessionKey$_kKeySep$ownerUin';

int _ownerOf(Map<String, dynamic> row, int fallback) {
  final value = row['ownerUin'];
  return value is int ? value : fallback;
}

Map<String, dynamic> _messageToJson(ChatMessageRecord m) => {
  'id': m.id,
  'content': m.content,
  'sessionKey': m.sessionKey,
  'uin': m.uin,
  'time': m.time,
  'extendData': m.extendData,
  'isSuccess': m.isSuccess,
  'notTime': m.notTime,
  'srcUserVersion': m.srcUserVersion,
  'bubble': m.bubble,
  'interCode': m.interCode,
  'groupId': m.groupId,
  'isSystemMsg': m.isSystemMsg,
  'isTime': m.isTime,
  'direction': m.direction,
  'msgType': m.msgType,
  'ownerUin': m.ownerUin,
};

Map<String, dynamic> _sessionToJson(ChatSessionRecord s) => {
  'sessionKey': s.sessionKey,
  'typeId': s.typeId,
  'name': s.name,
  'avatar': s.avatar,
  'lastTime': s.lastTime,
  'lastReadTime': s.lastReadTime,
  'unreadCount': s.unreadCount,
  'lastUin': s.lastUin,
  'lastText': s.lastText,
  'ownerUin': s.ownerUin,
};

Map<String, dynamic> _friendToJson(FriendRecord f) => {
  'uin': f.uin,
  'nickname': f.nickname,
  'avatar': f.avatar,
  'isOnline': f.isOnline,
  'gameStatus': f.gameStatus,
  'updatedAt': f.updatedAt,
  'relation': f.relation,
  'mark': f.mark,
  'ownerUin': f.ownerUin,
};

List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List) return const [];
  final result = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is Map) result.add(Map<String, dynamic>.from(item));
  }
  return result;
}

int _asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _asString(Object? value, [String fallback = '']) {
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

String? _asStringOrNull(Object? value) {
  if (value is String) return value;
  return value?.toString();
}

bool _asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  return fallback;
}
