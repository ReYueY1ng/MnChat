/// 聊天数据模型 —— 对齐反编译源码调研的字段结构。
/// (friendservice.lua AddNewGroupChatMessage 归一化字段 + chat_query 三元组)
library;

import 'dart:convert';

/// 消息类型。
enum ChatMsgType { text, share, custom, system }

/// 会话类型。
enum ChatSessionType { friend, group, system }

/// 单条聊天消息（好友+群聊归一化）。
class ChatMessage {
  /// 发送者 Uin（number）。
  final int uin;

  /// 文本内容。
  final String text;

  /// 时间戳（秒）。
  final int time;

  /// 扩展数据（气泡/分享 etc，原始字符串）。
  final String? extendData;

  /// 是否发送成功（自己发出的消息）。
  final bool isSuccess;

  /// not_time / src_user_version / bubble / interCode（群消息字段）。
  final int? notTime;
  final String? srcUserVersion;
  final String? bubble;
  final String? interCode;

  /// 群会话时的群 id。
  final int? groupId;

  /// 系统消息标志（chat_query 中 who==1000）。
  final bool isSystemMsg;

  /// 是否时间分隔条。
  final bool isTime;

  const ChatMessage({
    required this.uin,
    required this.text,
    required this.time,
    this.extendData,
    this.isSuccess = true,
    this.notTime,
    this.srcUserVersion,
    this.bubble,
    this.interCode,
    this.groupId,
    this.isSystemMsg = false,
    this.isTime = false,
  });

  /// 从 chat_query 三元组 [who, ts, msg] 构造（buddymanager.lua）。
  factory ChatMessage.fromChatQueryTriple(List<dynamic> triple) {
    final who = triple.isNotEmpty ? (triple[0] as num).toInt() : 0;
    final ts = triple.length > 1 ? (triple[1] as num).toInt() : 0;
    final msg = triple.length > 2 ? triple[2]?.toString() ?? '' : '';
    return ChatMessage(uin: who, text: msg, time: ts, isSystemMsg: who == 1000);
  }

  /// 从群聊归一化 map 构造（AddNewGroupChatMessage 字段）。
  factory ChatMessage.fromGroupNotify(Map<String, Object?> m, {int? groupId}) {
    final timeMs = (m['send_time'] ?? m['time'] ?? 0);
    final timeInt = timeMs is num ? timeMs.toInt() : int.tryParse('$timeMs') ?? 0;
    // send_time 为毫秒需转秒（Group_ChangeSendTimeToSecond）
    final timeSec = timeInt > 9999999999 ? timeInt ~/ 1000 : timeInt;
    return ChatMessage(
      uin: (m['uin'] as num? ?? 0).toInt(),
      text: m['text']?.toString() ?? '',
      time: timeSec,
      extendData: m['extend_data']?.toString() ?? m['shareData']?.toString(),
      isSuccess: (m['is_success'] as bool? ?? true),
      notTime: (m['not_time'] as num?)?.toInt(),
      srcUserVersion: m['src_user_version']?.toString(),
      bubble: m['bubble']?.toString(),
      interCode: m['interCode']?.toString(),
      groupId: groupId ?? (m['groupid'] as num?)?.toInt(),
    );
  }

  /// 从 chat_notify 推送构造（friendservice.lua chat_notify 字段）。
  factory ChatMessage.fromChatNotify(Map<String, Object?> m) => ChatMessage(
        uin: (m['src_uin'] as num? ?? 0).toInt(),
        text: m['chat_msg']?.toString() ?? '',
        time: (m['send_time'] as num?)?.toInt() ?? 0,
        extendData: m['extend_data']?.toString(),
      );

  Map<String, Object?> toJson() => {
        'uin': uin,
        'text': text,
        'time': time,
        'extend_data': extendData,
        'is_success': isSuccess,
        'not_time': notTime,
        'src_user_version': srcUserVersion,
        'bubble': bubble,
        'inter_code': interCode,
        'group_id': groupId,
        'is_system_msg': isSystemMsg,
        'is_time': isTime,
      };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
        uin: (json['uin'] as num).toInt(),
        text: json['text']?.toString() ?? '',
        time: (json['time'] as num).toInt(),
        extendData: json['extend_data']?.toString(),
        isSuccess: json['is_success'] as bool? ?? true,
        notTime: (json['not_time'] as num?)?.toInt(),
        srcUserVersion: json['src_user_version']?.toString(),
        bubble: json['bubble']?.toString(),
        interCode: json['inter_code']?.toString(),
        groupId: (json['group_id'] as num?)?.toInt(),
        isSystemMsg: json['is_system_msg'] as bool? ?? false,
        isTime: json['is_time'] as bool? ?? false,
      );

  @override
  String toString() => 'ChatMessage(uin=$uin time=$time "${text.length > 20 ? text.substring(0, 20) : text}")';
}

