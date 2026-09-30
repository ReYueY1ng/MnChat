import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import 'chat_emoji.dart' show emojiRepr;
import 'models/emoji_catalog.dart'
    show
        EmojiPic,
        ImfcRef,
        emojiAnimAsset,
        imfcUnicode,
        kBuiltinPackPics,
        parseEmojiCodeRefs;

/// 游戏 emoji 贴图（TexturePacker 图集 emoticon.png + emoticon.xml 坐标）。
/// 把 `#A1xx` / `#A3xx` 代码渲染成游戏真实图标：code → sprite 名 → 贴图矩形。
///
/// 图集与坐标来自游戏资源 `resources/ui/mobile/texture0/emoticon.xml`
/// （1024×1024，46 个 sprite；仓库内 `assets/emoticon/emoticon.webp` 与之逐像素一致）。
/// code → sprite 名不再手写，而是从内置包定义（`chatconfig.lua` → [kBuiltinPackPics]）
/// 反查，避免两张表各写一份而漏掉 3 号包。

const String kEmoticonAsset = 'assets/emoticon/emoticon.webp';

/// sprite 名 → 贴图矩形（x,y 为左上角，TexturePacker 坐标，y 向下；单位 px）。
const Map<String, Rect> kSpriteRect = {
  // 1 号包「熊孩子」
  'xieyanxiao': Rect.fromLTWH(2, 186, 90, 90),
  'baimu': Rect.fromLTWH(554, 94, 90, 90),
  'shengqi': Rect.fromLTWH(2, 554, 90, 90),
  'xianqi': Rect.fromLTWH(2, 278, 90, 90),
  'daku': Rect.fromLTWH(370, 94, 90, 90),
  'qinqin': Rect.fromLTWH(2, 738, 90, 90),
  'xihuan': Rect.fromLTWH(2, 94, 90, 90),
  'wabikong': Rect.fromLTWH(2, 370, 90, 90),
  'dianzan': Rect.fromLTWH(278, 94, 90, 90),
  'haixiu': Rect.fromLTWH(186, 94, 90, 90),
  'liulei': Rect.fromLTWH(2, 830, 90, 90),
  'keai': Rect.fromLTWH(94, 2, 90, 90),
  'shouqibao': Rect.fromLTWH(2, 462, 90, 90),
  'kun': Rect.fromLTWH(2, 922, 90, 90),
  'jingya': Rect.fromLTWH(186, 2, 90, 90),
  'yun': Rect.fromLTWH(2, 2, 90, 90),
  'shaojiao': Rect.fromLTWH(2, 646, 90, 90),
  'bye': Rect.fromLTWH(462, 94, 90, 90),
  // 3 号包「花小楼」（hua_ 前缀）
  'hua_qinqin': Rect.fromLTWH(94, 94, 90, 90),
  'hua_xieyanxiao': Rect.fromLTWH(462, 2, 90, 90),
  'hua_xianqi': Rect.fromLTWH(554, 2, 90, 90),
  'hua_baimu': Rect.fromLTWH(94, 922, 90, 90),
  'hua_shengqi': Rect.fromLTWH(830, 2, 90, 90),
  'hua_daku': Rect.fromLTWH(94, 738, 90, 90),
  'hua_xihuan': Rect.fromLTWH(370, 2, 90, 90),
  'hua_wabikong': Rect.fromLTWH(646, 2, 90, 90),
  'hua_dianzan': Rect.fromLTWH(94, 646, 90, 90),
  'hua_haixiu': Rect.fromLTWH(94, 554, 90, 90),
  'hua_liulei': Rect.fromLTWH(94, 186, 90, 90),
  'hua_keai': Rect.fromLTWH(94, 370, 90, 90),
  'hua_shouqibao': Rect.fromLTWH(738, 2, 90, 90),
  'hua_kun': Rect.fromLTWH(94, 278, 90, 90),
  'hua_jingya': Rect.fromLTWH(94, 462, 90, 90),
  'hua_yun': Rect.fromLTWH(278, 2, 90, 90),
  'hua_shaojiao': Rect.fromLTWH(922, 2, 90, 90),
  'hua_bye': Rect.fromLTWH(94, 830, 90, 90),
  // 互动表情（骰子 / 猜拳）：1_1..1_6 = 骰子 1..6 点，2_0 = 猜拳封面，
  // 2_1..2_3 = 布 / 剪刀 / 石头（尺寸 75×65，与上面的 90×90 不同）。
  '1_1': Rect.fromLTWH(263, 186, 75, 65),
  '1_2': Rect.fromLTWH(186, 186, 75, 65),
  '1_3': Rect.fromLTWH(877, 161, 75, 65),
  '1_4': Rect.fromLTWH(800, 161, 75, 65),
  '1_5': Rect.fromLTWH(723, 161, 75, 65),
  '1_6': Rect.fromLTWH(646, 161, 75, 65),
  '2_0': Rect.fromLTWH(877, 94, 75, 65),
  '2_1': Rect.fromLTWH(800, 94, 75, 65),
  '2_2': Rect.fromLTWH(723, 94, 75, 65),
  '2_3': Rect.fromLTWH(646, 94, 75, 65),
};

