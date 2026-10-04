import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/friend_tag.dart';
import '../core/models/messages.dart';
import '../core/services/chat_service.dart' show SessionSnapshot;
import '../core/services/partner.dart';
import '../core/services/rich_media.dart' show RichMedia;
import '../state/providers.dart';
import 'friend_request_page.dart' show FriendRequestPage, showAddFriendDialog;
import 'blacklist_page.dart';
import 'family_page.dart';
import 'my_qr_page.dart';
import 'nearby_page.dart';
import 'partner_page.dart';
import 'player_home_page.dart';
import 'quit_group_page.dart';
import 'relation_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/friend_filter_dialog.dart';
import 'widgets/friend_tag_dialog.dart';
import 'widgets/head_frame.dart';
import 'widgets/partner_badges.dart';
import 'widgets/session_menu.dart';
import 'widgets/session_player_info_popup.dart';
import 'widgets/rich_text_view.dart';

part 'friends_page_state.dart';
part 'friends_page_list.dart';

/// 好友页 —— 通讯录：全部联系人 + 关系分类 + 好友申请入口。
///
/// 数据源与"会话"共享 ChatService 的好友会话（每个好友一条 session），
/// 展示昵称 / 迷你号 / 在线游玩状态 / 关系。点击任意好友直接进入聊天。
class FriendsPage extends ConsumerStatefulWidget {
  /// 点击好友（uin）发起聊天时回调，供外层导航切换到会话 tab。
  final ValueChanged<int>? onOpenChat;

  const FriendsPage({super.key, this.onOpenChat});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}
