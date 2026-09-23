/// 网络图片的**磁盘 + 内存**两级缓存。
///
/// 背景：项目此前完全依赖 `Image.network` —— Flutter 的 `ImageCache` 只在内存、
/// 进程结束即丢，于是**每次冷启动都要把所有头像重新下载一遍**。
///
/// 设计：
/// - 内存层：URL → 已下载字节的 LRU（[memoryMaxEntries] 条），命中直接解码；
/// - 磁盘层：`<应用支持目录>/image_cache/<url 的 sha1>`，按 mtime 做 LRU，
///   总量超过 [diskMaxBytes] 时淘汰到 75% 以下；
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
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

/// 网络图片磁盘缓存（进程内单例）。
class ImageDiskCache {
  static const String _tag = 'imageCache';

  /// 内存层最多缓存的图片数。
  static const int memoryMaxEntries = 80;

  /// 磁盘层容量上限（字节）。
  static const int diskMaxBytes = 64 * 1024 * 1024;

  /// 淘汰后回到的比例（避免每次写入都触发一轮淘汰）。
  static const double _evictTarget = 0.75;

  static final ImageDiskCache instance = ImageDiskCache._();

  ImageDiskCache._();

  /// 内存层：URL → 字节。`LinkedHashMap` 保插入序，访问后重插实现 LRU。
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();

  Directory? _dir;

  /// 磁盘目录是否已尝试初始化（避免反复 stat）。
  bool _dirResolved = false;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
    ),
  );

  /// 读取图片字节：内存 → 磁盘 → 网络（并回写）。**不抛异常**（网络失败会抛给
  /// 调用方以便 errorBuilder 生效，缓存侧失败一律忽略）。
  Future<Uint8List> load(String url) async {
    if (url.isEmpty) throw ArgumentError('空的图片地址');
    final cached = _fromMemory(url);
    if (cached != null) return cached;
    final onDisk = await _fromDisk(url);
    if (onDisk != null) {
      _putMemory(url, onDisk);
      return onDisk;
    }
    final resp = await _dio.get<List<int>>(url);
    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw StateError('图片下载为空: $url');
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    _putMemory(url, bytes);
    await _writeDisk(url, bytes);
    return bytes;
  }

  /// 当前磁盘占用（字节）。UI/诊断用。
  Future<int> diskSize() async {
    final dir = await _cacheDir();
    if (dir == null) return 0;
    var total = 0;
    try {
      await for (final e in dir.list()) {
        if (e is File) total += await e.length();
      }
    } catch (e) {
      log.warn('统计图片缓存大小失败: $e', tag: _tag);
    }
    return total;
  }

  /// 清空磁盘与内存缓存。
  Future<void> clear() async {
    _memory.clear();
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
    } catch (e) {
      log.warn('清空图片缓存失败: $e', tag: _tag);
    }
  }

  // ── 内存层 ──────────────────────────────────────────────────────────

  Uint8List? _fromMemory(String url) {
    final hit = _memory.remove(url);
    if (hit != null) _memory[url] = hit; // 重新插到尾部 = 最近使用
    return hit;
  }

  void _putMemory(String url, Uint8List bytes) {
    _memory.remove(url);
    _memory[url] = bytes;
    while (_memory.length > memoryMaxEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  // ── 磁盘层 ──────────────────────────────────────────────────────────

  /// 缓存目录：优先应用支持目录，其次临时目录；都拿不到就退化为不落盘。
  Future<Directory?> _cacheDir() async {
    if (_dirResolved) return _dir;
    _dirResolved = true;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/image_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
    } catch (e) {
      log.warn('无法创建图片缓存目录，退化为不落盘: $e', tag: _tag);
      _dir = null;
    }
    return _dir;
  }

  /// URL → 文件名（sha1，跨进程稳定；不同 URL 不会碰撞）。
  String _fileNameOf(String url) {
    final digest = sha1.convert(utf8.encode(url));
    return digest.toString();
  }

  Future<Uint8List?> _fromDisk(String url) async {
    final dir = await _cacheDir();
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

  Future<void> _writeDisk(String url, Uint8List bytes) async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      final file = File('${dir.path}/${_fileNameOf(url)}');
      await file.writeAsBytes(bytes, flush: false);
      await _evictIfNeeded(dir);
    } catch (e) {
      log.warn('写入图片缓存失败: $e', tag: _tag);
    }
  }

  /// 超过上限时按 mtime 由旧到新删除，直到降到 [_evictTarget]。
  Future<void> _evictIfNeeded(Directory dir) async {
    try {
      final entries = <(File, int, DateTime)>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final len = await e.length();
        total += len;
        entries.add((e, len, await e.lastModified()));
      }
      if (total <= diskMaxBytes) return;
      final target = (diskMaxBytes * _evictTarget).round();
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
  const CachedNetworkImageProvider(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

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
    final bytes = await ImageDiskCache.instance.load(key.url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImageProvider &&
      other.url == url &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'CachedNetworkImageProvider("$url", scale: $scale)';
}
