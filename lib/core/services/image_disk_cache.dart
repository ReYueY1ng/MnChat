/// 网络图片的**磁盘 + 内存**两级缓存。
///
/// 背景：项目此前完全依赖 `Image.network` —— Flutter 的 `ImageCache` 只在内存、
/// 进程结束即丢，于是**每次冷启动都要把所有头像重新下载一遍**。
///
/// 设计：
/// - 内存层：URL → 已下载字节的 LRU，按 [ImageCacheKind] 分别计数；
/// - 磁盘层：`<应用 cache 目录>/image_cache/<用途>/<url 的 sha1>`，按 mtime 做
///   LRU，各自超过 [ImageCacheKind.capBytes] 时淘汰到 75% 以下；
///   **放在 cache 目录**（`getApplicationCacheDirectory`）而不是 files 目录 ——
///   这样系统在存储紧张时可以回收，也不会占用用户的「应用数据」额度。
/// - 未命中则用 dio 下载（http 明文已在清单里允许），成功后回写磁盘；
/// - **任何失败都不抛给 UI**：读/写缓存失败只记 warn 并退回网络；网络失败则把
///   异常交给调用方的 `errorBuilder` 处理。
///
/// 为什么不用 `cached_network_image`：它依赖 `flutter_cache_manager` → `sqflite`，
/// 而 sqflite 没有 Linux 桌面实现 —— 本项目是手机 + Linux 桌面双端，会直接砸掉
/// 桌面端。这里只用 `dart:io` + 已有依赖（dio / crypto / path_provider），
/// 全平台可用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

/// 图片用途：决定磁盘/内存的**独立配额**。
///
/// 头像小而高频复用、动态图大而看过即弃 —— 混在一个 LRU 里会让「刷一会儿动态」
/// 把头像全挤掉。分目录 + 各自独立限额后，两者**永不互相淘汰**。
enum ImageCacheKind {
  /// 头像/头像框等：小、复用极高，独立限额保护起来。
  avatar,

  /// 动态/邮件/大图预览等：大、一次性，自己限额自己淘汰。
  feed;

  /// 磁盘配额（字节）。头像给得小但受保护；feed 给大但自限。
  int get capBytes => switch (this) {
    ImageCacheKind.avatar => 32 * 1024 * 1024,
    ImageCacheKind.feed => 192 * 1024 * 1024,
  };

  /// 磁盘子目录名。
  String get dirName => name;

  /// 内存层条数：头像需要「秒出」，给得多；feed 给得少。
  int get memoryMaxEntries => switch (this) {
    ImageCacheKind.avatar => 200,
    ImageCacheKind.feed => 60,
  };
}

/// 网络图片磁盘缓存（进程内单例）。
class ImageDiskCache {
  static const String _tag = 'imageCache';

  /// 内存层最多缓存的图片数。
  static const int memoryMaxEntries = 80;

  /// 淘汰后回到的比例（避免每次写入都触发一轮淘汰）。
  static const double _evictTarget = 0.75;

  static final ImageDiskCache instance = ImageDiskCache._();

  ImageDiskCache._();

  /// 内存层：用途 → (URL → 字节)。Dart 的 map 字面量本身即插入有序
  /// （`LinkedHashMap`），访问后重插实现 LRU。
  final Map<ImageCacheKind, Map<String, Uint8List>> _memory = {
    for (final k in ImageCacheKind.values) k: <String, Uint8List>{},
  };

  /// 用途 → 磁盘目录（null 表示该用途不落盘）。
  final Map<ImageCacheKind, Directory?> _dirs = {};

