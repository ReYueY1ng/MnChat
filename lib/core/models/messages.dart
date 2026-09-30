/// 聊天数据模型 —— 对齐反编译源码调研的字段结构。
/// (friendservice.lua AddNewGroupChatMessage 归一化字段 + chat_query 三元组)
library;

import 'dart:convert';

import '../crypto/encoding.dart' show lenientBase64Decode;
import 'emoji_catalog.dart' show parseEmojiCodeRefs, parseImfc;

/// 消息类型。
enum ChatMsgType { text, share, custom, system }

/// 把协议里的类型字段（string/num）归一化为 [ChatMsgType]，未知回退 text。
ChatMsgType chatMsgTypeFrom(Object? v) {
  if (v is num) {
    // 常见 msg_type 数值：0=text, 1=share(分享), 2=custom(互动)
    return switch (v.toInt()) {
      1 => ChatMsgType.share,
      2 => ChatMsgType.custom,
      _ => ChatMsgType.text,
    };
  }
  if (v is String) {
    final s = v.toLowerCase();
    if (s.contains('share')) return ChatMsgType.share;
    if (s.contains('custom') || s.contains('interactive')) return ChatMsgType.custom;
    if (s.contains('system') || s.contains('create')) return ChatMsgType.system;
  }
  return ChatMsgType.text;
}

/// 会话类型。
enum ChatSessionType { friend, group, system }

/// 宽松的百分号解码：遇到非法 `%XX` 就把 `%` 当普通字符，不抛异常。
///
/// `Uri.decodeComponent` 碰到畸形转义会抛，而游戏侧 `url_encode` 的输出偶尔会带
/// 裸 `%`；直接抛会让整条消息退化成提示文案（表情就没了）。
String lenientPercentDecode(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '%' && i + 2 < s.length) {
        final v = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
        if (v != null) {
          out.writeCharCode(v);
          i += 2;
          continue;
        }
      }
      out.write(c);
    }
    return out.toString();
  }
}

/// 解码聊天 `extend_data`：`url_decode(base64(JSON))` → Map；失败返回 null。
///
/// 群消息（`group_chat_notify`）与好友消息（`chat_notify` 的 extend_data）用同一套
/// 编码：`url_encode(base64(JSON{nickname, shareType, bubble, interCode, ...}))`。
Map<String, Object?>? decodeChatExtendData(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final urldecoded = lenientPercentDecode(
      raw.replaceAll('%3D', '=').replaceAll('%2F', '/').replaceAll('%2B', '+'),
    );
    // base64 有几种变体（`_` 既可能是 `/` 也可能是填充），交给宽松解码器。
    final bytes = lenientBase64Decode(urldecoded);
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return null;
    return decoded.cast<String, Object?>();
  } catch (_) {
    return null;
  }
}

