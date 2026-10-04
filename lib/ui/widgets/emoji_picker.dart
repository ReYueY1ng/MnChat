/// 表情面板 —— 对齐游戏「ChatEmoji」浮动面板：
///
/// ```text
/// ┌───────────────────────────────────────┐
/// │  当前表情包的表情网格（8 列，可滚动）    │
/// ├───────────────────────────────────────┤
/// │ ＋ │ 基础 │ 互动 │ 包1 │ 包2(会员) │ ⚙ │   ← 底部表情包栏
/// └───────────────────────────────────────┘
/// ```
///
/// 行为来源（反编译 `miniui/module/chat/chatemoji/*`）：
/// - 面板是**浮动**的（`isFullScreen = false`；`ChatEmojiView:SetAligment` 贴锚点
///   上方居中）；
/// - 底部栏每个包用包里第一张图当图标，`GetType == Vip` 的包挂「会员」角标
///   （`ChatEmojiView:47-64` 的 `needMember` 控制器）；
/// - 「＋」进表情包管理/商店（`ChatEmojiCtrl:BtnAddClick`）、齿轮进管理
///   （`BtnManageClick`）；
/// - 点表情：静态包把代码插进输入框；动态包 / 互动表情 `autoSend`（立即发送）。
library;

import 'dart:io' show File;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chat_emoji.dart' show emojiRepr, kGameEmojiCodes;
import '../../core/emoticon.dart'
    show EmojiAnimImage, EmoticonImage, rectForCode;
import '../../core/models/emoji_catalog.dart'
    show
        EmojiGetType,
        EmojiPack,
        EmojiPic,
        ImfcEmoji,
        emojiPackAnimName,
        interactiveAnimName,
        kImfcEmojis;
import '../../core/services/emoji_store.dart' show EmojiPackView, EmojiStore;
import '../../state/providers.dart' show emojiStoreProvider;
import '../theme/app_tokens.dart';
import 'floating_panel.dart';

/// 弹出表情面板（浮动，浮在 [anchor] 上方）。
///
/// [onPick] 收到要插入输入框的表情代码；[onImfc] 收到要**立即发送**的互动表情
/// （骰子 / 猜拳，游戏里 `autoSend = true`）。
Future<void> showEmojiPicker(
  BuildContext context,
  WidgetRef ref, {
  required ValueChanged<String> onPick,
  ValueChanged<ImfcEmoji>? onImfc,
  Rect? anchor,
}) {
  return showFloatingPanel<void>(
    context,
    anchor: anchor,
    width: 520,
    heightFactor: 0.5,
    builder: (ctx, close) => EmojiPickerPanel(
      store: ref.read(emojiStoreProvider),
      onPick: (code) {
        close();
        onPick(code);
      },
      onImfc: onImfc == null
          ? null
          : (e) {
              close();
              onImfc(e);
            },
    ),
  );
}

/// 面板里的一「页」：一个表情包（或内置基础表情 / 互动表情）。
class _Page {
  final String title;
  final EmojiPack? pack;
  final List<EmojiPic> pics;
  final bool isBase;
  final bool isImfc;

  const _Page({
    required this.title,
    this.pack,
    this.pics = const [],
    this.isBase = false,
    this.isImfc = false,
  });

  /// 需要会员才能用（`GetType == Vip`）→ 底部栏挂「会员」角标。
  bool get requiresVip => pack?.getType == EmojiGetType.vip;
}

/// 表情面板主体（可独立构建，便于测试）。
class EmojiPickerPanel extends StatefulWidget {
  final EmojiStore? store;
  final ValueChanged<String> onPick;
  final ValueChanged<ImfcEmoji>? onImfc;

