/// 别人的个人主页。
///
/// 卡片与「我的主页」完全一致（[ProfilePage]）—— 以前这里的精简版（只有资料卡 +
/// 交友标签 + 家族）会让同一个人的主页在两处长得不一样，现在统一到同一套版块；
/// 关注 / 拉黑、访问记录也由 [ProfilePage] 在非本人模式下处理。
///
/// 保留这个类是因为一堆入口都按 `PlayerHomePage(targetUin:)` 调用：好友列表的
/// 「查看主页」、访客列表、会话菜单的「家园」、玩家浮窗的「个人中心」等。
library;

import 'package:material_ui/material_ui.dart';

import 'profile_page.dart';

class PlayerHomePage extends StatelessWidget {
  /// 要看的玩家 uin。
  final int targetUin;

  const PlayerHomePage({super.key, required this.targetUin});

  @override
  Widget build(BuildContext context) => ProfilePage(targetUin: targetUin);
}
