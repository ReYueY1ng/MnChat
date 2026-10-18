/// 聊天发图：上传链路 + 「图片」分享卡编码。
///
/// 线上形状对齐 [ChatService.sendDynamicsShare]（`msgtype=4` 分享类消息 +
/// `extend_data = url_encode(base64(JSON))`），`shareType` 取
/// [ShareType.customPic]（22）—— 游戏客户端与 MNChat 都能渲染成图片卡片。
///
/// 与 DIY 头像的区别：**不需要任何确认接口**。分片直传的 `upload_end` 回包
/// （`photo_upload.dart` 头注释）形如 `ok:token=<t>&node=<n>&dir=<d>`，其中
/// `node`/`dir` 就是 CDN 路径，配合本次上传的 `md5`/`ext` 即可本地拼出图片
/// URL（线上实测形状 `http://map<node>.mini1.cn/map/<node>/<dir>/<md5>.<ext>`，
/// 见 dynamics 的 `pic_list[].url`）。所以发图只写「上传」一次，
/// 不碰 `set_usr_header3` / `add_posting_pic` 这类有副作用的确认接口。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../net/http_factory.dart' show createDio;
import '../net/photo_upload.dart' show uploadPresignedFile;
import 'profile.dart' show ProfileClient;
import 'rich_media.dart' show ShareType;

/// `upload_end` 回包（去掉 `ok:` 前缀后）解析出的 CDN 位置。
class PhotoUploadToken {
  /// 原始 token 字段。
  final String token;

  /// CDN 节点号（主机名 `map<node>.mini1.cn`）。
  final String node;

  /// CDN 目录（形如 `20261016`）。
  final String dir;

  const PhotoUploadToken({
    required this.token,
    required this.node,
    required this.dir,
  });
}

/// 解析 `token=<t>&node=<n>&dir=<d>`；三项缺一 → null（绝不抛）。
PhotoUploadToken? parsePhotoUploadToken(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  Map<String, String> q;
  try {
    q = Uri.splitQueryString(text);
  } on FormatException {
    return null;
  }
  final token = (q['token'] ?? '').trim();
  final node = (q['node'] ?? '').trim();
  final dir = (q['dir'] ?? '').trim();
  if (token.isEmpty || node.isEmpty || dir.isEmpty) return null;
  return PhotoUploadToken(token: token, node: node, dir: dir);
}

/// 拼图片 CDN URL。`ext` 不带点，缺省 `png`。
String buildPhotoCdnUrl({
  required String node,
  required String dir,
  required String md5,
  String ext = 'png',
}) =>
    'http://map$node.mini1.cn/map/$node/$dir/$md5.$ext';

/// 从文件名取扩展名（小写、不带点）；无扩展名 / 不像扩展名 → [fallback]。
String mediaExtensionOf(String fileName, {String fallback = 'png'}) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return fallback;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : fallback;
}

/// 非图片媒体（语音）上传时套用的扩展名。
///
/// 存储 CDN **只发布图片扩展名**（2026-10-17 七臂实测，同一账号同一接口、同一份
/// 64078 字节音频：`png`/`jpg`/`webp` 取回 **200**，`m4a`/`mp4`/`ogg`/`amr` 均 **404**）。
/// 而播放器是按**内容**认容器的（ffmpeg 嗅探：把 WAV 改名 `.png` 后 `ffprobe` 仍报
/// `format_name=wav`、播放器照播 —— 按内容认容器，与扩展名无关），所以语音音频套 `.png` 上传、URL 放进信封，
/// 対端下载后仍能正常播。官方客户端看不到这个 URL（它只读正文），不受影响。
const String kVoiceCarrierExt = 'png';

/// 编码「图片」分享卡的 `extend_data`。
///
/// 字段与 [ChatService.sendDynamicsShare] 一致（`nickname`/`shareType`/
/// `content`/`pic_list`/`bubble`），图片地址放在 `url` 与 `pic_list[0].url`
/// （两者都在 [ChatService] 的解析里被读）。
String buildImageShareExtend({
  required String nickname,
  required String url,
  String content = '',
}) {
  final tShare = <String, Object?>{
    'nickname': nickname,
    'shareType': ShareType.customPic,
    'url': url,
    'pic_list': <Object?>[
      <String, Object?>{'url': url},
    ],
    'content': Uri.encodeQueryComponent(content),
    'bubble': 0,
  };
  return Uri.encodeQueryComponent(
    base64Encode(utf8.encode(jsonEncode(tShare))),
  );
}

/// 上传任意聊天媒体（图片 / 语音…），成功返回可直接放进分享卡或信封的 CDN URL。
///
/// 步骤：`upload_pre_photo` 取预签名地址 → 分片直传 → 本地拼 URL。
/// 扩展名取 [fileName] 的后缀（不像扩展名时用 [defaultExt]）——服务端按
/// `upload_end` 的 `ext` 回包与文件名共用同一份 md5 索引，所以传输类型不吃紧。
/// 任一步失败 / 回包不合法 → null（由调用方提示，绝不抛）。
Future<String?> uploadChatMedia(
  ProfileClient profile, {
  required List<int> bytes,
  required String fileName,
  String defaultExt = 'png',
  String? forceExt,
}) async {
  if (bytes.isEmpty) return null;
  final uploadUrl = await profile.uploadPrePhoto();
  if (uploadUrl == null) return null;
  final ext = forceExt ?? mediaExtensionOf(fileName, fallback: defaultExt);
  final md5 = crypto.md5.convert(bytes).toString();
  final raw = await uploadPresignedFile(
    createDio(),
    uploadUrl,
    bytes,
    fileMd5: md5,
    ext: ext,
  );
  if (raw == null) return null;
  final token = parsePhotoUploadToken(raw);
  if (token == null) return null;
  return buildPhotoCdnUrl(
    node: token.node,
    dir: token.dir,
    md5: md5,
    ext: ext,
  );
}

/// 上传一张聊天图片（[uploadChatMedia] 的图片缺省扩展名封装）。
Future<String?> uploadChatImage(
  ProfileClient profile, {
  required List<int> bytes,
  required String fileName,
}) =>
    uploadChatMedia(profile, bytes: bytes, fileName: fileName);
