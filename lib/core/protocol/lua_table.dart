/// Lenient decoder for Mini World HTTP responses.
/// 移植自 MNClient `net/lua_table.py` (294 行，逐行对照)。
///
/// 迷你世界网关端点常返回 **Lua table 字面量** 而非 JSON，例如
/// `{["ret"]=0,["profile"]={["RoleInfo"]={["NickName"]="x"}}}`。
/// 真客户端用 Jeffrey Friedl 的 `JSON.lua`（宽松解码器，接受 Lua 语法）
/// 解析；本文件提供 Dart 等价实现。
///
/// 支持：嵌套 `{...}`、`["key"]=` 和裸 `key=` 字段、隐式索引数组 `{1,2,3}`、
/// 字符串(单/双引号 + Lua 转义)、数字(int/float/hex/指数)、`nil`/`true`/`false`、
/// 尾随逗号。
library;

import 'dart:convert' show jsonDecode;

class LuaTableDecodeError implements Exception {
  final String message;
  LuaTableDecodeError(this.message);
  @override
  String toString() => 'LuaTableDecodeError: $message';
}

final RegExp _identRe = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

const Map<String, String> _escapes = {
  'a': '\u0007',
  'b': '\b',
  'f': '\u000C',
  'n': '\n',
  'r': '\r',
  't': '\t',
  'v': '\u000B',
  '\\': '\\',
  '"': '"',
  "'": "'",
};

class _Parser {
  final String _text;
  int _pos = 0;

  _Parser(this._text);

  bool get _eof => _pos >= _text.length;
  String get _peek => _eof ? '' : _text[_pos];

  void _skipWs() {
    while (!_eof && ' \t\r\n'.contains(_peek)) {
      _pos++;
    }
  }

  void _expect(String ch) {
    _skipWs();
    if (_eof || _peek != ch) {
      throw LuaTableDecodeError("expected '$ch' at offset $_pos: ${_text.substring(0, _text.length > 60 ? 60 : _text.length)}");
    }
    _pos++;
  }

  Object? parseValue() {
    _skipWs();
    if (_eof) throw LuaTableDecodeError('unexpected end of input at $_pos');
    final ch = _peek;
    if (ch == '{') return _parseTable();
    if (ch == '"' || ch == "'") return _parseString();
    // Lua 长括号字符串 `[[...]]` / `[==[...]==]`（emoji_system 配置里用它写中文说明，
    // 例如 `Access = [[花小楼换装舞会活动获得]]`）。
    if (_isLongBracketStart()) return _parseLongBracket();
    if (ch == 'n' && _text.startsWith('nil', _pos)) {
      _pos += 3;
      return null;
    }
    if (ch == 't' && _text.startsWith('true', _pos)) {
      _pos += 4;
      return true;
    }
    if (ch == 'f' && _text.startsWith('false', _pos)) {
      _pos += 5;
      return false;
    }
    if ('-+0123456789.'.contains(ch)) return _parseNumber();
    throw LuaTableDecodeError("unexpected character '$ch' at offset $_pos: ${_text.substring(0, _text.length > 60 ? 60 : _text.length)}");
  }

  /// 当前位置是否是长括号字符串开头（`[[` 或 `[=*[`）。
  bool _isLongBracketStart() {
    if (_peek != '[') return false;
    var i = _pos + 1;
    while (i < _text.length && _text[i] == '=') {
      i++;
    }
    return i < _text.length && _text[i] == '[';
  }

  /// 解析长括号字符串：`[[内容]]` / `[=[内容]=]`（等号个数须与开头一致）。
  /// 按 Lua 语义，开头紧跟的第一个换行会被忽略。
  String _parseLongBracket() {
    _pos++; // 开头的 '['
    var level = 0;
    while (!_eof && _peek == '=') {
      level++;
      _pos++;
    }
    _expect('[');
    if (_peek == '\n') _pos++; // Lua: 跳过紧随其后的换行

    final close = ']${'=' * level}]';
    final end = _text.indexOf(close, _pos);
    if (end < 0) {
      throw LuaTableDecodeError('unterminated long string at offset $_pos');
    }
    final value = _text.substring(_pos, end);
    _pos = end + close.length;
    return value;
  }

  Object? _parseTable() {
    _expect('{');
    _skipWs();
    final items = <(Object?, Object?)>[]; // (key, value); key null => implicit index
    var nextIndex = 1;

    while (true) {
      _skipWs();
      if (_eof) throw LuaTableDecodeError('unterminated table literal');
      if (_peek == '}') {
        _pos++;
        break;
      }

      // `[` 只有当它不是长括号字符串（`[[` / `[=[`）时才是「显式键」；
      // 否则（如 `{ [[a]] }`）走隐式下标，交给 parseValue 解析。
      if (_peek == '[' && !_isLongBracketStart()) {
        _pos++;
        final key = _parseKey();
        _expect(']');
        _expect('=');
        items.add((key, parseValue()));
      } else {
        final m = _identRe.matchAsPrefix(_text, _pos);
        if (m != null) {
          final key = m.group(0)!;
          _pos += key.length;
          _expect('=');
          items.add((key, parseValue()));
        } else {
          items.add((null, parseValue()));
        }
      }

      _skipWs();
      if (_peek == ',') {
        _pos++;
      } else if (_peek != '}') {
        throw LuaTableDecodeError("expected ',' or '}' at offset $_pos: ${_text.substring(0, _text.length > 60 ? 60 : _text.length)}");
      }
    }

    if (items.isEmpty) return <String, Object?>{};

    // All implicit-index entries with no keyed fields → list.
    if (items.every((it) => it.$1 == null)) {
      return items.map((it) => it.$2).toList();
    }

    final result = <Object?, Object?>{};
    for (final (key, value) in items) {
      Object? k = key;
      if (key == null) {
        k = nextIndex;
        nextIndex++;
      }
      result[k!] = value;
    }

    // Lua arrays serialize with explicit numeric keys [1]=..,[2]=..;
    // a dense 1..N integer-keyed table maps to a List.
    final keys = result.keys.toList();
    if (keys.every((k) => k is int) && _isDense(keys)) {
      final list = <Object?>[];
      for (var i = 1; i <= keys.length; i++) {
        list.add(result[i]);
      }
      return list;
    }
    return _normalizeMap(result);
  }