/// 从消息里取出「应当整条渲染成表情」的代码；不是表情消息则返回 null。
///
/// 背景：收到**动态表情**时，游戏把低版本文案放在消息 `text`
/// （`【您收到一条动态表情，请升级到最新版本查看】`），真正的表情代码放在
/// `extend_data` 的 `interCode`（`[mdemo]<Type>&<包ID>&<图ID>` 或 `@IMFC&<序号>_<结果>`）。
/// 直接渲染 `text` 就会看到那句提示文案而不是表情。
String? emojiCodeForMessage({String? text, String? interCode}) {
  // 文本本身就是互动表情的 JSON 信封 / 裸代码
  if (parseImfc(text) != null) return text;
  final code = interCode?.trim() ?? '';
  if (code.isEmpty) return null;
  if (parseImfc(code) != null) return code; // 骰子 / 猜拳
  if (parseEmojiCodeRefs(code).isNotEmpty) return code; // [mdemo] / #A1xx
  return null;
}

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

  /// 是否「本进程运行期间到的」消息（新收到 / 自己刚发）。
  ///
  /// **不入库**：只有它才播互动表情的动画；从库里读出来的历史消息直接显示结果帧
  /// （骰子/猜拳是即时反馈，翻旧记录不该一遍遍重播）。
  final bool isLive;

  /// 是否时间分隔条。
  final bool isTime;

  /// 消息类型（text/share/custom/system）。默认 text；system 时也会被
  /// [isSystemMsg] 标记，两者保持一致。
  final ChatMsgType type;

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
    this.isLive = false,
    this.isTime = false,
    this.type = ChatMsgType.text,
  });

  /// 从 chat_query 三元组 [who, ts, msg] 构造（buddymanager.lua）。
  factory ChatMessage.fromChatQueryTriple(List<dynamic> triple) {
    final who = triple.isNotEmpty ? (triple[0] as num).toInt() : 0;
    final ts = triple.length > 1 ? (triple[1] as num).toInt() : 0;
    final msg = triple.length > 2 ? triple[2]?.toString() ?? '' : '';
    final isSys = who == 1000;
    return ChatMessage(
      uin: who,
      text: msg,
      time: ts,
      isSystemMsg: isSys,
      type: isSys ? ChatMsgType.system : ChatMsgType.text,
    );
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
      type: chatMsgTypeFrom(m['Type'] ?? m['type'] ?? m['msg_type']),
    );
  }

  /// 从 chat_notify 推送构造（friendservice.lua chat_notify 字段）。
  ///
  /// extend_data 里可能带 `interCode`（动态表情 / 互动表情的真身）—— 推送的
  /// `chat_msg` 往往只是低版本提示文案，所以这里把它解出来挂到 [interCode]。
  factory ChatMessage.fromChatNotify(Map<String, Object?> m) {
    final ext = m['extend_data']?.toString();
    final interCode =
        m['inter_code']?.toString() ??
        decodeChatExtendData(ext)?['interCode']?.toString();
    return ChatMessage(
      uin: (m['src_uin'] as num? ?? 0).toInt(),
      text: m['chat_msg']?.toString() ?? '',
      time: (m['send_time'] as num?)?.toInt() ?? 0,
      extendData: ext,
      interCode: interCode,
      type: chatMsgTypeFrom(m['msg_type'] ?? m['type']),
    );
  }

  /// 复制并覆盖部分字段（只用于「补回丢失字段」，传 null 表示保持原值）。
  ChatMessage copyWith({
    String? extendData,
    String? interCode,
    String? bubble,
    int? notTime,
    int? groupId,
  }) => ChatMessage(
        uin: uin,
        text: text,
        time: time,
        extendData: extendData ?? this.extendData,
        isSuccess: isSuccess,
        notTime: notTime ?? this.notTime,
        srcUserVersion: srcUserVersion,
        bubble: bubble ?? this.bubble,
        interCode: interCode ?? this.interCode,
        groupId: groupId ?? this.groupId,
        isSystemMsg: isSystemMsg,
        isTime: isTime,
        type: type,
        isLive: isLive,
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
        'msg_type': type.name,
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
        type: chatMsgTypeFrom(json['msg_type']),
      );

  @override
  String toString() => 'ChatMessage(uin=$uin time=$time "${text.length > 20 ? text.substring(0, 20) : text}")';
}