/// 会话（好友 / 群）。
class ChatSession {
  /// 会话 id（好友 = 对方 uin；群 = group_id）。
  final int id;

  final ChatSessionType type;

  /// 显示名。
  final String name;

  /// 头像（无真实头像 url 时可为空，UI 用首字渲染）。
  final String? avatar;

  /// 好友是否在线（query_friend_list 的 `online` 字段，仅好友会话有效）。
  final bool isOnline;

  /// 游玩状态文本（如「游戏中」「组队中」，来自 statusinfo；无则 null）。
  final String? gameStatus;

  /// 最后一条消息。
  final ChatMessage? lastMessage;

  /// 未读数。
  final int unreadCount;

  /// 最后读取时间（秒）。
  final int lastReadTime;

  const ChatSession({
    required this.id,
    required this.type,
    required this.name,
    this.avatar,
    this.isOnline = false,
    this.gameStatus,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastReadTime = 0,
  });

  ChatSession copyWith({
    bool? isOnline,
    String? gameStatus,
    ChatMessage? lastMessage,
    int? unreadCount,
    int? lastReadTime,
    String? name,
  }) =>
      ChatSession(
        id: id,
        type: type,
        name: name ?? this.name,
        avatar: avatar,
        isOnline: isOnline ?? this.isOnline,
        gameStatus: gameStatus ?? this.gameStatus,
        lastMessage: lastMessage ?? this.lastMessage,
        unreadCount: unreadCount ?? this.unreadCount,
        lastReadTime: lastReadTime ?? this.lastReadTime,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'avatar': avatar,
        'is_online': isOnline,
        'game_status': gameStatus,
        'last_message': lastMessage?.toJson(),
        'unread_count': unreadCount,
        'last_read_time': lastReadTime,
      };

  factory ChatSession.fromJson(Map<String, Object?> json) => ChatSession(
        id: (json['id'] as num).toInt(),
        type: ChatSessionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ChatSessionType.friend,
        ),
        name: json['name']?.toString() ?? '',
        avatar: json['avatar']?.toString(),
        isOnline: json['is_online'] as bool? ?? false,
        gameStatus: json['game_status']?.toString(),
        lastMessage: json['last_message'] is Map
            ? ChatMessage.fromJson((json['last_message'] as Map).cast<String, Object?>())
            : null,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        lastReadTime: (json['last_read_time'] as num?)?.toInt() ?? 0,
      );
}

/// 联系人（好友）。
class Contact {
  final int uin;
  final String nickname;
  final String? avatar;

  const Contact({required this.uin, required this.nickname, this.avatar});

  Map<String, Object?> toJson() => {'uin': uin, 'nickname': nickname, 'avatar': avatar};

  factory Contact.fromJson(Map<String, Object?> json) => Contact(
        uin: (json['uin'] as num).toInt(),
        nickname: json['nickname']?.toString() ?? '',
        avatar: json['avatar']?.toString(),
      );
}

/// 群聊原始消息（group_chat_notify push 的 t_extend）。
class GroupNotify {
  final String type; // SendMsg / ShareMsg / CreateGroup / ...
  final int groupId;
  final int uin;
  final String text;
  final int sendTime; // 毫秒
  final String? shareData;

  const GroupNotify({
    required this.type,
    required this.groupId,
    required this.uin,
    required this.text,
    required this.sendTime,
    this.shareData,
  });

  /// 从 group_chat_notify extend_data 解码 (url_decode → base64 → JSON)。
  static GroupNotify? fromExtendData(String raw) {
    try {
      final urldecoded = Uri.decodeComponent(raw.replaceAll('%3D', '=').replaceAll('%2F', '/').replaceAll('%2B', '+'));
      final normalized = urldecoded.replaceAll('-', '+').replaceAll('_', '/');
      final pad = normalized.length % 4 == 0 ? '' : '=' * (4 - normalized.length % 4);
      final bytes = base64Decode(normalized + pad);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final m = decoded.cast<String, Object?>();
      final timeMs = (m['send_time'] as num?) ?? (m['time'] as num?) ?? 0;
      return GroupNotify(
        type: m['Type']?.toString() ?? 'SendMsg',
        groupId: (m['groupid'] as num?)?.toInt() ?? 0,
        uin: (m['uin'] as num?)?.toInt() ?? 0,
        text: m['text']?.toString() ?? '',
        sendTime: timeMs.toInt(),
        shareData: m['shareData']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}