import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/rich_text_view.dart' show buildRichSpans, RichTextView;
import 'widgets/image_viewer.dart' show openImageViewer;
import 'widgets/session_player_info_popup.dart';
import '../core/services/image_disk_cache.dart';

part 'dynamics_detail_state.dart';
part 'dynamics_detail_post.dart';
part 'dynamics_detail_comments.dart';

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

  const DynamicsDetailPage({super.key, required this.post});

  @override
  ConsumerState<DynamicsDetailPage> createState() => _DynamicsDetailPageState();
}