/// 表情代码 → 图集 sprite 名（旧包 `#A<包ID><图ID>` 才走图集；新包 `[mdemo]` 走下载）。
///
/// 从 [kBuiltinPackPics] 反查 `icon` 名（如 `#A306` → `hua_qinqin.png` → `hua_qinqin`）。
String? spriteNameForCode(String code) {
  final refs = parseEmojiCodeRefs(code);
  if (refs.isEmpty) return null;
  final ref = refs.first;
  if (ref.fromDynamic) return null;
  final pics = kBuiltinPackPics[ref.packId];
  if (pics == null) return null;
  for (final EmojiPic p in pics) {
    if (p.picId == ref.picId) {
      final name = p.iconName;
      return name.isEmpty ? null : name;
    }
  }
  return null;
}

/// code → 贴图矩形；无法解析返回 null。
Rect? rectForCode(String code) {
  final sprite = spriteNameForCode(code);
  if (sprite == null) return null;
  return kSpriteRect[sprite];
}

/// 渲染一个游戏表情帧。
///
/// [code] 传表情代码（`#A1xx` / `#A3xx`），或 [sprite] 直接指定图集 sprite 名
/// （互动表情 `1_3`、猜拳封面 `2_0` 等）——两者给其一。
class EmoticonImage extends StatefulWidget {
  final String code;
  final String? sprite;
  final double size;

  /// 图集不可用时展示的兜底文案；为空则用 [emojiRepr]（[code] 的近似 Unicode）。
  final String? fallback;

  const EmoticonImage({
    super.key,
    this.code = '',
    this.sprite,
    this.size = 24,
    this.fallback,
  }) : assert(code != '' || sprite != null, 'code 与 sprite 至少要给一个');

  @override
  State<EmoticonImage> createState() => _EmoticonImageState();
}

class _EmoticonImageState extends State<EmoticonImage> {
  ui.Image? _image;

  static ui.Image? _cached;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_cached != null) {
      if (mounted) setState(() => _image = _cached);
      return;
    }
    try {
      final provider = AssetImage(kEmoticonAsset);
      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info);
          stream.removeListener(listener);
        },
        onError: (e, s) {
          if (!completer.isCompleted) completer.completeError(e);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final info = await completer.future;
      _cached = info.image;
      if (mounted) setState(() => _image = _cached);
    } catch (_) {
      // 加载失败：保持为空，build 里回退文字
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    final sprite = widget.sprite;
    final rect = sprite != null ? kSpriteRect[sprite] : rectForCode(widget.code);
    final size = widget.size;
    if (img == null || rect == null) {
      final text = widget.fallback ?? emojiRepr(widget.code);
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text(text, style: TextStyle(fontSize: size * 0.8))),
      );
    }
    // 图集内 sprite 尺寸不一（表情 90×90、骰子/猜拳 75×65），按原始宽高比等比缩放。
    final dst = _fitRect(rect, size);
    return CustomPaint(
      size: Size.square(size),
      painter: _EmojiPainter(img, rect, dst),
    );
  }
}

class _EmojiPainter extends CustomPainter {
  final ui.Image image;
  final Rect src;
  final Rect dst;

  _EmojiPainter(this.image, this.src, this.dst);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _EmojiPainter old) =>
      old.image != image || old.src != src || old.dst != dst;
}

/// 组件矩形是否已经「进入可视区域」（用于决定何时开始播一次性动画）。
///
/// 聊天列表会把视口外的历史消息也构建出来（`cacheExtent`），那些不该立刻开播：
/// 否则用户滚上去时动画早已播完，看起来就是「历史消息不播、只有新消息才播」。
///
/// 判据：与视口有交集，且**露出高度过半**（刚探个头不算，避免半露就开始播）。
/// 纯函数，便于单测。
bool isWidgetVisible(Rect widgetRect, Size viewport) {
  if (widgetRect.isEmpty || viewport.isEmpty) return false;
  final visible = widgetRect.intersect(Offset.zero & viewport);
  if (visible.isEmpty) return false;
  final shorter = widgetRect.height < viewport.height
      ? widgetRect.height
      : viewport.height;
  return visible.height >= shorter * 0.5;
}

