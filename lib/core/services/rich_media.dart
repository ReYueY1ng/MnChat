/// 聊天富媒体消息 —— extend_data(url_encode(base64(JSON))) 的解码与模型。
///
/// 对齐反编译源码 commonshareinterface.lua（ShareType 枚举）与
/// mainchatview.lua（RefreshSendRedPocket / RefreshDynamicNotice 等卡片渲染）：
/// - 红包：Type == "SendFriendRedPocket"，字段 amount（充值金额档位）
/// - 动态通知：shareType == 19 (DYNAMIC_NOTICE)，字段 pid/content/pic_list
/// - 地图分享：shareType == 1 (MAP)，字段 name/author 等
/// - 作品/动态分享：shareType == 18 (DYNAMICS)
/// - 链接：shareType == 9 (URL)
library;

import 'dart:convert';

/// ShareType 枚举（commonshareinterface.lua，仅列客户端可渲染的子集）。
class ShareType {
  static const int text = 0;
  static const int map = 1;
  static const int skin = 2;
  static const int ride = 3;
  static const int role = 4;
  static const int avatar = 5;
  static const int url = 9;
  static const int dynamics = 18;
  static const int dynamicNotice = 19; // DYNAMIC_NOTICE（@我/评论通知卡）
  static const int familyInvite = 37;

  static const Map<int, String> labels = {
    map: '地图',
    skin: '皮肤',
    ride: '载具',
    role: '角色',
    avatar: '头像',
    url: '链接',
    dynamics: '动态',
    dynamicNotice: '动态',
    familyInvite: '家族邀请',
  };

  static String label(int v) => labels[v] ?? '分享';
}

  /// 解码后的富媒体消息（extend_data 的 JSON 内容）。
class RichMedia {
  /// shareType 数值（缺省 0=文本）。
  final int shareType;

  /// 红包专用：Type == "SendFriendRedPocket"。
  final String type;

  /// 通用昵称（发送者，显示在卡片上）。
  final String nickname;

  /// 红包金额档（amount，服务器按价查配置）。
  final int amount;

  /// 动态通知/动态分享：动态 pid（"uin_ct"）。
  final String pid;

  /// 动态内容（url 编码，需 decode）。
  final String content;

  /// 动态图片。
  final List<String> picList;

  /// 地图/作品名与作者。
  final String name;
  final String author;

  /// 链接 url。
  final String url;

  /// 房间邀请（Type=InviteJoinRoom）：房间名 / 房主 uin / 人数。
  final String roomName;
  final int roomUin;
  final int playerNum;
  final int playerMaxNum;

  /// 原始解码 JSON（供扩展渲染）。
  final Map<String, Object?> raw;

  const RichMedia({
    required this.shareType,
    this.type = '',
    this.nickname = '',
    this.amount = 0,
    this.pid = '',
    this.content = '',
    this.picList = const [],
    this.name = '',
    this.author = '',
    this.url = '',
    this.roomName = '',
    this.roomUin = 0,
    this.playerNum = 0,
    this.playerMaxNum = 0,
    this.raw = const {},
  });

  bool get isRedPacket => type == 'SendFriendRedPocket';

  bool get isRoomInvite => type == 'InviteJoinRoom' || type == 'FriendJoinRoom';

  bool get isDynamicNotice => shareType == ShareType.dynamicNotice;

  bool get isDynamics => shareType == ShareType.dynamics;

  bool get isMap => shareType == ShareType.map;

  bool get isUrl => shareType == ShareType.url;

  /// 展示标题（供卡片顶栏）。
  String get title {
    if (isRedPacket) return '迷你红包';
    if (isRoomInvite) return '房间邀请';
    if (isDynamicNotice || isDynamics) return '动态';
    if (isMap) return '地图分享';
    if (isUrl) return '链接';
    return ShareType.label(shareType);
  }

  /// 卡片副文案。
  String get subtitle {
    if (isRedPacket) return '金币红包 · 点击查看';
    if (isRoomInvite) {
      final room = roomName.isNotEmpty ? roomName : '房间';
      final num = playerMaxNum > 0 ? ' · $playerNum/$playerMaxNum 人' : '';
      return '$room$num';
    }
    if (name.isNotEmpty) return name;
    if (url.isNotEmpty) return url;
    return content.isEmpty ? title : content;
  }

  /// 从 url_encode(base64(JSON)) 解码；失败返回 null。
  static RichMedia? decode(String? rawExt) {
    if (rawExt == null || rawExt.isEmpty) return null;
    try {
      // url_decode（兼容 %XX 与 %3D 等）
      var urldecoded = rawExt;
      if (urldecoded.contains('%')) {
        urldecoded = Uri.decodeComponent(
          urldecoded.replaceAll('%3D', '=').replaceAll('%2F', '/').replaceAll('%2B', '+'),
        );
      }
      // base64（兼容 -_ 与 : 变体）
      var normalized = urldecoded.replaceAll('-', '+').replaceAll('_', '/');
      normalized = normalized.replaceAll(':', '=');
      final rem = normalized.length % 4;
      if (rem != 0) normalized = normalized.padRight(normalized.length + (4 - rem), '=');
      final bytes = base64Decode(normalized);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final m = decoded.cast<String, Object?>();

      int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      final pics = <String>[];
      final rawPics = m['pic_list'];
      if (rawPics is List) {
        for (final e in rawPics) {
          if (e is String && e.isNotEmpty) {
            pics.add(e);
          } else if (e is Map) {
            final u = e['url']?.toString();
            if (u != null && u.isNotEmpty) pics.add(u);
          }
        }
      }
      return RichMedia(
        shareType: i(m['shareType'] ?? m['share_type']),
        type: m['Type']?.toString() ?? m['type']?.toString() ?? '',
        nickname: m['nickname']?.toString() ?? m['InviterName']?.toString() ?? '',
        amount: i(m['amount'] ?? m['price'] ?? m['Count']),
        pid: m['pid']?.toString() ?? '',
        content: _safeUrlDecode(m['content']?.toString() ?? ''),
        picList: pics,
        name: m['name']?.toString() ?? m['mapName']?.toString() ?? '',
        author: m['author']?.toString() ?? m['authorName']?.toString() ?? '',
        url: m['url']?.toString() ?? '',
        roomName: m['RoomName']?.toString() ?? '',
        roomUin: i(m['RoomUin'] ?? m['roomUin']),
        playerNum: i(m['PlayerNum'] ?? m['playerNum']),
        playerMaxNum: i(m['PlayerMaxNum'] ?? m['playerMaxNum']),
        raw: m,
      );
    } catch (_) {
      return null;
    }
  }

  static String _safeUrlDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }
}