/// 消息按 [ChatMessage.time]（epoch 秒）升序稳定排序。
/// 返回新列表，不修改入参；time 相等时保持原有相对顺序（稳定排序）。
/// flutter_chat_ui 需要按时间升序的消息列表（修复 drift DESC 与内存缓存不一致）。
List<ChatMessage> sortMessagesAscending(Iterable<ChatMessage> msgs) {
  final indexed = <(int, ChatMessage)>[];
  var i = 0;
  for (final m in msgs) {
    indexed.add((i++, m));
  }
  indexed.sort((a, b) {
    final byTime = a.$2.time.compareTo(b.$2.time);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
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

  /// 上次登录时间（`baseinfo.LastLoginTime`，epoch 秒；0 = 未知）。
  ///
  /// 好友列表的「登录从近到远 / 从远到近」两种排序用它 —— 游戏里也是这个字段
  /// （`newfriendmgr.lua:904-939` 的 `SortFriendOnLinTime`）。
  final int lastLoginTime;

  /// 游玩状态文本（如「游戏中」「组队中」，来自 statusinfo；无则 null）。
  final String? gameStatus;

  /// 最后一条消息。
  final ChatMessage? lastMessage;

  /// 未读数。
  final int unreadCount;

  /// 最后读取时间（秒）。
  final int lastReadTime;

  /// 好友关系位掩码（仅好友会话；群为 0）。
  final int relation;

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）；用于本地渲染头像，无则 null。
  final int? headType;
  final int? headId;

  /// 头像框 id（RoleInfo.head_frame_id）。
  final int? headFrameId;

  const ChatSession({
    required this.id,
    required this.type,
    required this.name,
    this.avatar,
    this.isOnline = false,
    this.lastLoginTime = 0,
    this.gameStatus,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastReadTime = 0,
    this.relation = 0,
    this.headType,
    this.headId,
    this.headFrameId,
  });

  ChatSession copyWith({
    bool? isOnline,
    String? gameStatus,
    ChatMessage? lastMessage,
    int? unreadCount,
    int? lastReadTime,
    String? name,
    int? relation,
    int? headType,
    int? headId,
    int? headFrameId,
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
        relation: relation ?? this.relation,
        headType: headType ?? this.headType,
        headId: headId ?? this.headId,
        headFrameId: headFrameId ?? this.headFrameId,
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
        'relation': relation,
        'head_type': headType,
        'head_id': headId,
        'head_frame_id': headFrameId,
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
        relation: (json['relation'] as num?)?.toInt() ?? 0,
        headType: (json['head_type'] as num?)?.toInt(),
        headId: (json['head_id'] as num?)?.toInt(),
        headFrameId: (json['head_frame_id'] as num?)?.toInt(),
      );
}

/// 联系人（好友）。
class Contact {
  final int uin;
  final String nickname;
  final String? avatar;

  /// 好友关系位掩码（反编译 friend_relation）：
  /// bit0=我申请, bit1=他申请我, bit2=单向, bit3=双向好友, bit4=我关注,
  /// bit5=关注我, bit6=黑名单, bit7=QQ好友。
  final int relation;

  /// 成为好友/最近互动时间戳（relation&8 的好友有值，否则 0）。
  final int mark;

  /// 头像本体 type/id（1=皮肤 3=坐骑 4=立绘）；无则 null。
  final int? headType;
  final int? headId;

  /// 头像框 id。
  final int? headFrameId;

  const Contact({
    required this.uin,
    required this.nickname,
    this.avatar,
    this.relation = 0,
    this.mark = 0,
    this.headType,
    this.headId,
    this.headFrameId,
  });

  /// 是否双向好友（我的好友列表）。
  bool get isEachother => (relation & 8) != 0;

  /// 是否我关注（但非双向）。
  bool get isMyAttention => (relation & 16) != 0;

  /// 是否黑名单。
  bool get isBlack => (relation & 64) != 0;

  /// 是否对方申请我（待处理）。
  bool get isBeApply => (relation & 2) != 0;

  Map<String, Object?> toJson() => {
        'uin': uin,
        'nickname': nickname,
        'avatar': avatar,
        'relation': relation,
        'mark': mark,
        'head_type': headType,
        'head_id': headId,
        'head_frame_id': headFrameId,
      };

  factory Contact.fromJson(Map<String, Object?> json) => Contact(
        uin: (json['uin'] as num).toInt(),
        nickname: json['nickname']?.toString() ?? '',
        avatar: json['avatar']?.toString(),
        relation: (json['relation'] as num?)?.toInt() ?? 0,
        mark: (json['mark'] as num?)?.toInt() ?? 0,
        headType: (json['head_type'] as num?)?.toInt(),
        headId: (json['head_id'] as num?)?.toInt(),
        headFrameId: (json['head_frame_id'] as num?)?.toInt(),
      );
}

/// 好友申请状态。
enum FriendRequestStatus { pending, accepted, rejected, removed }

/// 好友申请（applyed_notify 推送归集；本地持久化，无需独立查询接口）。
class FriendRequest {
  final int uin;
  final String name;
  final String? avatar;
  final int time;
  final FriendRequestStatus status;

  const FriendRequest({
    required this.uin,
    required this.name,
    this.avatar,
    this.time = 0,
    this.status = FriendRequestStatus.pending,
  });

  Map<String, Object?> toJson() => {
        'uin': uin,
        'name': name,
        'avatar': avatar,
        'time': time,
        'status': status.name,
      };

  factory FriendRequest.fromJson(Map<String, Object?> json) => FriendRequest(
        uin: (json['uin'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        avatar: json['avatar']?.toString(),
        time: (json['time'] as num?)?.toInt() ?? 0,
        status: FriendRequestStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => FriendRequestStatus.pending,
        ),
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
      final m = decodeChatExtendData(raw);
      if (m == null) return null;
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

/// 群详情 —— 由 query_user_groups 的 members/creator 归集。
/// 仅存必要的展示/操作字段，成员为 uin 列表（昵称/头像与好友共用 ProfileClient 拉取）。
class GroupInfo {
  final int groupId;
  final String name;

  /// 群主（lord），`identity == 1` 的成员。
  final int creatorUin;

  /// 成员 uin 列表（含群主）。
  final List<int> members;

  /// 我是否被本群静音（ban_group==1 → ignoreAll）。
  final bool isMuteAll;

  const GroupInfo({
    required this.groupId,
    required this.name,
    this.creatorUin = 0,
    this.members = const [],
    this.isMuteAll = false,
  });

  Map<String, Object?> toJson() => {
        'group_id': groupId,
        'name': name,
        'creator_uin': creatorUin,
        'members': members,
        'is_mute_all': isMuteAll,
      };

  factory GroupInfo.fromJson(Map<String, Object?> json) => GroupInfo(
        groupId: (json['group_id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        creatorUin: (json['creator_uin'] as num?)?.toInt() ?? 0,
        members: (json['members'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ?? const [],
        isMuteAll: json['is_mute_all'] as bool? ?? false,
      );
}