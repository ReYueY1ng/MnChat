/// 表情仓库 —— 拉配置 / 已拥有列表 / 素材下载解包与本地缓存。
///
/// 数据来源（对齐反编译 emojisysservice.lua / emojisysdatamanager.lua）：
/// - 包配置：visual-cfg `emoji_system`（`miniw/ma/configIndex.lua` → `<md5>.lua`，
///   与称号/伙伴同一套机制），字段 `emojis[{ID,Type,GetType,emoji_cfgs_url,
///   emoji_files_url}]`；
/// - 已拥有 + 展示顺序：`/miniw/emoji/act/get_user_emoji_data` →
///   `{own_list:[{id:包ID}...], seq:[包ID...]}`（`ReqMyEmojiDatas` 解析逻辑）；
/// - 包内图列表：下载 `emoji_cfgs_url` 得到的 `infos.list`（JSON）；
/// - 图素材：`emoji_files_url[图ID]` 是**压缩包**，解包后得到 `<icon>.png`
///   （`EmojiDownload`：下载 → unzip → 落盘，见 emojisysdatamanager.lua:1568）。
///
/// 1/3 号旧包用内置定义（`kBuiltinPackPics`）渲染，不需要网络与下载。
/// 所有网络/下载失败都**不抛异常**：包级失败跳过该包，图级失败返回 null，
/// UI 侧自行回退（图集 / Unicode / 占位）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/emoji_catalog.dart';
import '../net/config.dart' show kDefaultBase;
import '../net/http_factory.dart' show createDio;
import '../protocol/lua_table.dart' show decodeHttpResponse;
import '../utils/log.dart';
import 'config_text_cache.dart';
import 'miniw_extra.dart' show EmojiClient;
import 'title_config.dart' show parseConfigIndex;

/// 本模块日志标签。
const String _logTag = 'EmojiStore';

/// 一个「包 + 包内图」的展示单元。
class EmojiPackView {
  final EmojiPack pack;
  final List<EmojiPic> pics;

  const EmojiPackView({required this.pack, required this.pics});

  /// 旧包（1/3）：不下载，走本地图集 / Unicode。
  bool get isLegacy => pack.isLegacy;

  /// 包内图是否可以按需下载（远程包且有素材地址）。
  bool get downloadable =>
      !isLegacy && pack.filesUrl.isNotEmpty;
}

/// 表情仓库（进程内缓存包列表）。
class EmojiStore {
  EmojiStore({
    required EmojiClient client,
    Dio? dio,
    String? baseUrl,
    String? cacheRoot,
  })  :
        // ignore: prefer_initializing_formals
        _client = client,
        _dio = dio ?? createDio(),
        _baseUrl = baseUrl ?? kDefaultBase,
        _cacheRootOverride = cacheRoot;

  final EmojiClient _client;
  final Dio _dio;
  final String _baseUrl;
  final String? _cacheRootOverride;

  List<EmojiPackView>? _cached;

  String _base() =>
      _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;

  /// 全部表情包（配置里能拿到的，含未拥有）+ 是否已拥有。
  ///
  /// 面板底部那一排要显示"没买到的包"（游戏里给它们挂「会员」角标），
  /// 所以这里不按已拥有过滤；拉配置失败时回退内置包。
  Future<List<(EmojiPack, bool)>> loadAllPacks() async {
    try {
      final remote = <String, EmojiPack>{
        for (final p in await _fetchRemotePacks()) p.id: p,
      };
      for (final p in kBuiltinEmojiPacks) {
        remote[p.id] = p;
      }
      final owned = (await _fetchOwned()).$1.toSet();
      final builtinIds = kBuiltinEmojiPacks.map((p) => p.id).toSet();
      final out = <(EmojiPack, bool)>[];
      // 已拥有的排前面（保持后端给的顺序），其余按 id。
      final ownedIds = <String>[
        ...owned,
        ...remote.keys.where(
          (id) => !owned.contains(id) && builtinIds.contains(id),
        ),
        ...remote.keys.where(
          (id) => !owned.contains(id) && !builtinIds.contains(id),
        ),
      ];
      for (final id in ownedIds) {
        final pack = remote[id];
        if (pack == null) continue;
        out.add((pack, owned.contains(id) || builtinIds.contains(id)));
      }
      return out;
    } catch (e) {
      log.warn('表情包列表（全部）拉取失败: $e', tag: _logTag);
      return [for (final p in kBuiltinEmojiPacks) (p, true)];
    }
  }