  Object? _parseKey() {
    _skipWs();
    final ch = _peek;
    if (ch == '"' || ch == "'") return _parseString();
    if ('-+0123456789.'.contains(ch)) return _parseNumber();
    throw LuaTableDecodeError('invalid table key at offset $_pos');
  }

  String _parseString() {
    final quote = _peek;
    _pos++;
    final out = StringBuffer();
    while (!_eof) {
      final ch = _peek;
      _pos++;
      if (ch == quote) return out.toString();
      if (ch == '\\') {
        out.write(_parseEscape());
      } else {
        out.write(ch);
      }
    }
    throw LuaTableDecodeError('unterminated string literal');
  }

  String _parseEscape() {
    if (_eof) throw LuaTableDecodeError('unterminated escape sequence');
    final ch = _peek;
    _pos++;
    if (_escapes.containsKey(ch)) return _escapes[ch]!;
    if (ch == 'x') {
      // \xHH
      final hex = _text.substring(_pos, _pos + 2 > _text.length ? _text.length : _pos + 2);
      if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(hex)) {
        _pos += 2;
        return String.fromCharCode(int.parse(hex, radix: 16));
      }
      throw LuaTableDecodeError('invalid \\x escape');
    }
    if (RegExp(r'[0-9]').hasMatch(ch)) {
      // \ddd decimal
      var digits = '';
      for (var i = _pos; i < _text.length && digits.length < 2; i++) {
        if (RegExp(r'[0-9]').hasMatch(_text[i])) {
          digits += _text[i];
          _pos++;
        } else {
          break;
        }
      }
      final n = int.parse('$ch$digits');
      return String.fromCharCode(n);
    }
    return ch;
  }

  Object? _parseNumber() {
    final re = RegExp(r'^[-+]?(?:0[xX][0-9a-fA-F]+|\d*\.?\d+(?:[eE][-+]?\d+)?)');
    final m = re.firstMatch(_text.substring(_pos));
    if (m == null) throw LuaTableDecodeError('invalid number at offset $_pos');
    final token = m.group(0)!;
    _pos += token.length;
    if (token.toLowerCase().startsWith('0x')) return int.parse(token, radix: 16);
    if (token.contains('.') || token.contains('e') || token.contains('E')) {
      return double.parse(token);
    }
    return int.parse(token);
  }
}

bool _isDense(List keys) {
  final sorted = [...keys]..sort();
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i] != i + 1) return false;
  }
  return true;
}

/// Convert a Lua table literal into Dart objects.
/// Keys become String, except int keys kept as int (dense ones already became a List).
Object? decodeLuaTable(String text) {
  final parser = _Parser(text);
  final value = parser.parseValue();
  parser._skipWs();
  if (!parser._eof) {
    throw LuaTableDecodeError('trailing data at offset ${parser._pos}: ${text.substring(0, text.length > 60 ? 60 : text.length)}');
  }
  return value;
}

/// Decode a Mini World HTTP response body.
///
/// Tries strict JSON first; falls back to [decodeLuaTable].
///
/// Some endpoints concatenate multiple Lua table literals (one per line);
/// the LAST complete table carries the actual payload, so it wins.
///
/// An empty body is treated as `{}` — mutation endpoints return 200 with no
/// content on success.
Object? decodeHttpResponse(String text) {
  final stripped = text.trim();
  if (stripped.isEmpty) return <String, Object?>{};
  try {
    return jsonDecode(stripped);
  } on FormatException {
    try {
      return decodeLuaTable(stripped);
    } on LuaTableDecodeError {
      return _decodeLastLuaSegment(stripped);
    }
  }
}

Object? _decodeLastLuaSegment(String text) {
  final segments = <String>[];
  var depth = 0;
  int? start;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0 && start != null) {
        segments.add(text.substring(start, i + 1));
        start = null;
      }
    }
  }
  if (segments.isEmpty) {
    throw LuaTableDecodeError('no Lua table literal found: ${text.substring(0, text.length > 60 ? 60 : text.length)}');
  }
  for (final segment in segments.reversed) {
    try {
      return decodeLuaTable(segment);
    } on LuaTableDecodeError {
      // continue to next
    }
  }
  throw LuaTableDecodeError('no parseable Lua table segment');
}

// -- helpers -----------------------------------------------------------------

/// Normalize a map with mixed Object? keys to String keys where possible,
/// keeping int keys cast to into String for JSON-like consumption.
Map<String, Object?> _normalizeMap(Map<Object?, Object?> raw) {
  final out = <String, Object?>{};
  raw.forEach((k, v) => out['$k'] = v);
  return out;
}