/// 按「已播时长」求当前帧下标（[animDurationsMs] 为各帧时长）。
///
/// 纯函数，便于单测；**结尾夹到最后一帧**，这样动画放完就停在末帧
/// （骰子/猜拳的结果就写在末帧上，不能回绕）。
int animFrameIndexAt(List<int> animDurationsMs, int elapsedMs) {
  if (animDurationsMs.isEmpty) return 0;
  var acc = 0;
  for (var i = 0; i < animDurationsMs.length; i++) {
    acc += animDurationsMs[i];
    if (elapsedMs < acc) return i;
  }
  return animDurationsMs.length - 1;
}

/// 在 [size]×[size] 的方框内等比居中放置 [src]（保持原始宽高比）。
Rect _fitRect(Rect src, double size) {
  final longest = src.width > src.height ? src.width : src.height;
  if (longest <= 0) return Rect.fromLTWH(0, 0, size, size);
  final scale = size / longest;
  final w = src.width * scale;
  final h = src.height * scale;
  return Rect.fromLTWH((size - w) / 2, (size - h) / 2, w, h);
}

/// 互动表情（骰子 / 猜拳）图片：优先播放 webp 动图，其次渲染图集结果帧。
///
/// 游戏端用 spine 播「掷骰子 / 出拳」过程（`RefreshSpineDynamicEmoji`），spine 不能
/// 商用，因此约定把转好的 webp 动图按 `<序号>_<结果>.webp` 放进
/// [kEmojiAnimDir]；有就播动画，没有就退回内置图集里的结果帧（等价于游戏
/// 停留 5 秒后的最终画面）。
///
/// **播完停在最后一帧**（`loop: false`）—— 结果点数/手势靠末帧表达，
/// 无限循环会让人读不出「掷出了几」。
class ImfcEmojiImage extends StatelessWidget {
  final ImfcRef ref;
  final double size;

  /// 是否播动画；历史消息传 false（直接显示结果帧）。
  final bool animate;

  const ImfcEmojiImage({
    super.key,
    required this.ref,
    this.size = 24,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) => EmojiAnimImage(
        name: ref.sprite,
        size: size,
        loop: false,
        animate: animate,
        fallback: () => EmoticonImage(
          sprite: ref.sprite,
          size: size,
          fallback: imfcUnicode(ref),
        ),
      );
}

/// 动态表情动画：`assets/emoticon/anim/<name>.webp`。
///
/// - [loop] = true（默认，表达类表情）：交给 `Image.asset` 原生循环播放 —— 高效，
///   且项目里的头像框动画同款做法；
/// - [loop] = false（骰子/猜拳这类互动表情）：自己解码逐帧推进，**放完停在最后一帧**，
///   因为结果就写在末帧上。
///
/// 素材缺失时调用 [fallback]（静态帧 / 占位），不抛异常。
class EmojiAnimImage extends StatelessWidget {
  final String name;
  final double size;
  final Widget Function() fallback;
  final bool loop;

  /// 是否播动画（只对 `loop: false` 有意义）：false 时直接显示末帧。
  final bool animate;

  const EmojiAnimImage({
    super.key,
    required this.name,
    required this.size,
    required this.fallback,
    this.loop = true,
    this.animate = true,
  });

  /// 仅供测试：清空解码缓存。
  ///
  /// widget 测试里跨 zone 的 Future 可能永远不完成，缓存会「卡住」后续用例；
  /// 每个用例前清一次即可互不影响。
  @visibleForTesting
  static void debugResetCache() {
    _PlayOnceAnimImageState._done.clear();
    _PlayOnceAnimImageState._inflight.clear();
  }

  @override
  Widget build(BuildContext context) {
    final path = emojiAnimAsset(name);
    if (loop) {
      return Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback(),
      );
    }
    return _PlayOnceAnimImage(
      assetPath: path,
      size: size,
      fallback: fallback,
      animate: animate,
    );
  }
}

/// 解码后的动画帧序列（进程内缓存，按素材路径共享）。
class _AnimFrames {
  final List<ui.Image> frames;

  /// 各帧时长（毫秒）。
  final List<int> durations;

  const _AnimFrames(this.frames, this.durations);

  int get totalMs =>
      durations.fold(0, (a, b) => a + b).clamp(1, 1 << 30);
}

/// 「播一次并停在最后一帧」的动画 WebP。
///
/// 为什么不用 `Image.asset`：它只会无限循环，不暴露帧控制。这里用
/// `ui.instantiateImageCodec` 把帧解出来，再用 [AnimationController] 按各帧时长
/// 推进；`forward()`（而非 `repeat()`）天然停在终点。
class _PlayOnceAnimImage extends StatefulWidget {
  final String assetPath;
  final double size;
  final Widget Function() fallback;

  /// false = 不播，直接定格在末帧（历史消息用）。
  final bool animate;

  const _PlayOnceAnimImage({
    required this.assetPath,
    required this.size,
    required this.fallback,
    this.animate = true,
  });

  @override
  State<_PlayOnceAnimImage> createState() => _PlayOnceAnimImageState();
}