  /// 拉取「我的表情」（包 + 图），进程内缓存。失败时**回退内置包**（1/3）。
  Future<List<EmojiPackView>> load({bool force = false}) async {
    if (!force && _cached != null) return _cached!;

    final remote = <String, EmojiPack>{
      for (final p in await _fetchRemotePacks()) p.id: p,
    };
    // 内置 1/3 号包**覆盖**远端同 ID 项：远端那两条不带标题（Name 在另一处），
    // 覆盖后选择器能显示「熊孩子 / 花小楼」，且这两个包本来就用本地图集渲染。
    for (final p in kBuiltinEmojiPacks) {
      remote[p.id] = p;
    }

    final owned = await _fetchOwned();
    // 拿不到已拥有信息（未登录/请求失败）→ 至少给内置 1/3 号包，保证面板非空。
    final ids = owned.$1.isNotEmpty
        ? owned.$1
        : kBuiltinEmojiPacks.map((p) => p.id).toList();

    final out = <EmojiPackView>[];
    for (final id in ids) {
      final pack = remote[id] ?? EmojiPack(id: id);
      final pics = kBuiltinPackPics[id] ?? await _fetchPackPics(pack);
      if (pics.isEmpty) continue;
      out.add(EmojiPackView(pack: pack, pics: pics));
    }
    return _cached = out;
  }

  /// 发送用代码（旧包 `#A1xx`，新包 `[mdemo]...[/mdemo]`）。
  String sendCode(EmojiPack pack, EmojiPic pic) => emojiSendCode(pack, pic);

  /// 确保某张图已下载解包，返回本地文件路径；不可用返回 null。
  ///
  /// 同一张图的并发请求会合并；同时最多 [maxConcurrentDownloads] 个下载在跑
  /// （「我的表情」面板打开时会一次性挂载很多格子，不限制会瞬间打满连接）。
  Future<String?> ensurePicFile(EmojiPack pack, EmojiPic pic) {
    if (pack.isLegacy) return Future.value(null);
    // 动态包（Type=2）的素材是 spine（`.atlas`+`.skel`），本客户端渲染不了，
    // 下载下来也用不上 —— 其动画由外部转成 webp 后放进 kEmojiAnimDir，
    // 渲染侧直接按图 ID 取（真实 infos.list 里 ID 与 icon 同名）。
    if (pack.isDynamic) return Future.value(null);
    final key = '${pack.id}:${pic.picId}';
    final inflight = _inflight[key];
    if (inflight != null) return inflight;
    final fut = _ensurePicFileInner(pack, pic).whenComplete(() {
      // 注意：这里必须是**语句块**。写成 `() => _inflight.remove(key)` 会让
      // whenComplete 的返回值变成「正在等待的那个 future」→ 自我等待死锁。
      _inflight.remove(key);
    });
    _inflight[key] = fut;
    return fut;
  }

