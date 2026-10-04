part of 'providers.dart';

// ── 表情仓库 ─────────────────────────────────────────────────────────────

/// 表情仓库（表情包配置 / 已拥有 / 素材下载缓存）。
/// 未登录或表情客户端尚未建立时返回 null。
final emojiStoreProvider = Provider<EmojiStore?>((ref) {
  final auth = ref.watch(authProvider).auth;
  final client = ref.read(chatServiceProvider).emoji;
  if (auth == null || client == null) return null;
  return EmojiStore(client: client);
});


/// 礼物目录（服务端 visual-cfg `new_give_gift_config` + `items`）。
///
/// 拉不到时返回空目录，赠送面板会提示「取不到礼物配置」而不是瞎编列表。
final giftCatalogProvider = FutureProvider<GiftCatalog>((ref) async {
  return GiftConfigClient().catalog();
});

/// 账号道具背包（主账号长连接 `baseinfo.update` → `Account.BillDataSvr.ItemInfo`）。
///
/// 礼物面板用它显示每个礼物「仓库 ×N」，并在有存货时默认「从仓库赠送」。
/// 拉不到（未登录/断网/连接建不起来）就当空背包：面板退回按礼物配置扣费、
/// 免费或看广告，只是当作「仓库没货」处理，不会把用户卡住。
final giftInventoryProvider = FutureProvider<AccountInventory>((ref) async {
  try {
    return await ref.watch(chatServiceProvider).accountInventory();
  } catch (_) {
    return AccountInventory.empty;
  }
});