class _PlayOnceAnimImageState extends State<_PlayOnceAnimImage>
    with SingleTickerProviderStateMixin {
  /// 解好的帧：互动表情总共 9 个素材、单帧几十 KB，按路径缓存即可。
  static final Map<String, _AnimFrames> _done = {};

  /// 正在解码的（同一素材被多个气泡同时挂载时只解一次）。
  static final Map<String, Future<_AnimFrames?>> _inflight = {};

  AnimationController? _controller;
  _AnimFrames? _data;
  bool _failed = false;
  ScrollPosition? _position;

  /// 首帧之后才允许 `setState`。命中帧缓存时 `_load` 会在 `initState` 里同步
  /// 走完（那时 `setState` 会抛异常），而那时 build 还没跑，直接改字段就够。
  bool _canSetState = false;

  @override
  void initState() {
    super.initState();
    _load();
    // 聊天列表会把视口外的历史消息也构建出来（cacheExtent）。若在 build 时就
    // `forward()`，那些动画在屏幕外就播完了 —— 用户滚上去只看到定格的结果帧
    // （表现为「历史消息不播动画，只有新收到的才播」）。所以等真正进入
    // 可视区域再开播。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _canSetState = true;
      _startIfVisible();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pos = Scrollable.maybeOf(context)?.position;
    if (!identical(pos, _position)) {
      _position?.removeListener(_startIfVisible);
      _position = pos;
      _position?.addListener(_startIfVisible);
    }
    _startIfVisible();
  }

  Future<void> _load() async {
    try {
      final path = widget.assetPath;
      // 命中已解好的帧时**同步**出图：不用多等一个 microtask / 跨 zone 的 await
      //（后者在 widget 测试里甚至可能永远不返回）。
      final cached = _done[path];
      if (cached != null) {
        _apply(cached);
        return;
      }
      final data = await (_inflight[path] ??= _decode(path));
      _inflight.remove(path);
      if (data == null || data.frames.isEmpty) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      _done[path] = data;
      _apply(data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _apply(_AnimFrames data) {
    if (!mounted) return;
    _data = data;
    _refresh();
    // 立即试一次，再排一次「布局完成后」的检查：解码可能晚于首帧，
    // 那时才量得到自己在不在视口里 —— 而列表静止时不会再有滚动事件
    // 来触发检查（会一直不出画面）。
    _startIfVisible();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfVisible());
  }

  void _refresh() {
    if (mounted && _canSetState) setState(() {});
  }

  /// 帧已就绪、该播时开播一次（停在最后一帧）。
  ///
  /// [widget.animate] 为 false（历史消息）时**不等视野**，直接定格末帧：
  /// 列表滚动时那些条目本来就在屏外，等进视野才出图会闪一下空白。
  void _startIfVisible() {
    if (!mounted || _controller != null || _data == null) return;
    if (widget.animate && !_isVisible()) return;
    _position?.removeListener(_startIfVisible);
    _position = null;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _data!.totalMs),
    );
    if (widget.animate) {
      _controller!.forward(); // 播一遍，停在末帧
    } else {
      _controller!.value = 1.0; // 历史消息：直接显示结果帧
    }
    _refresh();
  }

  bool _isVisible() {
    final box = context.findRenderObject();
    final media = MediaQuery.maybeOf(context);
    if (box is! RenderBox || !box.hasSize) return false;
    if (media == null) return true;
    return isWidgetVisible(box.localToGlobal(Offset.zero) & box.size, media.size);
  }

  /// 解码全部帧；失败返回 null（调用方走 fallback）。
  static Future<_AnimFrames?> _decode(String path) async {
    try {
      final bytes = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final frames = <ui.Image>[];
      final durations = <int>[];
      for (var i = 0; i < codec.frameCount; i++) {
        final frame = await codec.getNextFrame();
        frames.add(frame.image);
        durations.add(frame.duration.inMilliseconds);
      }
      codec.dispose();
      return _AnimFrames(frames, durations);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_startIfVisible);
    _position = null;
    _controller?.dispose();
    super.dispose();
  }

  /// 当前应显示的帧下标（按已播时长推进，直到最后一帧）。
  int _frameIndex(_AnimFrames data) => animFrameIndexAt(
        data.durations,
        ((_controller?.value ?? 1.0) * data.totalMs).round(),
      );

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final controller = _controller;
    if (data == null || controller == null) {
      if (_failed) return widget.fallback();
      return SizedBox(width: widget.size, height: widget.size);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final image = data.frames[_frameIndex(data)];
        final dst = _fitRect(
          Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          widget.size,
        );
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _EmojiPainter(image, Rect.fromLTWH(0, 0,
              image.width.toDouble(), image.height.toDouble()), dst),
        );
      },
    );
  }
}
