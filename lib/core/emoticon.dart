import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'chat_emoji.dart' show emojiRepr;

/// 游戏 emoji 贴图（TexturePacker 图集 emoticon.png + emoticon.xml 坐标）。
/// 把 `#A1xx` 代码渲染成游戏真实图标：code → sprite 名 → 贴图矩形。

const String kEmoticonAsset = 'assets/emoticon/emoticon.webp';

/// code → sprite 名（对齐 chatconfig.lua + emoticon.xml）。
const Map<String, String> kCodeToSprite = {
  '#A101': 'xieyanxiao',
  '#A102': 'baimu',
  '#A103': 'shengqi',
  '#A104': 'xianqi',
  '#A105': 'daku',
  '#A106': 'qinqin',
  '#A107': 'xihuan',
  '#A108': 'wabikong',
  '#A109': 'dianzan',
  '#A110': 'haixiu',
  '#A111': 'liulei',
  '#A112': 'keai',
  '#A113': 'shouqibao',
  '#A114': 'kun',
  '#A115': 'jingya',
  '#A116': 'yun',
  '#A117': 'shaojiao',
  '#A118': 'bye',
};

/// sprite 名 → 贴图矩形（x,y 为左上角，TexturePacker 坐标，y 向下；单位 px）。
const Map<String, Rect> kSpriteRect = {
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
};

/// code → 贴图矩形；无法解析返回 null。
Rect? rectForCode(String code) {
  final sprite = kCodeToSprite[code];
  if (sprite == null) return null;
  return kSpriteRect[sprite];
}

/// 渲染一个游戏表情帧。
class EmoticonImage extends StatefulWidget {
  final String code;
  final double size;

  const EmoticonImage({super.key, required this.code, this.size = 24});

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
    final rect = rectForCode(widget.code);
    final size = widget.size;
    if (img == null || rect == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text(emojiRepr(widget.code), style: TextStyle(fontSize: size * 0.8))),
      );
    }
    final src = Rect.fromLTWH(
      rect.left,
      rect.top,
      rect.width,
      rect.height,
    );
    return CustomPaint(
      size: Size.square(size),
      painter: _EmojiPainter(img, src),
    );
  }
}

class _EmojiPainter extends CustomPainter {
  final ui.Image image;
  final Rect src;

  _EmojiPainter(this.image, this.src);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _EmojiPainter old) =>
      old.image != image || old.src != src;
}
