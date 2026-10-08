import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/nickname.dart' show plainNickname;
import '../core/services/dynamics.dart';
import '../core/services/profile.dart' show PlayerProfile, ProfileClient;
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart' show buildRichSpans, RichTextView;
import 'widgets/image_viewer.dart' show openImageViewer;
import 'widgets/session_player_info_popup.dart';
import 'dynamics_topic_page.dart' show DynamicsTopicPage;
import '../core/services/image_disk_cache.dart';

part 'dynamics_detail_state.dart';
part 'dynamics_detail_post.dart';
part 'dynamics_detail_comments.dart';

/// AppBar「本人动态管理」overflow 菜单按钮的 Key（测试定位用）。
const Key dynamicsPostMenuKey = Key('dynamics_post_menu');

/// 动态管理菜单的 tooltip（同时是测试/无障碍定位锚点）。
const String dynamicsPostMenuTooltip = '动态管理';

/// 评论条目「更多操作」菜单的 tooltip（列表内有 N 条，故用 tooltip 而非 Key，
/// 避免同层出现重复 Key）。
const String dynamicsCommentMenuTooltip = '评论操作';

/// 回复条目「更多操作」菜单的 tooltip（同上，用 tooltip 定位）。
const String dynamicsReplyMenuTooltip = '回复操作';

/// 动态详情页 —— 左侧动态全文，右侧评论区；窄屏上下堆叠。
/// 点头像弹玩家卡片：由页面注入（带被点对象的资料 + 指针全局坐标）。
typedef PlayerCardTap =
    void Function(
      int uin,
      String name,
      String? avatar,
      int? headFrameId,
      Offset position,
    );

class DynamicsDetailPage extends ConsumerStatefulWidget {
  final DynamicsPost post;

  /// 动态服务客户端注入点（测试 / 预览用）。
  ///
  /// 缺省 null：页面自己按 `chatServiceProvider.auth` 构造 `DynamicsClient`
  /// （与其它动态页一致）。测试注入一个挂了假 Dio adapter 的客户端，用来断言
  /// 「点了菜单/按钮后究竟发了哪个 `act`」。
  final DynamicsClient? client;

  const DynamicsDetailPage({super.key, required this.post, this.client});

  @override
  ConsumerState<DynamicsDetailPage> createState() => _DynamicsDetailPageState();
}
