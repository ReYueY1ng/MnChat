/// 剪贴板文本 → 本机图片文件路径。
///
/// 桌面文件管理器复制图片文件时，剪贴板里通常是若干行路径或 `file://` URI；
/// 这里只做纯解析与存在性过滤（IO 由调用方以 [exists] 注入），便于单测。
library;

/// 认可的图片扩展名（小写）。
const Set<String> kClipboardImageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.bmp',
  '.heic',
};

/// 路径是否以图片扩展名结尾。
bool isImagePath(String path) {
  final lower = path.toLowerCase();
  return kClipboardImageExtensions.any(lower.endsWith);
}

/// 拖拽进来的文件里第一个图片路径；没有返回 null。
String? firstImagePath(Iterable<String> paths) {
  for (final p in paths) {
    if (isImagePath(p)) return p;
  }
  return null;
}

/// 从剪贴板文本提取本机存在的图片路径（去重、最多 [max] 条）。
///
/// - 支持每行一个路径、带引号的路径、`file://` URI；
/// - 非图片扩展名、不存在的文件一律跳过，绝不抛。
List<String> imagePathsFromClipboard(
  String text, {
  required bool Function(String path) exists,
  int max = 9,
}) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    var s = raw.trim();
    if (s.isEmpty) continue;
    if (s.length > 1 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.startsWith('file://')) {
      final uri = Uri.tryParse(s);
      if (uri == null) continue;
      try {
        s = uri.toFilePath();
      } catch (_) {
        continue;
      }
    }
    final lower = s.toLowerCase();
    if (!isImagePath(lower)) continue;
    if (!exists(s)) continue;
    if (!out.contains(s)) out.add(s);
    if (out.length >= max) break;
  }
  return out;
}
