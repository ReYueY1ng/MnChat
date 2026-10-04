/// 消息中心 —— 对齐游戏内 MainChat 系统页（双栏 / 窄屏单栏下钻）。
///
/// 结构（参考游戏内截图）：
/// - 顶部 3 个圆入口：动态互动 / 新增粉丝 / 作品互动（`/miniw/msg_box`；
///   动态互动 = post_rep + post_prize + post_at 合并）；
/// - 左侧 7 分类：礼物消息(10005) / 官方邮件(1) / 创作者助手(20001) /
///   系统消息(20002) / 好友邮件(2) / 动态助手(0→msg_box post_sys) / 运营活动(20003)，
///   每行 = 彩色图标 + 标题 + 右侧时间 + 一行摘要 + 未读角标；
/// - 右侧详情：所选分类的消息列表（标题/正文/`详情`/时间）+ 底部
///   `一键已读` / `删除已读`；互动通知条目标题/正文/缩略图 + `N小时前 IP 省`。
///
/// 宽窄判定与 `home_shell` 会话双栏一致（内容宽 ≥760 双栏，否则单栏
/// push-on-tap）。互动通知头像复用 [AvatarView]（角色头 / 头像框走本地资源）。
library;

import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/dynamics.dart' show DynamicsClient;
import '../core/services/message_center.dart';
import '../core/services/msg_box.dart';
import '../core/services/profile.dart' show PlayerProfile, ProfileClient;
import '../state/providers.dart';
import 'dynamics_detail_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart' show headFrameSlotSize, kAvatarListTileDensity;
import '../core/services/image_disk_cache.dart';

part 'mail_page_state.dart';
part 'mail_page_widgets.dart';
part 'mail_page_detail.dart';

/// 宽窄分界：内容宽 ≥760 双栏（对齐 home_shell 会话双栏阈值）。
const double kMailCentreWideWidth = 760;

/// 消息中心选中项：顶部互动入口 或 左列邮件/系统分类（二者互斥）。
class MailSelection {
  /// 顶部 3 入口之一；与 [channel] 互斥。
  final MsgBoxEntry? entry;

  /// `MsgChannel` 频道 id（含动态助手 [MsgChannel.activityAssistant]=0）。
  final int? channel;

  const MailSelection.entry(MsgBoxEntry e)
      : entry = e,
        channel = null;

  const MailSelection.channel(int c)
      : entry = null,
        channel = c;

  bool get isEntry => entry != null;

  @override
  bool operator ==(Object other) =>
      other is MailSelection && other.entry == entry && other.channel == channel;

  @override
  int get hashCode => Object.hash(entry, channel);
}

/// 消息中心主页面。
class MailPage extends ConsumerStatefulWidget {
  /// 打开时聚焦的分类/入口（动态通知 → 动态互动）。
  ///
  /// 窄屏（<[kMailCentreWideWidth]）下非空时直接渲染该分类的详情页（带返回），
  /// 用于列表页 push 下钻；宽屏则作为双栏右栏的初始选中。
  final MailSelection? focus;

  const MailPage({super.key, this.focus});

  @override
  ConsumerState<MailPage> createState() => _MailPageState();
}

/// 相对时间（对齐 messagecenterdatamgr.lua convertTime）。
String fmtMsgTime(int ts) {
  if (ts <= 0) return '';
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final sub = now - ts;
  if (sub <= 60) return '刚刚';
  if (sub <= 3600) return '${sub ~/ 60}分钟前';
  if (sub <= 86400) return '${sub ~/ 3600}小时前';
  if (sub <= 2592000) return '${sub ~/ 86400}天前';
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}

/// `N小时前 IP 省`（互动通知时间行；location 为空时只显示相对时间）。
String fmtMsgTimeIp(int ts, String location) {
  final t = fmtMsgTime(ts);
  if (location.isEmpty) return t;
  return t.isEmpty ? 'IP $location' : '$t IP $location';
}

/// 邮件详情页。
class MailDetailPage extends ConsumerStatefulWidget {
  final MsgItem item;
  final Future<void> Function()? onTake;
  final Future<void> Function()? onDelete;

  const MailDetailPage({
    super.key,
    required this.item,
    this.onTake,
    this.onDelete,
  });

  @override
  ConsumerState<MailDetailPage> createState() => _MailDetailPageState();
}
