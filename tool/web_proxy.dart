/// MnChat Web 本地开发 CORS 代理服务器。
///
/// 背景：迷你世界 HTTP API（wskacchm/shequ/chatpush.mini1.cn）未返回
/// `Access-Control-Allow-Origin`，浏览器同源策略会阻止 Web 前端直连。
///
/// 本服务器把静态 `build/web` 与 4 个后端代理放到**同一 origin**，浏览器请求
/// `/mw/<backend>/*` 走同源转发 → 完全不触发 CORS。
///
/// 用法：
///   dart run tool/web_proxy.dart [--port=8080] [--dir=build/web]
///
/// 路由映射：
///   /mw/login/*      -> https://wskacchm.mini1.cn:14100/*
///   /mw/wsconfig/*   -> http://wskacchm.mini1.cn:4000/*
///   /mw/shequ/*      -> https://shequ.mini1.cn:8081/*
///   /mw/chatpush/*   -> https://chatpush.mini1.cn:19602/*
library;

import 'dart:async';
import 'dart:io';

final Map<String, String> _routes = {
  '/mw/login': 'https://wskacchm.mini1.cn:14100',
  '/mw/wsconfig': 'http://wskacchm.mini1.cn:4000',
  '/mw/shequ': 'https://shequ.mini1.cn:8081',
  '/mw/chatpush': 'https://chatpush.mini1.cn:19602',
};

Future<void> main(List<String> args) async {
  final port = _arg(args, 'port') ?? _arg(args, 'p') ?? '8080';
  final webDir = _arg(args, 'dir') ?? 'build/web';

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, int.parse(port));
  stdout.writeln('[proxy] MnChat Web dev proxy @ http://localhost:$port');
  stdout.writeln('[proxy]   static root: $webDir');
  stdout.writeln('[proxy]   routes: ${_routes.keys.join('  ')}');

  await for (final req in server) {
    unawaited(_handle(req, client, webDir));
  }
}

Future<void> _handle(HttpRequest req, HttpClient client, String webDir) async {
  final path = req.uri.path;

  String? route;
  String? rest;
  for (final r in _routes.keys) {
    if (path == r || path.startsWith('$r/')) {
      route = r;
      rest = path.substring(r.length);
      break;
    }
  }

  if (route == null) {
    await _serveStatic(req, webDir);
    return;
  }

  final targetBase = _routes[route]!;
  final targetPath = (rest == null || rest.isEmpty) ? '/' : rest;
  final target = Uri.parse('$targetBase$targetPath')
      .replace(query: req.uri.query);
  await _forward(req, client, target);
}

Future<void> _forward(HttpRequest req, HttpClient client, Uri target) async {
  try {
    final body = await _readBody(req);
    final out = await client.openUrl(req.method, target);

    req.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'host' ||
          lower == 'content-length' ||
          lower == 'connection' ||
          lower == 'accept-encoding') {
        return;
      }
      out.headers.set(name, values);
    });

    if (body.isNotEmpty) {
      out.headers.contentLength = body.length;
      out.add(body);
    }

    final resp = await out.close();
    req.response.statusCode = resp.statusCode;
    resp.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'transfer-encoding' || lower == 'connection') return;
      // 同源后无需 CORS 头；若仍被下发也无害。
      req.response.headers.set(name, values);
    });
    await req.response.addStream(resp);
    await req.response.close();
  } catch (e) {
    req.response.statusCode = HttpStatus.badGateway;
    req.response.write('[proxy] error forwarding ${req.method} $target: $e');
    await req.response.close();
  }
}

Future<List<int>> _readBody(HttpRequest req) async {
  final bytes = <int>[];
  await for (final chunk in req) {
    bytes.addAll(chunk);
  }
  return bytes;
}

Future<void> _serveStatic(HttpRequest req, String webDir) async {
  var path = req.uri.path;
  if (path == '/') path = '/index.html';

  // 防目录穿越
  final clean = path.split('/').where((s) => s.isNotEmpty).join('/');
  final file = File('$webDir/$clean');

  if (!file.existsSync()) {
    // SPA fallback → index.html
    final idx = File('$webDir/index.html');
    if (idx.existsSync()) {
      await _sendFile(req.response, idx, 'text/html');
      return;
    }
    req.response.statusCode = 404;
    req.response.write('not found');
    await req.response.close();
    return;
  }

  await _sendFile(req.response, file, _mime(file.path));
}

Future<void> _sendFile(HttpResponse resp, File f, String mime) async {
  resp.headers.contentType = ContentType.parse(mime);
  resp.headers.contentLength = await f.length();
  await resp.addStream(f.openRead());
  await resp.close();
}

String _mime(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.html')) return 'text/html';
  if (p.endsWith('.js')) return 'application/javascript';
  if (p.endsWith('.css')) return 'text/css';
  if (p.endsWith('.wasm')) return 'application/wasm';
  if (p.endsWith('.json')) return 'application/json';
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.svg')) return 'image/svg+xml';
  if (p.endsWith('.ico')) return 'image/x-icon';
  if (p.endsWith('.ttf')) return 'font/ttf';
  if (p.endsWith('.otf')) return 'font/otf';
  if (p.endsWith('.json')) return 'application/json';
  return 'application/octet-stream';
}

String? _arg(List<String> args, String name) {
  final prefix = '--$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}
