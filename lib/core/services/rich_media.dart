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

import '../crypto/encoding.dart' show lenientBase64Decode;

/// ShareType 枚举 —— 完整对齐反编译 `commonshareinterface.lua:AfterInit`。
class ShareType {
  static const int text = 0;
  static const int map = 1;
  static const int skin = 2;
  static const int ride = 3;
  static const int role = 4;
  static const int avatar = 5;
  static const int screenshot = 6;
  static const int battleVictory = 7;
  static const int battleFailure = 8;
  static const int url = 9;
  static const int achieve = 10;
  static const int chameleon = 11;
  static const int weapon = 12;
  static const int greatEwallGuard = 13;
  static const int douluoTeam = 14;
  static const int weekendCarnival = 15;
  static const int bpCompetitionMsg = 16;
  static const int pat = 17; // 拍一拍（配合 cmd=take_pat）
  static const int dynamics = 18;
  static const int dynamicNotice = 19; // DYNAMIC_NOTICE（@我/评论通知卡）
  static const int action = 20;
  static const int bpFlyChess = 21;
  static const int customPic = 22;
  static const int customPanel = 23; // ReqSendCustomMsg 自定义面板卡
  static const int customCrShare = 24;
  static const int customFlowersShare = 25;
  static const int versionResCrShare = 26;
  static const int customExploreAct = 27;
  static const int customWeekSignShare = 30;
  static const int customTreasureSummon = 31;
  static const int dynamicInviteAnswer = 32;
  static const int customFishCollectShare = 33;
  static const int customPeerShare = 34;
  static const int resourceGoodShare = 35;
  static const int familyRecruit = 36;
  static const int familyInvite = 37;
  static const int familyServer = 38;
  static const int customSpmtShare = 39;
  static const int familyDynamics = 40;
  static const int familyRedPacket = 42;
  static const int rankSystem = 43;
  static const int contentFavsShare = 44;
  static const int qixiPartnerInvite = 45;
  static const int avatarMatch = 46;
  static const int mscardShare = 52;

  static const Map<int, String> labels = {
    text: '文本',
    map: '地图',
    skin: '皮肤',
    ride: '载具',
    role: '角色',
    avatar: '头像',
    screenshot: '截图',
    battleVictory: '对战胜利',
    battleFailure: '对战失败',
    url: '链接',
    achieve: '成就',
    chameleon: '变色龙皮肤',
    weapon: '武器',
    pat: '拍一拍',
    dynamics: '动态',
    dynamicNotice: '动态',
    action: '动作',
    customPic: '图片',
    customPanel: '卡片',
    resourceGoodShare: '资源',
    familyRecruit: '家族招募',
    familyInvite: '家族邀请',
    familyServer: '家族服务器',
    familyDynamics: '家族动态',
    familyRedPacket: '家族红包',
    rankSystem: '排行榜',
    qixiPartnerInvite: '伙伴邀请',
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

  /// 拍一拍文案（shareType == PAT，`tapText`）。
  final String tapText;

  /// 自定义面板卡（shareType == CUSTOM_PANEL）标题/内容/主按钮文案。
  final String panelTitle;
  final String panelContent;
  final String panelMainText;

  /// 赠送礼物（Type=SendFriendGift）：道具 id / 数量 / 增加默契度 / 送礼人昵称。
  ///
  /// 对齐 `friendgiftdatamgr.lua:404-413` 的 `t_extendData`
  /// （`Type/itemid/num/addValue/des_uin/src_uin/src_name/token`）。
  final int giftItemId;
  final int giftNum;
  final int giftAddValue;
  final String giftSrcName;

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
    this.tapText = '',
    this.panelTitle = '',
    this.panelContent = '',
    this.panelMainText = '',
    this.giftItemId = 0,
    this.giftNum = 0,
    this.giftAddValue = 0,
    this.giftSrcName = '',
    this.roomName = '',
    this.roomUin = 0,
    this.playerNum = 0,
    this.playerMaxNum = 0,
    this.raw = const {},
  });

  bool get isRedPacket => type == 'SendFriendRedPocket';

  bool get isRoomInvite => type == 'InviteJoinRoom' || type == 'FriendJoinRoom';

  /// 赠送礼物卡（`Type == SendFriendGift`）。
  bool get isFriendGift => type == 'SendFriendGift';

  /// 是不是**卡片类**富媒体（决定消息走卡片气泡还是普通文本气泡）。
  ///
  /// 对齐游戏客户端：它只看 `extend_data` 的 `Type`/`shareType`，不看 `msg_type`
  /// （`mainchatview.lua:412-450`、`:482`）。
  bool get isCard =>
      isFriendGift ||
      isRedPacket ||
      isRoomInvite ||
      isPat ||
      isAchieve ||
      isCustomPanel ||
      isDynamicNotice ||
      isDynamics ||
      isMap ||
      isUrl ||
      shareType != ShareType.text;

  bool get isDynamicNotice => shareType == ShareType.dynamicNotice;

  bool get isDynamics => shareType == ShareType.dynamics;

  bool get isMap => shareType == ShareType.map;

  bool get isUrl => shareType == ShareType.url;

  /// 拍一拍卡片（`shareType == PAT`，文案取 `tapText`）。
  bool get isPat => shareType == ShareType.pat;

  /// 成就分享卡（`shareType == ACHIEVE`）。
  bool get isAchieve => shareType == ShareType.achieve;

  /// 自定义面板卡（`shareType == CUSTOM_PANEL`，标题/内容/主按钮）。
  bool get isCustomPanel => shareType == ShareType.customPanel;

  /// 展示标题（供卡片顶栏）。
  String get title {
    if (isFriendGift) return '默契礼物';
    if (isRedPacket) return '迷你红包';
    if (isRoomInvite) return '房间邀请';
    if (isPat) return '拍一拍';
    if (isAchieve) return '成就';
    if (isCustomPanel) {
      return panelTitle.isNotEmpty ? panelTitle : '卡片';
    }
    if (isDynamicNotice || isDynamics) return '动态';
    if (isMap) return '地图分享';
    if (isUrl) return '链接';
    return ShareType.label(shareType);
  }

  /// 卡片副文案。
  String get subtitle {
    if (isFriendGift) {
      final who = giftSrcName.isNotEmpty ? giftSrcName : '好友';
      final n = giftNum > 0 ? '×$giftNum' : '';
      return '$who 送给你 $n'.trim();
    }
    if (isRedPacket) return '金币红包 · 点击查看';
    if (isPat) return tapText.isNotEmpty ? tapText : '拍了拍你';
    if (isCustomPanel) {
      if (panelContent.isNotEmpty) return panelContent;
      if (panelMainText.isNotEmpty) return panelMainText;
    }
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
      // base64（兼容 `-_` 字母表、`:` 填充，以及**尾部 `_` 当填充**的变体）
      final bytes = lenientBase64Decode(urldecoded);
      if (bytes == null) return null;
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
      final custom = m['customData'];
      final customMap = custom is Map ? custom.cast<String, Object?>() : const <String, Object?>{};
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
        tapText: m['tapText']?.toString() ?? '',
        panelTitle: customMap['strTitle']?.toString() ?? '',
        panelContent: customMap['strContent']?.toString() ?? '',
        panelMainText: customMap['mainTxt']?.toString() ?? '',
        giftItemId: i(m['itemid'] ?? m['itemId']),
        giftNum: i(m['num']),
        giftAddValue: i(m['addValue'] ?? m['add_value']),
        giftSrcName: m['src_name']?.toString() ?? m['srcName']?.toString() ?? '',
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
