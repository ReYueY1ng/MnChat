/// 赠送礼物面板（浮动）。
///
/// 数据来自 [giftCatalogProvider]（服务端 visual-cfg `new_give_gift_config`），
/// 发送走 `FriendGiftClient.giveGift`（`/miniw/welfare?act=give_gift`），
/// 对齐反编译 `FriendGiftDataMgr:SendFriendGift`（`friendgiftdatamgr.lua:476`）。
///
/// `type`（payType）取值 —— 2026-10-04 用真机逐个实测（同一束 43000 送给自己，
/// 看 `get_gift_data`、余额和 `day_*` 有没有变），**只有 1/3 真的发货**：
/// - `1` = 从仓库扣库存赠送：余额（4 迷你币 / 32 迷你豆）不变、`get_gift` +1；
/// - `3` = 看广告赠送：`day_advert` 0→1 且发货；
/// - `0` / `2` / `4` = 服务端回 `ret:0` 但**什么都不做** —— 静默假成功
///   （`4` 就是「仓库赠送」的旧写法，用它礼物根本没送出去）。
///
/// 所以付费礼物要从仓库送就得先有库存：游戏的做法是 `needNum = 数量 - 已拥有`，
/// 差额走 `buy_give_gift`，再统一按 `type=1` 送出（`main_newgiftsetCtrl`）。
/// 本客户端同样提供「扣费购买赠送」选项，内部就是 `buy_give_gift` + `type=1`。
///
/// 说明：礼物「仓库里有几个」在游戏里取自账号道具背包（`getAccountItemNum` →
/// `BillDataSvr.ItemInfo`）——那份数据只由游戏网关下发，`/miniw/*` 没有对应接口，
/// chatpush 网关的 `baseinfo.update` 也只回 1001，所以本客户端**取不到持有数量**。
/// （`get_gift_data` 的 `get_gift` 是「收到的礼物」，不是仓库，别拿来当库存用。）
/// 因此只能让用户显式选赠送方式，够不够由服务端校验（不足回 120264）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/account_inventory.dart' show AccountInventory;
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

/// 赠送方式（见文件头 `type` 说明）。
enum _GiftPayMode {
  /// 从礼物仓库扣库存（`give_gift type=1`），免费。
  warehouse,

  /// 先买进仓库再送（`buy_give_gift` + `give_gift type=1`），扣迷你币/豆。
  buy,

  /// 免费赠送（`give_gift type=2`）。
  free,

  /// 看广告赠送（`give_gift type=3`）。
  ad,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog =
        ref.watch(giftCatalogProvider).asData?.value ?? GiftCatalog.empty;
    final gifts = catalog.activeAt(DateTime.now());
    final inventory =
        ref.watch(giftInventoryProvider).asData?.value ??
        AccountInventory.empty;
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
                      _giftCell(theme, gifts[i], inventory.countOf(gifts[i].id)),
                ),
        ),
      ],
    );
  }

  Widget _giftCell(ThemeData theme, GiftItem g, int owned) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _sending ? null : () => _confirmAndSend(g, owned),
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
            if (owned > 0)
              Text(
                '仓库 ×$owned',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              )
            else if (g.free || g.ad)
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

  /// 选数量 + 赠送方式 → 确认 → 发送。
  Future<void> _confirmAndSend(GiftItem g, int owned) async {
    final picked = await showDialog<(int, _GiftPayMode)>(
      context: context,
      builder: (ctx) => _GiftCountDialog(gift: g, owned: owned),
    );
    if (picked == null || picked.$1 <= 0 || !mounted) return;
    final (num, mode) = picked;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 走 ChatService：成功后它会按游戏的做法补一条礼物卡消息。
      await widget.hostRef
          .read(chatServiceProvider)
          .sendGift(
            desUin: widget.uin,
            itemId: g.id,
            num: num,
            payType: switch (mode) {
              _GiftPayMode.warehouse || _GiftPayMode.buy => 1,
              _GiftPayMode.free => 2,
              _GiftPayMode.ad => 3,
            },
            buyFirst: mode == _GiftPayMode.buy,
            addValue: g.intimacies * num,
          );
      messenger.showSnackBar(const SnackBar(content: Text('赠送成功')));
      widget.onDone();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('赠送失败: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// 赠送份数 + 赠送方式确认。
class _GiftCountDialog extends StatefulWidget {
  final GiftItem gift;

  /// 该礼物在账号道具背包里的份数（0 = 仓库没货）。
  final int owned;

  const _GiftCountDialog({required this.gift, this.owned = 0});

  @override
  State<_GiftCountDialog> createState() => _GiftCountDialogState();
}

class _GiftCountDialogState extends State<_GiftCountDialog> {
  int _num = 1;
  late _GiftPayMode _mode;

  GiftItem get _g => widget.gift;

  /// 可选方式：**有存货就默认「从仓库赠送」**（免费）；没存货自然把仓库选项排到
  /// 最后，默认落在能成功的那条路上（付费→扣费购买、免费→免費、看广告→广告）。
  List<_GiftPayMode> get _modes {
    final paid = !_g.free && !_g.ad;
    if (widget.owned > 0) {
      return [
        _GiftPayMode.warehouse,
        if (paid) _GiftPayMode.buy,
        if (_g.ad) _GiftPayMode.ad,
        if (_g.free) _GiftPayMode.free,
      ];
    }
    return [
      if (paid) _GiftPayMode.buy,
      if (_g.ad) _GiftPayMode.ad,
      if (_g.free) _GiftPayMode.free,
      _GiftPayMode.warehouse,
    ];
  }

  @override
  void initState() {
    super.initState();
    _mode = _modes.first;
  }

  String _payText() {
    return switch (_mode) {
      _GiftPayMode.warehouse => widget.owned >= _num
          ? '从仓库赠送 $_num 份（免费）'
          : '从仓库赠送 $_num 份（仓库只有 ${widget.owned} 份，会失败）',
      _GiftPayMode.buy => '购买 $_num 份后赠送',
      _GiftPayMode.free => '免费赠送 $_num 份',
      _GiftPayMode.ad => '看广告赠送 $_num 份',
    };
  }

  String _titleOf(_GiftPayMode m) => switch (m) {
    _GiftPayMode.warehouse => '从礼物仓库赠送',
    _GiftPayMode.buy => '扣费购买赠送',
    _GiftPayMode.free => '免费赠送',
    _GiftPayMode.ad => '看广告赠送',
  };

  String _subOf(_GiftPayMode m) => switch (m) {
    _GiftPayMode.warehouse => '扣仓库库存，免费；仓库 ×${widget.owned}',
    _GiftPayMode.buy => '先买进仓库再送，扣 ${_g.costNum * _num} ${_g.currency}',
    _GiftPayMode.free => '用当日的免费赠送次数',
    _GiftPayMode.ad => '看完广告后送出',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modes = _modes;
    return AlertDialog(
      title: Text(_g.displayName),
      content: SingleChildScrollView(
        child: Column(
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
            Text(_payText(), style: theme.textTheme.bodySmall),
            if (_g.intimacies > 0)
              Text(
                '默契度 +${_g.intimacies * _num}',
                style: theme.textTheme.bodySmall,
              ),
            const Divider(height: 12),
            for (final m in modes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  m == _mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: m == _mode
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                title: Text(_titleOf(m)),
                subtitle: Text(_subOf(m)),
                onTap: () => setState(() => _mode = m),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((_num, _mode)),
          child: const Text('赠送'),
        ),
      ],
    );
  }
}
