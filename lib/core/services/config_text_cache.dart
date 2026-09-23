/// 游戏配置文本的磁盘缓存（`miniw/ma/configIndex.lua` 与 `<md5>.lua`）。
///
/// 为什么可以**永久缓存、不需要任何失效策略**：配置文件名就是内容的 md5 ——
/// 内容一变文件名就变，所以同一个 URL 的正文永不改变（与 `cfgdownloadmgr` 一致）。
///
/// 收益：
/// - 冷启动不再重复拉配置（关系等级阈值、称号目录）；
/// - **离线时**仍能画出亲密度进度条、显示称号名（原先直接退化成空/无）。
///
/// 落点：`<应用支持目录>/cfg_cache/<url 的 sha1>.txt`。这里用**支持目录**而不是
/// cache 目录 —— 配置体积极小、且是「希望长期保留」的数据，不该被系统随手回收
/// （图片缓存才放 cache 目录）。
///
/// 读写失败只记 warn 并退回网络：缓存本身绝不能影响功能。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/log.dart';

/// 配置文本磁盘缓存（进程内单例）。
class ConfigTextCache {
  static const String _tag = 'cfgCache';

  static final ConfigTextCache instance = ConfigTextCache._();

  ConfigTextCache._();

  /// 进程内层：URL → 文本（避免同一次会话反复读盘）。
  final Map<String, String> _memory = <String, String>{};

  Directory? _dir;
  bool _resolved = false;

  /// 读取缓存；未命中返回 null（**不抛异常**）。
  Future<String?> get(String url) async {
    final hit = _memory[url];
    if (hit != null) return hit;
    final dir = await _cacheDir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}/${_nameOf(url)}');
      if (!file.existsSync()) return null;
      final text = await file.readAsString();
      if (text.isEmpty) return null;
      _memory[url] = text;
      return text;
    } catch (e) {
      log.warn('读取配置缓存失败: $e', tag: _tag);
      return null;
    }
  }

  /// 写入缓存（失败忽略）。
  Future<void> put(String url, String text) async {
    if (text.isEmpty) return;
    _memory[url] = text;
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      await File('${dir.path}/${_nameOf(url)}').writeAsString(text);
    } catch (e) {
      log.warn('写入配置缓存失败: $e', tag: _tag);
    }
  }

  /// 清空缓存（内存 + 磁盘）。
  Future<void> clear() async {
    _memory.clear();
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
    } catch (e) {
      log.warn('清空配置缓存失败: $e', tag: _tag);
    }
  }

  /// 缓存目录；拿不到就退化为「不落盘」（只走网络）。
  Future<Directory?> _cacheDir() async {
    if (_resolved) return _dir;
    _resolved = true;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/cfg_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
    } catch (e) {
      log.warn('无法创建配置缓存目录，退化为不落盘: $e', tag: _tag);
      _dir = null;
    }
    return _dir;
  }

  /// URL → 文件名（sha1，跨进程稳定）。
  String _nameOf(String url) => sha1.convert(utf8.encode(url)).toString();
}