  /// 是否已尝试解析目录（避免反复 stat）。
  bool _dirResolved = false;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
    ),
  );

  /// 读取图片字节：内存 → 磁盘 → 网络（并回写）。
  ///
  /// 缓存侧失败一律忽略（只记 warn 并继续走网络）；网络失败则抛出，交给调用方的
  /// `errorBuilder` 处理。
  Future<Uint8List> load(String url, ImageCacheKind kind) async {
    if (url.isEmpty) throw ArgumentError('空的图片地址');
    final cached = _fromMemory(url, kind);
    if (cached != null) return cached;
    final onDisk = await _fromDisk(url, kind);
    if (onDisk != null) {
      _putMemory(url, onDisk, kind);
      return onDisk;
    }
    final resp = await _dio.get<List<int>>(url);
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw StateError('图片下载为空: $url');
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    _putMemory(url, bytes, kind);
    await _writeDisk(url, bytes, kind);
    return bytes;
  }

  /// 某用途（或全部）的磁盘占用（字节）。诊断/设置页用。
  Future<int> diskSize([ImageCacheKind? kind]) async {
    final kinds = kind == null ? ImageCacheKind.values : [kind];
    var total = 0;
    for (final k in kinds) {
      final dir = await _cacheDir(k);
      if (dir == null) continue;
      try {
        await for (final e in dir.list()) {
          if (e is File) total += await e.length();
        }
      } catch (e) {
        log.warn('统计图片缓存大小失败: $e', tag: _tag);
      }
    }
    return total;
  }

  /// 清空磁盘与内存缓存（全部用途）。
  Future<void> clear() async {
    for (final list in _memory.values) {
      list.clear();
    }
    for (final k in ImageCacheKind.values) {
      final dir = await _cacheDir(k);
      if (dir == null) continue;
      try {
        await for (final e in dir.list()) {
          if (e is File) await e.delete();
        }
      } catch (e) {
        log.warn('清空图片缓存失败: $e', tag: _tag);
      }
    }
  }

  // ── 内存层 ──────────────────────────────────────────────────────────

  Uint8List? _fromMemory(String url, ImageCacheKind kind) {
    final list = _memory[kind]!;
    final hit = list.remove(url);
    if (hit != null) list[url] = hit; // 重新插到尾部 = 最近使用
    return hit;
  }

  void _putMemory(String url, Uint8List bytes, ImageCacheKind kind) {
    final list = _memory[kind]!;
    list.remove(url);
    list[url] = bytes;
    while (list.length > kind.memoryMaxEntries) {
      list.remove(list.keys.first);
    }
  }

  // ── 磁盘层 ──────────────────────────────────────────────────────────

  /// 某用途的缓存目录：应用 **cache 目录**下的 `image_cache/<用途>`。
  ///
  /// 用 cache 目录而不是 files 目录：系统存储紧张时可自行回收，也不占「应用数据」
  /// 额度；临时目录作兜底，都拿不到就退化为不落盘（只走内存 + 网络）。
  Future<Directory?> _cacheDir(ImageCacheKind kind) async {
    if (_dirResolved) return _dirs[kind];
    _dirResolved = true;
    try {
      Directory base;
      try {
        base = await getApplicationCacheDirectory();
      } catch (_) {
        base = await getTemporaryDirectory();
      }
      for (final k in ImageCacheKind.values) {
        final dir = Directory('${base.path}/image_cache/${k.dirName}');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _dirs[k] = dir;
      }
    } catch (e) {
      log.warn('无法创建图片缓存目录，退化为不落盘: $e', tag: _tag);
      for (final k in ImageCacheKind.values) {
        _dirs[k] = null;
      }
    }
    return _dirs[kind];
  }

  /// URL → 文件名（sha1，跨进程稳定；不同 URL 不会碰撞）。
  String _fileNameOf(String url) {
    final digest = sha1.convert(utf8.encode(url));
    return digest.toString();
  }

  Future<Uint8List?> _fromDisk(String url, ImageCacheKind kind) async {
    final dir = await _cacheDir(kind);
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/${_fileNameOf(url)}');
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      // 触碰 mtime，作为 LRU 的「最近使用」标记
      unawaited(file.setLastModified(DateTime.now()).catchError((_) => file));
      return bytes;
    } catch (e) {
      log.warn('读取图片缓存失败: $e', tag: _tag);
      return null;
    }
  }

  Future<void> _writeDisk(
    String url,
    Uint8List bytes,
    ImageCacheKind kind,
  ) async {
    final dir = await _cacheDir(kind);
    if (dir == null) return;
    try {
      final file = File('${dir.path}/${_fileNameOf(url)}');
      await file.writeAsBytes(bytes, flush: false);
      await _evictIfNeeded(dir, kind);
    } catch (e) {
      log.warn('写入图片缓存失败: $e', tag: _tag);
    }
  }

  /// 该用途超过配额时，按 mtime 由旧到新删除，直到降到 [_evictTarget]。
  ///
  /// **只在本用途目录内淘汰** —— 所以动态图无论刷多少都动不到头像缓存。
  Future<void> _evictIfNeeded(Directory dir, ImageCacheKind kind) async {
    try {
      final entries = <(File, int, DateTime)>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final len = await e.length();
        total += len;
        entries.add((e, len, await e.lastModified()));
      }
      if (total <= kind.capBytes) return;
      final target = (kind.capBytes * _evictTarget).round();
      entries.sort((a, b) => a.$3.compareTo(b.$3)); // 旧的在前
      for (final (file, len, _) in entries) {
        if (total <= target) break;
        try {
          await file.delete();
          total -= len;
        } catch (_) {
          // 单个文件删不掉就跳过
        }
      }
    } catch (e) {
      log.warn('图片缓存淘汰失败: $e', tag: _tag);
    }
  }
}

/// `NetworkImage` 的磁盘缓存替代品。
///
/// 用法与 [NetworkImage] 完全一致：`Image(image: CachedNetworkImageProvider(url))`，
/// 调用点的 `loadingBuilder` / `errorBuilder` / `frameBuilder` 语义不变。
class CachedNetworkImageProvider
    extends ImageProvider<CachedNetworkImageProvider> {
  const CachedNetworkImageProvider(
    this.url, {
    this.scale = 1.0,
    this.kind = ImageCacheKind.feed,
  });

  final String url;
  final double scale;

  /// 用途：**头像务必传 [ImageCacheKind.avatar]**，这样它走独立配额，
  /// 不会被动态/大图的滚动把缓存挤掉。
  final ImageCacheKind kind;

  @override
  Future<CachedNetworkImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedNetworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(key, decode),
      scale: key.scale,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadCodec(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await ImageDiskCache.instance.load(key.url, key.kind);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImageProvider &&
      other.url == url &&
      other.scale == scale &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(url, scale, kind);

  @override
  String toString() =>
      'CachedNetworkImageProvider("$url", scale: $scale, kind: ${kind.name})';
}
