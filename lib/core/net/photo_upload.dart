/// 预签名地址的图片直传 —— 对齐真实抓包（2026-10-06，mitmproxy flows）。
///
/// `/miniw/upload/?type=photo&node=&dir=&token=&uin=` 的 v2 协议是**分片
/// multipart**（`MiniHttp.CustomUpload` 为原生实现，Lua 反编译看不到线格式，
/// 这里按抓包逐字节复刻）：
///
/// ```text
/// GET  <pre>&v=2&act=info&fn=<文件 md5>&usize=<总字节>  → "ok,size=-1"
/// POST <pre>&act=upload_begin&ext=<ext>                → "ok"
/// POST <pre>&act=upload_step&ext=<ext>   ×N（每片 128 KiB）→ "ok"
/// POST <pre>&act=upload_end&ext=<ext>                  → "ok:token=<t>&node=<n>&dir=<d>"
/// ```
///
/// 每个分片都是 `multipart/form-data`，字段名 `fileUpload`、filename = 文件
/// md5、part 的 Content-Type = `application/octet-stream`。`upload_end` 的回包
/// 去掉 `ok:` 前缀即 sub_token，随后原样拼进确认接口
/// （`add_posting_pic` / `set_usr_header3` 等）。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../utils/log.dart' show log, redactUrl;

/// 单片字节数（抓包实测每片 131072 = 128 KiB，multipart 开销另计）。
const int kUploadChunkSize = 128 * 1024;

/// 直传标签（日志用）。
const String _logTag = 'Upload';

/// 把 [bytes] 分片直传到预签名地址 [presignedUrl]，成功返回 sub_token。
///
/// [fileMd5] 是整份文件的 md5（32 位十六进制），既做 `act=info` 的 `fn`，
/// 也做每个分片 part 的 filename —— 服务端据此把分片拼成同一份文件。
/// 任一步失败 / 回包不以 `ok` 开头 → null（绝不抛，由调用方降级）。
Future<String?> uploadPresignedFile(
  Dio dio,
  String presignedUrl,
  List<int> bytes, {
  required String fileMd5,
  required String ext,
}) async {
  if (bytes.isEmpty) return null;
  final sep = presignedUrl.contains('?') ? '&' : '?';
  final base = '$presignedUrl${sep}v=2';
  final plain = Options(responseType: ResponseType.plain);

  // 1) info：声明文件名与总大小（服务端据此给出续传起点）。
  try {
    final info = await dio.get<String>(
      '$base&act=info&fn=$fileMd5&usize=${bytes.length}',
      options: plain,
    );
    final body = '${info.data}'.trim();
    if (!body.startsWith('ok')) {
      log.warn('upload info 失败: $body', tag: _logTag);
      return null;
    }
  } on DioException catch (e) {
    log.warn('upload info 异常: ${e.message}（${redactUrl(presignedUrl)}）',
        tag: _logTag);
    return null;
  }

  // 2) 分片：首片 begin、末片 end、中间 step；单片文件直接用 end。
  final total = bytes.length;
  var offset = 0;
  var index = 0;
  String? token;
  while (offset < total) {
    final end = offset + kUploadChunkSize < total
        ? offset + kUploadChunkSize
        : total;
    final isLast = end >= total;
    final act = index == 0 && !isLast
        ? 'upload_begin'
        : (isLast ? 'upload_end' : 'upload_step');
    final form = FormData.fromMap({
      'fileUpload': MultipartFile.fromBytes(
        Uint8List.fromList(bytes.sublist(offset, end)),
        filename: fileMd5,
        contentType: DioMediaType('application', 'octet-stream'),
      ),
    });
    try {
      final resp = await dio.post<String>(
        '$base&act=$act&ext=$ext',
        data: form,
        options: plain,
      );
      final body = '${resp.data}'.trim();
      if (!body.startsWith('ok')) {
        log.warn('upload $act 失败: $body', tag: _logTag);
        return null;
      }
      if (act == 'upload_end') {
        final t = body.startsWith('ok:') ? body.substring(3).trim() : '';
        token = t.isEmpty ? null : t;
      }
    } on DioException catch (e) {
      log.warn('upload $act 异常: ${e.message}', tag: _logTag);
      return null;
    }
    offset = end;
    index++;
  }
  return token;
}
