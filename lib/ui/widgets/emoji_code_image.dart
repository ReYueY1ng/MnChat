/// 消息内联表情渲染 —— 把表情代码渲染为图片。
///
/// - 旧表情（`#A1xx` / `#A3xx`）：走内置图集；
/// - 动态包（`[mdemo]2&...`）：素材是 spine，读外部转好的内置 webp 动图
///   （`assets/emoticon/anim/<图ID>.webp`）。真实 `infos.list` 里 `ID` 与 `icon`
///   同名（如 `ani_expression_OK`），所以图 ID 直接就是素材名 —— 不必先拿到包配置，
///   **未拥有的包也能渲染**（与游戏一致：配置对所有包都下发）；
/// - 静态新包（`[mdemo]1&...`）：下载解包后的本地 png。
///
/// 对齐反编译 `MainChatView` / `ChatEmojiView` 的取图逻辑
/// （`GetEmojiSrc`：旧包走图集、新包读本地文件）。
library;

import 'dart:io' show File;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chat_emoji.dart' show emojiRepr;
import '../../core/emoticon.dart' show EmojiAnimImage, EmoticonImage, rectForCode;
import '../../core/models/emoji_catalog.dart'
    show
        EmojiCodeRef,
        EmojiPackType,
        emojiPackAnimName,
        interactiveAnimName,
        parseEmojiCodeRefs;
import '../../state/providers.dart';

/// 渲染一段表情代码（`#A1xx` 或 `[mdemo]...[/mdemo]`）。
class EmojiCodeImage extends ConsumerStatefulWidget {
  /// 表情代码（单段）。
  final String code;

  /// 渲染尺寸（px）。
  final double size;

  /// 是否播动画；历史消息传 false（直接显示结果帧）。
  final bool animate;

  const EmojiCodeImage({
    super.key,
    required this.code,
    this.size = 18,
    this.animate = true,
  });

  @override
  ConsumerState<EmojiCodeImage> createState() => _EmojiCodeImageState();
}

class _EmojiCodeImageState extends ConsumerState<EmojiCodeImage> {
  EmojiCodeRef? _ref;

  /// 静态新包下载后的本地文件路径。
  String? _path;
  bool _resolved = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final refs = parseEmojiCodeRefs(widget.code);
    _ref = refs.isEmpty ? null : refs.first;
    final r = _ref;
    // 只有「静态新包」需要异步下载；旧表情走图集、动态包读内置动图，都是同步。
    if (r != null && r.fromDynamic && r.type != EmojiPackType.dynamic) {
      _download();
    } else {
      _resolved = true;
    }
  }

  Future<void> _download() async {
    final r = _ref!;
    final store = ref.read(emojiStoreProvider);
    final path =
        store == null ? null : await store.ensurePicByCode(r.packId, r.picId);
    if (!mounted) return;
    setState(() {
      _path = path;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = widget.code;
    final r = _ref;

    // 旧表情：图集可解析则用图集，否则退化为近似 Unicode。
    if (r == null || !r.fromDynamic) {
      if (rectForCode(code) != null) {
        return EmoticonImage(code: code, size: widget.size);
      }
      return Text(
        emojiRepr(code),
        style: TextStyle(fontSize: widget.size * 0.95),
      );
    }

    // 动态包：读内置 webp 动图（素材名带包 ID，未拥有的包也能显示）。
    if (r.type == EmojiPackType.dynamic) {
      // 骰子/猜拳是包内两条 spine 骨架，`图ID>结果` 才是真身（没有对应的「图」文件）。
      final interactive = interactiveAnimName(r.picId, anim: r.anim);
      if (interactive != null) {
        return EmojiAnimImage(
          // 结果写在最后一帧上，所以带结果时停末帧（与 `@IMFC` 同款处理）。
          name: interactive,
          size: widget.size,
          loop: r.anim == null,
          animate: widget.animate,
          fallback: () => _placeholder(theme),
        );
      }
      return EmojiAnimImage(
        name: emojiPackAnimName(r.packId, r.picId),
        size: widget.size,
        fallback: () => _placeholder(theme),
      );
    }

    // 静态新包：下载解包后的本地 png。
    final path = _path;
    if (path != null) {
      return Image.file(
        File(path),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _placeholder(theme),
      );
    }
    if (!_resolved) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }
    return _placeholder(theme);
  }

  /// 素材不可用时的占位（不显示冗长的 `[mdemo]...` 原文）。
  Widget _placeholder(ThemeData theme) => Icon(
        Icons.emoji_emotions_outlined,
        size: widget.size,
        color: theme.colorScheme.outline,
      );
}