  const EmojiPickerPanel({
    super.key,
    required this.store,
    required this.onPick,
    this.onImfc,
  });

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  int _index = 0;
  List<_Page>? _pages;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = widget.store;
    var packs = const <EmojiPackView>[];
    if (store != null) {
      try {
        packs = await store.load();
      } catch (_) {
        packs = const <EmojiPackView>[];
      }
    }
    if (!mounted) return;
    setState(() {
      _pages = [
        const _Page(title: '基础', isBase: true),
        if (widget.onImfc != null) const _Page(title: '互动', isImfc: true),
        for (final v in packs)
          _Page(title: v.pack.displayTitle, pack: v.pack, pics: v.pics),
      ];
      _index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Column(
      children: [
        Expanded(
          child: pages == null
              ? const Center(child: CircularProgressIndicator())
              : _grid(pages[_index.clamp(0, pages.length - 1)]),
        ),
        const Divider(height: 1),
        _packBar(pages ?? const <_Page>[]),
      ],
    );
  }

  Widget _grid(_Page page) {
    final theme = Theme.of(context);
    if (page.isImfc) {
      return _cellGrid(
        itemCount: kImfcEmojis.length,
        itemBuilder: (context, i) {
          final e = kImfcEmojis[i];
          return _tappable(
            onTap: () => widget.onImfc?.call(e),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EmoticonImage(sprite: e.icon, size: 40, fallback: e.title),
                Text(e.title, style: theme.textTheme.labelSmall),
              ],
            ),
          );
        },
      );
    }
    if (page.isBase) {
      final codes = kGameEmojiCodes.toList();
      return _cellGrid(
        itemCount: codes.length,
        itemBuilder: (context, i) => _tappable(
          onTap: () => widget.onPick(codes[i]),
          child: EmoticonImage(code: codes[i], size: 44),
        ),
      );
    }
    final store = widget.store;
    final pack = page.pack!;
    if (store == null) return const Center(child: Text('暂无可用的表情包'));
    return _cellGrid(
      itemCount: page.pics.length,
      itemBuilder: (context, i) => _EmojiPicCell(
        store: store,
        pack: pack,
        pic: page.pics[i],
        onPick: () => widget.onPick(store.sendCode(pack, page.pics[i])),
      ),
    );
  }

  Widget _cellGrid({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    if (itemCount == 0) return const Center(child: Text('暂无可用的表情包'));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
        childAspectRatio: 1,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }

  Widget _tappable({required Widget child, required VoidCallback onTap}) =>
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: child)),
      );

  /// 底部表情包栏：＋ / 各包 / 齿轮。
  Widget _packBar(List<_Page> pages) {
    return SizedBox(
      height: 62,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        children: [
          _barButton(
            tooltip: '添加表情包',
            icon: Icons.add,
            onTap: () => _hint('表情包商城暂未开放'),
          ),
          for (var i = 0; i < pages.length; i++) _packTab(i, pages[i]),
          _barButton(
            tooltip: '表情设置',
            icon: Icons.settings,
            onTap: () => _hint('表情包管理暂未开放'),
          ),
        ],
      ),
    );
  }

  Widget _packTab(int i, _Page page) {
    final theme = Theme.of(context);
    final selected = i == _index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: page.title,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _index = i),
          child: Container(
            width: 52,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              border: selected
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _tabIcon(page),
                  ),
                ),
                if (page.requiresVip)
                  Positioned(
                    right: -2,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '会员',
                        style: TextStyle(fontSize: 9, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabIcon(_Page page) {
    if (page.isImfc) {
      return EmoticonImage(sprite: kImfcEmojis.first.icon, size: 34);
    }
    if (page.isBase) {
      return EmoticonImage(code: kGameEmojiCodes.first, size: 34);
    }
    final store = widget.store;
    if (store == null || page.pics.isEmpty) {
      return const Icon(Icons.emoji_emotions_outlined, size: 26);
    }
    return _EmojiPicCell(
      store: store,
      pack: page.pack!,
      pic: page.pics.first,
      onPick: null,
      size: 34,
    );
  }

  Widget _barButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(icon, size: 26),
          ),
        ),
      ),
    );
  }

  void _hint(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 包内单个表情单元格：旧包走本地图集 / 近似 Unicode，动态包读内置动图，
/// 远程静态包按需下载后显示本地图。
class _EmojiPicCell extends StatefulWidget {
  final EmojiStore store;
  final EmojiPack pack;
  final EmojiPic pic;

  /// 为空表示只当图标用（不可点）。
  final VoidCallback? onPick;
  final double size;

  const _EmojiPicCell({
    required this.store,
    required this.pack,
    required this.pic,
    required this.onPick,
    this.size = 44,
  });

  @override
  State<_EmojiPicCell> createState() => _EmojiPicCellState();
}

class _EmojiPicCellState extends State<_EmojiPicCell> {
  String? _path;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // 只有「静态新包」需要下载；旧包走图集、动态包读内置动图。
    if (widget.pack.isLegacy || widget.pack.isDynamic) return;
    _prepare();
  }

  Future<void> _prepare() async {
    final p = await widget.store.ensurePicFile(widget.pack, widget.pic);
    if (!mounted) return;
    setState(() {
      _path = p;
      _failed = p == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _content(Theme.of(context));
    if (widget.onPick == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.onPick,
      child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: content)),
    );
  }

  Widget _content(ThemeData theme) {
    final code = widget.store.sendCode(widget.pack, widget.pic);
    // 旧包：1 号包（熊孩子）有本地图集坐标；其余旧包（花小楼等）用近似 Unicode。
    if (widget.pack.isLegacy) {
      if (rectForCode(code) != null) {
        return EmoticonImage(code: code, size: widget.size);
      }
      return Text(emojiRepr(code), style: const TextStyle(fontSize: 30));
    }
    // 动态包：素材是 spine，读外部转好的内置 webp 动图（素材名带包 ID）。
    if (widget.pack.isDynamic) {
      final icon = widget.pic.iconName.isNotEmpty
          ? widget.pic.iconName
          : widget.pic.picId;
      // 骰子/猜拳是包内 spine 骨架，没有对应的「图」文件，映射到内置互动素材。
      final interactive =
          interactiveAnimName(widget.pic.picId) ?? interactiveAnimName(icon);
      return EmojiAnimImage(
        name: interactive ?? emojiPackAnimName(widget.pack.id, icon),
        size: widget.size,
        fallback: () => _fallback(theme),
      );
    }
    final path = _path;
    if (path != null) {
      return Image.file(
        File(path),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _fallback(theme),
      );
    }
    if (_failed) return _fallback(theme);
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  /// 下载失败/图缺失时的占位（点击仍可插入代码，由游戏端渲染）。
  Widget _fallback(ThemeData theme) => Icon(
    Icons.emoji_emotions_outlined,
    size: widget.size * 0.7,
    color: theme.colorScheme.outline,
  );
}
