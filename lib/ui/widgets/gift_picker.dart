/// 赠送礼物面板（浮动）。
///
/// 数据来自 [giftCatalogProvider]（服务端 visual-cfg `new_give_gift_config`），
/// 发送走 `FriendGiftClient.giveGift`（`/miniw/welfare?act=give_gift`），
/// 对齐反编译 `FriendGiftDataMgr:SendFriendGift`（`friendgiftdatamgr.lua:476`）。
///
/// `type`（payType）取值来自 `friendgiftdatamgr.lua:15` 的
/// `paytype = { costItem=3, ad=2, free=1, item=4 }`：
/// 付费礼物用 3（消耗迷你币购买）、看广告用 2、免费礼物用 1、
/// **从礼物仓库赠送用 4**（仓库里有就直接扣库存免费送）。
///
/// 说明：游戏里每个礼物格子会标「仓库里有几个」（`getAccountItemNum`，数据来自
/// 账号服务的 `BillDataSvr.ItemInfo`）——那份数据本客户端没有接入，所以无法展示
/// 持有数量、也无法自动判断「该走仓库还是该扣费」。这里改为让用户显式选择
/// 「从仓库赠送」，由服务端校验（不足会回业务码，界面按码提示）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/gift_catalog.dart';
import '../../core/models/nickname.dart' show plainNickname;
import '../../state/providers.dart';
import 'floating_panel.dart';

/// 弹出礼物面板；[uin] 为收礼好友。
Future<void> showGiftPicker(
  BuildContext context,
  WidgetRef ref, {
  required int uin,
  required String name,
  Rect? anchor,
}) {
  return showFloatingPanel<void>(
    context,
    anchor: anchor,
    width: 560,
    heightFactor: 0.6,
    builder: (ctx, close) =>
        GiftPickerPanel(hostRef: ref, uin: uin, name: name, onDone: close),
  );
}

/// 礼物面板主体（可独立构建，便于测试）。
class GiftPickerPanel extends ConsumerStatefulWidget {
  /// 宿主页面的 ref —— 面板自身在 dialog 里，弹「确认赠送」要用宿主的 context。
  final WidgetRef hostRef;
  final int uin;
  final String name;
  final VoidCallback onDone;

  const GiftPickerPanel({
    super.key,
    required this.hostRef,
    required this.uin,
    required this.name,
    required this.onDone,
  });

  @override
  ConsumerState<GiftPickerPanel> createState() => _GiftPickerPanelState();
}

class _GiftPickerPanelState extends ConsumerState<GiftPickerPanel> {
  bool _sending = false;

  /// 收礼人展示名：服务端昵称带 `[i][color][b]` 这类富文本标记，这里是纯文本，
  /// 必须先过 plainNickname；洗完为空（昵称只由标记组成）时退回迷你号。
  String get _displayName {
    final plain = plainNickname(widget.name);
    return plain.isEmpty ? '${widget.uin}' : plain;
  }

  /// 支付方式（见文件头）。
  static int _payTypeOf(GiftItem g) => g.ad
      ? 2
      : (g.free ? 1 : 3);

  /// 从礼物仓库赠送（`paytype.item`）。
  static const int _payTypeItem = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog =
        ref.watch(giftCatalogProvider).asData?.value ?? GiftCatalog.empty;
    final gifts = catalog.activeAt(DateTime.now());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // 收礼人名字来自服务端昵称，可能带 `[i][color][b]` 这类标记；
                  // 这里是纯文本，不过 plainNickname 就会显示成
                  // 「赠送礼物给 [i][color][b]顾念」（真机实测踩到过）。
                  '赠送礼物给 $_displayName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (catalog.dayIntimaciesLimit > 0)
                Text(
                  '每日默契度上限 ${catalog.dayIntimaciesLimit}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: gifts.isEmpty
              ? const Center(child: Text('取不到礼物配置（或当前无可赠送礼物）'))
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.78,
                      ),
                  itemCount: gifts.length,
                  itemBuilder: (context, i) =>
                      _giftCell(theme, gifts[i]),
                ),
        ),
      ],
    );
  }

  Widget _giftCell(ThemeData theme, GiftItem g) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _sending ? null : () => _confirmAndSend(g),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: _giftIcon(theme, g)),
            const SizedBox(height: 4),
            Text(
              g.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 2),
            if (g.free || g.ad)
              Text(
                g.ad ? '看广告' : '免费',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              )
            else
              Text(
                '${g.costNum} ${g.currency}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            if (g.intimacies > 0)
              Text(
                '默契度 +${g.intimacies}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _giftIcon(ThemeData theme, GiftItem g) {
    final icon = g.icon;
    if (icon != null && icon.startsWith('http')) {
      return Image.network(
        icon,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _fallbackIcon(theme),
      );
    }
    return _fallbackIcon(theme);
  }

  Widget _fallbackIcon(ThemeData theme) => Icon(
    Icons.card_giftcard,
    size: 34,
    color: theme.colorScheme.primary,
  );

  /// 选数量 → 确认 → 发送。
  Future<void> _confirmAndSend(GiftItem g) async {
    final picked = await showDialog<(int, bool)>(
      context: context,
      builder: (ctx) => _GiftCountDialog(gift: g),
    );
    if (picked == null || picked.$1 <= 0 || !mounted) return;
    final (num, fromWarehouse) = picked;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 走 ChatService：成功后它会按游戏的做法补一条礼物卡消息。
      final ok = await widget.hostRef
          .read(chatServiceProvider)
          .sendGift(
            desUin: widget.uin,
            itemId: g.id,
            num: num,
            payType: fromWarehouse ? _payTypeItem : _payTypeOf(g),
            addValue: g.intimacies * num,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? '赠送成功' : '赠送失败')),
      );
      if (ok) widget.onDone();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('赠送失败: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// 赠送份数 + 总价确认。
class _GiftCountDialog extends StatefulWidget {
  final GiftItem gift;

  const _GiftCountDialog({required this.gift});

  @override
  State<_GiftCountDialog> createState() => _GiftCountDialogState();
}

class _GiftCountDialogState extends State<_GiftCountDialog> {
  int _num = 1;

  /// 从礼物仓库赠送（免费，扣库存）；由服务端校验是否够。
  bool _warehouse = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.gift;
    final theme = Theme.of(context);
    final payText = _warehouse
        ? '从仓库赠送 $_num 份（仓库不足会失败）'
        : g.free || g.ad
        ? (g.ad ? '看广告赠送 $_num 份' : '免费赠送 $_num 份')
        : '共 ${g.costNum * _num} ${g.currency}';
    return AlertDialog(
      title: Text(g.displayName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('数量'),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: _num > 1 ? () => setState(() => _num--) : null,
              ),
              Text('$_num', style: const TextStyle(fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _num < 99 ? () => setState(() => _num++) : null,
              ),
            ],
          ),
          Text(payText, style: theme.textTheme.bodySmall),
          if (g.intimacies > 0)
            Text(
              '默契度 +${g.intimacies * _num}',
              style: theme.textTheme.bodySmall,
            ),
          // 付费礼物（迷你币购买）允许改用仓库里的存货免费送 —— 本客户端取不到
          // 仓库持有数（见文件头），只能由用户自己选择、服务端校验。
          if (!g.free)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _warehouse,
              title: const Text('从礼物仓库赠送'),
              subtitle: const Text('仓库里有就免费，不足则失败'),
              onChanged: (v) => setState(() => _warehouse = v),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((_num, _warehouse)),
          child: const Text('赠送'),
        ),
      ],
    );
  }
}