  Future<String?> _ensurePicFileInner(EmojiPack pack, EmojiPic pic) async {
    final dir = await _packDir(pack.id);
    if (dir == null) return null;

    final fileName =
        pic.iconName.isNotEmpty ? '${pic.iconName}.png' : '${pic.picId}.png';
    final target = File('${dir.path}${Platform.pathSeparator}$fileName');
    if (await target.exists() && await target.length() > 0) return target.path;

    final url = pack.filesUrl[pic.picId];
    if (url == null || url.isEmpty) return null;

    await _acquireDownloadSlot();
    try {
      final resp = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) return null;
      final archive = ZipDecoder().decodeBytes(bytes);
      final hit = _pickEntry(archive, pic);
      if (hit == null) {
        log.warn('emoji zip 内未找到 ${pic.icon}（pack=${pack.id} pic=${pic.picId}）',
            tag: _logTag);
        return null;
      }
      await dir.create(recursive: true);
      await target.writeAsBytes(hit.content, flush: true);
      return target.path;
    } catch (e) {
      log.warn('emoji 下载失败 pack=${pack.id} pic=${pic.picId}: $e', tag: _logTag);
      return null;
    } finally {
      _releaseDownloadSlot();
    }
  }

  /// 同时进行的素材下载上限。
  static const int maxConcurrentDownloads = 4;

  final Map<String, Future<String?>> _inflight = {};
  final List<Completer<void>> _downloadQueue = [];
  int _activeDownloads = 0;

  Future<void> _acquireDownloadSlot() {
    if (_activeDownloads < maxConcurrentDownloads) {
      _activeDownloads++;
      return Future.value();
    }
    final c = Completer<void>();
    _downloadQueue.add(c);
    return c.future;
  }

  void _releaseDownloadSlot() {
    // 有等待者时把名额直接转交（active 不变），否则释放。
    if (_downloadQueue.isNotEmpty) {
      _downloadQueue.removeAt(0).complete();
    } else {
      _activeDownloads--;
    }
  }

  /// 按「包 ID + 图 ID」确保素材就绪（供消息内联渲染调用），不可用返回 null。
  Future<String?> ensurePicByCode(String packId, String picId) async {
    final packs = await load();
    for (final v in packs) {
      if (v.pack.id != packId) continue;
      for (final p in v.pics) {
        if (p.picId == picId) return ensurePicFile(v.pack, p);
      }
    }
    return null;
  }

  /// 在压缩包里挑出目标图标。
  ///
  /// `EmojiDownload` 解包后按 `<icon>.png` 命名读取（`GetEmojiSrc`），故这里
  /// 只在 basename 命中 `<icon>`/`<icon>.png` 时采用（zip 内可能在子目录）。
  /// 只有连 icon 名都没有（协议缺项）时才退化为「第一张图片」——
  /// 否则宁可返回 null 也不要渲染成别的表情。
  ArchiveFile? _pickEntry(Archive archive, EmojiPic pic) {
    final want = pic.icon.isNotEmpty ? pic.icon : '';
    final wantStem = pic.iconName;
    ArchiveFile? firstImage;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final base = f.name.split('/').last;
      if (want.isNotEmpty && base == want) return f;
      if (wantStem.isNotEmpty) {
        final dot = base.lastIndexOf('.');
        final stem = dot > 0 ? base.substring(0, dot) : base;
        if (stem == wantStem) return f;
      }
      if (base.endsWith('.png') || base.endsWith('.altas')) {
        firstImage ??= f;
      }
    }
    return want.isEmpty ? firstImage : null;
  }

  Future<Directory?> _packDir(String packId) async {
    try {
      final root = _cacheRootOverride != null
          ? Directory(_cacheRootOverride)
          : Directory('${(await getApplicationCacheDirectory()).path}'
              '${Platform.pathSeparator}emoji');
      return Directory('${root.path}${Platform.pathSeparator}$packId');
    } catch (e) {
      log.warn('emoji 缓存目录不可用: $e', tag: _logTag);
      return null;
    }
  }

  /// 远端 visual-cfg `emoji_system` → 包列表（失败返回空）。
  Future<List<EmojiPack>> _fetchRemotePacks() async {
    try {
      final index = parseConfigIndex(
        await _getText('${_base()}/miniw/ma/configIndex.lua'),
      );
      final md5 = index['emoji_system'];
      if (md5 == null) return const [];
      final cfg = await _getText('${_base()}/miniw/ma/$md5.lua');
      return parseEmojiSystemConfig(decodeHttpResponse(cfg));
    } catch (e) {
      log.warn('emoji_system 配置拉取失败: $e', tag: _logTag);
      return const [];
    }
  }

  /// 已拥有包 ID（按展示顺序）+ 顺序表。失败返回 (空, 空)。
  Future<(List<String>, List<String>)> _fetchOwned() async {
    try {
      final resp = await _client.userData();
      final own = <String>[];
      final raw = resp['own_list'] ?? resp['data'];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            final id = (e['id'] ?? e['ID'])?.toString() ?? '';
            if (id.isNotEmpty) own.add(id);
          } else if (e != null) {
            final id = e.toString();
            if (id.isNotEmpty) own.add(id);
          }
        }
      }
      final seq = <String>[];
      final rawSeq = resp['seq'];
      if (rawSeq is List) {
        for (final e in rawSeq) {
          final id = e?.toString() ?? '';
          if (id.isNotEmpty) seq.add(id);
        }
      }
      // seq 是用户自定义顺序：先按 seq，再补 own 里剩余的。
      final ordered = <String>[];
      for (final id in seq) {
        if (own.contains(id) && !ordered.contains(id)) ordered.add(id);
      }
      for (final id in own) {
        if (!ordered.contains(id)) ordered.add(id);
      }
      return (ordered, seq);
    } catch (e) {
      log.warn('emoji 已拥有列表拉取失败: $e', tag: _logTag);
      return (<String>[], <String>[]);
    }
  }

  /// 下载并解析某包的 `infos.list` → 包内图列表。
  Future<List<EmojiPic>> _fetchPackPics(EmojiPack pack) async {
    if (pack.cfgsUrl.isEmpty) return const [];
    try {
      final text = await _getText(pack.cfgsUrl);
      return parsePackInfosList(pack.id, decodeHttpResponse(text));
    } catch (e) {
      log.warn('包 ${pack.id} 图列表拉取失败: $e', tag: _logTag);
      return const [];
    }
  }

  Future<String> _getText(String url) async {
    final cached = await ConfigTextCache.instance.get(url);
    if (cached != null) return cached;
    final resp = await _dio.get(url);
    final d = resp.data;
    final text = d is String ? d : jsonEncode(d);
    await ConfigTextCache.instance.put(url, text);
    return text;
  }
}
