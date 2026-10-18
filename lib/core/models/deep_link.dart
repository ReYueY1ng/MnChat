/// 应用深链解析（纯函数：无 IO、无平台通道、不 import Flutter）。
///
/// 支持的形态（scheme 大小写不敏感；允许末尾 `/`、查询串、`#` 片段）：
/// - `mnchat://friend/273640665` → 打开好友会话
/// - `mnchat://group/10086` → 打开群会话
/// - `mnchat://open/group/10086` → 同上（显式 `open` 形式，便于扩展）
/// - `mnchat://favorites` / `mnchat://search` / `mnchat://partners` → 打开固定页面
/// - `mnchat://video?url=<http(s) URL 或本地路径>` → 打开应用内视频播放页
/// - 裸会话 key：`friend_123` / `group_456`（通知与 Android intent 里就是这个形态）
///
/// 脏数据（scheme 不符、id 非正整数、未知 host、空串）一律返回 null，绝不抛 ——
/// 与 `models/` 其它解析器同一口径。
library;

import 'messages.dart' show ChatSessionType;
import 'session_key.dart' show sessionKeyOf;

/// 深链可直达的固定页面。
enum DeepLinkView {
  /// 收藏夹。
  favorites,

  /// 跨会话聊天记录搜索。
  search,

  /// 搭子（拍档 + 最近玩伴）。
  partners,
}

/// 一次深链解析的结果：要么是会话，要么是固定页面。
class DeepLink {
  /// 会话类型（与 [sessionId] 同时非空才表示"打开会话"）。
  final ChatSessionType? sessionType;

  /// 会话 id（好友 = uin，群 = group_id）。
  final int? sessionId;

  /// 固定页面。
  final DeepLinkView? view;

  /// 视频深链要播放的地址（本地路径或 http(s) URL）；非视频链为 null。
  final String? videoUrl;

  const DeepLink.session(this.sessionType, this.sessionId)
    : view = null,
      videoUrl = null;

  const DeepLink.page(this.view)
    : sessionType = null,
      sessionId = null,
      videoUrl = null;

  /// 应用内视频播放：`mnchat://video?url=…`。
  const DeepLink.video(this.videoUrl)
    : sessionType = null,
      sessionId = null,
      view = null;

  /// 是否为“打开某个会话”。
  bool get isSession => sessionType != null && sessionId != null;

  /// 是否为“播放一个视频”。
  bool get isVideo => videoUrl != null;

  /// 会话 key（`friend_123` / `group_456`），可直接交给通知点击同一条路径
  /// （`MainShell` 只认这个格式）。
  String? get sessionKey =>
      isSession ? sessionKeyOf(sessionType!, sessionId!) : null;

  @override
  String toString() => isSession
      ? 'DeepLink.session(${sessionType!.name}, $sessionId)'
      : isVideo
      ? 'DeepLink.video($videoUrl)'
      : 'DeepLink.page(${view?.name})';
}

/// URI scheme。
const String kDeepLinkScheme = 'mnchat';

/// 解析一个深链字符串；无法识别返回 null。
DeepLink? parseDeepLink(String? url) {
  final raw = url?.trim() ?? '';
  if (raw.isEmpty) return null;

  // 裸会话 key（通知 / intent 里常见）。
  final bare = _parseBareSessionKey(raw);
  if (bare != null) return bare;

  Uri uri;
  try {
    uri = Uri.parse(raw);
  } catch (_) {
    return null;
  }
  if (uri.scheme.toLowerCase() != kDeepLinkScheme) return null;

  // `mnchat://friend/1` → host=friend, pathSegments=[1]
  // `mnchat:friend/1`   → host='', pathSegments=[friend, 1]
  var segments = <String>[
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments.where((s) => s.isNotEmpty),
  ];
  if (segments.isEmpty) return null;
  // 显式 open 形式：跳过它继续解析。
  if (segments.first.toLowerCase() == 'open') {
    segments = segments.sublist(1);
    if (segments.isEmpty) return null;
  }

  final head = segments.first.toLowerCase();
  switch (head) {
    case 'friend':
    case 'group':
      if (segments.length < 2) return null;
      final id = int.tryParse(segments[1]);
      if (id == null || id <= 0) return null;
      return DeepLink.session(
        head == 'group' ? ChatSessionType.group : ChatSessionType.friend,
        id,
      );
    case 'favorites':
    case 'favorite':
    case 'star':
      return const DeepLink.page(DeepLinkView.favorites);
    case 'search':
      return const DeepLink.page(DeepLinkView.search);
    case 'partners':
    case 'partner':
      return const DeepLink.page(DeepLinkView.partners);
    case 'video':
    case 'play':
      // `mnchat://video?url=…`（也认 `src`）；地址为空一律当脏数据丢弃。
      final src = (uri.queryParameters['url'] ?? uri.queryParameters['src'] ?? '')
          .trim();
      if (src.isEmpty) return null;
      return DeepLink.video(src);
    default:
      return null;
  }
}

/// 裸会话 key → [DeepLink]；不是合法 key 返回 null。
DeepLink? _parseBareSessionKey(String raw) {
  if (raw.contains('://') || raw.contains('/')) return null;
  final sep = raw.lastIndexOf('_');
  if (sep <= 0) return null;
  final typeName = raw.substring(0, sep).toLowerCase();
  final id = int.tryParse(raw.substring(sep + 1));
  if (id == null || id <= 0) return null;
  switch (typeName) {
    case 'friend':
      return DeepLink.session(ChatSessionType.friend, id);
    case 'group':
      return DeepLink.session(ChatSessionType.group, id);
    default:
      return null;
  }
}
