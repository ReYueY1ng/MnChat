/// Riverpod 提供者 —— 把 ChatService 暴露给 UI 层。
/// 使用 riverpod 3.x 的 Notifier API（StateNotifier/StateProvider 已在 3.x 移除）。
/// 拆分为 part 文件：providers_core（基础设施单例）/ providers_account（认证、当前会话与本人资料）/ providers_chat（会话与联系人数据流）/ providers_settings（设置、主题、通知、免打扰）/ providers_social（消息中心、请求失败总线、拍档社交）/ providers_media（表情仓库与礼物目录/背包）。
library;

import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_bridge.dart';
import '../core/models/account_inventory.dart' show AccountInventory;
import '../core/models/friend_tag.dart' show FriendTag, parseFriendTagPool;
import '../core/models/gift_catalog.dart' show GiftCatalog;
import '../core/models/messages.dart';
import '../core/services/auth.dart';
import '../core/services/chat_service.dart';
import '../core/services/dynamics.dart';
import '../core/services/emoji_store.dart';
import '../core/services/gift_config.dart' show GiftConfigClient;
import '../core/services/message_center.dart';
import '../core/services/msg_box.dart';
import '../core/services/notification_service.dart';
import '../core/services/partner.dart';
import '../core/services/request_errors.dart' show RequestErrorBus;
import '../core/services/social_sign.dart'
    show DeclarationCatalog, DeclarationConfigClient;
import '../core/services/profile.dart';
import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/settings_store.dart' show SettingsKeys, SettingsStore;
import '../core/utils/log.dart';

part 'providers_core.dart';
part 'providers_account.dart';
part 'providers_chat.dart';
part 'providers_settings.dart';
part 'providers_social.dart';
part 'providers_media.dart';
