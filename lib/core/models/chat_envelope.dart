/// MNChat 私有扩展协议 v1：把结构化元数据（引用 / 正在输入 / 语音…）以
/// **零宽字符**隐写在消息正文尾部。
///
/// 为什么用零宽字符而不是可见标记（`[[mn:...]]`）：
/// - 官方客户端与其它客户端看到的是**干净正文** —— 零宽字符不渲染，不会出现乱码
///   或"未知字段"提示，天然满足"未知字段降级为文本"；
/// - MNChat ↔ MNChat 之间才解得出元数据（引用块、正在输入）；
/// - 元数据损坏 / 版本不认识时，[splitMnMessage] 原样返回正文（不删不改），
///   等于退回普通文本。
///
/// 位编码：位 0 → U+200B（ZWSP），位 1 → U+200C（ZWNJ），末尾 U+200D（ZWJ）作
/// 结束哨兵。头 32 位 = 魔数 16 位（'MN'）+ 版本 4 位 + 载荷字符数 12 位；载荷是
/// base64url(JSON) 的每个字符（6 位一组，字母表下标）。
///
/// 纯函数、无 IO、无 Flutter 依赖；脏数据一律不抛。
library;

import 'dart:convert';

/// 版本号（不认识更高版本就整体忽略）。
///
/// v3（2026-10-17）：**4 位/字符**的 16 符号字母表 + 瘦头（20 位）+ **按 UTF-8
/// 字节**算预算。实测依据：`send_chat_msg` 的正文上限是 **~128 字节**（纯 ASCII 128
/// 通过、140 回 `result=13`；101 个字符含 95 个零宽也是 13）。隐形符号在 UTF-8 里
/// 多为 3 字节，所以 v2（3 位/字符）的一个 typing 信封（51 字符）就要 150 字节，
/// 照样发不出去。
const int kMnEnvelopeVersion = 3;

/// 魔数 'M'（v3 起缩成 8 位，把位数留给载荷）。
const int kMnEnvelopeMagic = 0x4D;

/// 服务端 `send_chat_msg` 的正文上限（**UTF-8 字节**，实测：128 通过 / 140 回
/// `result=13` msg_too_long）。
const int kMnMaxMessageBytes = 128;

/// 信封占位预算（字节）：留给可见正文的余量，超过就不带信封（见 [attachMnEnvelope]）。
const int kMnEnvelopeBudgetBytes = 120;

/// 起始标记（软连字符，2 字节，正常渲染不可见）。
const String _start = '\u00AD';

/// 结束标记（ZWNBSP，3 字节）。
const String _end = '\uFEFF';

/// 4 位/字符的隐写字母表：下标即 4 位值（16 个，全部不可见）。
const List<String> _symbols = <String>[
  '\u200B', // ZWSP
  '\u200C', // ZWNJ
  '\u200D', // ZWJ
  '\u200E', // LRM
  '\u200F', // RLM
  '\u2060', // WORD JOINER
  '\u2061', // function application
  '\u2062', // invisible times
  '\u2063', // invisible separator
  '\u2064', // invisible plus
  '\uFEFF', // ZWNBSP
  '\u034F', // combining grapheme joiner
  '\u061C', // Arabic letter mark
  '\u180E', // Mongolian vowel separator
  '\u17B4', // Khmer inherent vowel
  '\u17B5', // Khmer inherent vowel
];

const int _bitsPerSymbol = 4;

/// 载荷字符数上限（9 位）。
const int _kMaxPayloadChars = 0x1FF;

const String _b64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// 信封种类。
enum MnEnvelopeKind {
  /// 引用回复：载荷 `{text, uin}` 指向被引用的原文。
  quote,

  /// 正在输入（正文通常为空）。
  typing,

  /// 语音消息：载荷 `{url, seconds}`。
  voice,
}

/// 一条私有元数据。
class MnEnvelope {
  final MnEnvelopeKind kind;
  final Map<String, Object?> payload;

  const MnEnvelope(this.kind, this.payload);

  Map<String, Object?> toJson() => <String, Object?>{
    'k': kind.name,
    ...payload,
  };

  @override
  String toString() => 'MnEnvelope(${kind.name}, $payload)';
}

/// 把信封编码进 `extend_data`（`url_encode(base64(JSON{'mn': env}))`，与分享卡同形）。
///
/// **为什么需要它**：`send_chat_msg` 的正文上限约 128 **字节**，而隐形符号多占
/// 3 字节/个 —— 引用原文、语音 URL 这类载荷在正文里根本装不下（服务端回
/// `result=13`）。`extend_data` 是独立字段：没有正文长度约束，官方客户端忽略
/// 未知键，MNChat 之间才读。
String encodeMnExtendData(MnEnvelope envelope) =>
    Uri.encodeQueryComponent(
      base64Encode(utf8.encode(jsonEncode(<String, Object?>{'mn': envelope.toJson()}))),
    );

/// 从已解析的 `extend_data` 里取信封；没有 / 不认识 → null。
MnEnvelope? envelopeFromExtendData(Map<String, Object?>? extend) {
  final raw = extend?['mn'];
  if (raw is! Map) return null;
  final map = raw.cast<String, Object?>();
  final kindName = map['k']?.toString();
  for (final kind in MnEnvelopeKind.values) {
    if (kind.name != kindName) continue;
    return MnEnvelope(kind, <String, Object?>{
      for (final e in map.entries)
        if (e.key != 'k') e.key.toString(): e.value,
    });
  }
  return null;
}

/// 把 [envelope] 隐写进 [text]（可见部分不变，返回新字符串）。
///
/// 两种情形返回原 [text]：载荷还带不下（超长 / 不是纯 base64url 字符），
/// 或加上信封后总长会超过 [kMnEnvelopeBudgetChars]（服务端上限见
/// [kMnMaxMessageChars]，超了会被回 `result=13`）。
String attachMnEnvelope(String text, MnEnvelope envelope) {
  String b64;
  try {
    b64 = base64Url
        .encode(utf8.encode(jsonEncode(envelope.toJson())))
        .replaceAll('=', '');
  } catch (_) {
    return text;
  }
  if (b64.isEmpty || b64.length > _kMaxPayloadChars) return text;
  for (final unit in b64.codeUnits) {
    if (!_b64Alphabet.contains(String.fromCharCode(unit))) return text;
  }

  final bits = <int>[];
  void put(int value, int width) {
    for (var i = width - 1; i >= 0; i--) {
      bits.add((value >> i) & 1);
    }
  }

  put(0x4D, 8); // 魔数 'M'
  put(kMnEnvelopeVersion, 3);
  put(b64.length, 9);
  for (final unit in b64.codeUnits) {
    put(_b64Alphabet.indexOf(String.fromCharCode(unit)), 6);
  }

  // 3 位一组落到隐写字符（尾部不足 3 位补 0）。
  final hidden = StringBuffer(_start);
  for (var i = 0; i < bits.length; i += _bitsPerSymbol) {
    var value = 0;
    for (var n = 0; n < _bitsPerSymbol; n++) {
      value = (value << 1) | (i + n < bits.length ? bits[i + n] : 0);
    }
    hidden.write(_symbols[value]);
  }
  hidden.write(_end);

  // 服务端有正文字节上限：加上信封会超限就**整条不带**（宁可不带元数据，
  // 也不能让消息被 msg_too_long 拒收）。
  final block = hidden.toString();
  final total = utf8.encode(text).length + utf8.encode(block).length;
  if (total > kMnEnvelopeBudgetBytes) return text;
  return '$text$block';
}

/// 拆出正文与信封。
///
/// - 没有隐写块 → `(raw, null)`，**原样返回**；
/// - 有隐写块且结构合法、版本认识 → `(可见正文, 信封)`；
/// - 有隐写块但魔数/版本/长度/JSON 任一不合法 → `(raw, null)`：正文一个字符都
///   不动，等于这条消息退化成普通文本。
(String, MnEnvelope?) splitMnMessage(String raw) {
  if (raw.isEmpty) return (raw, null);
  if (raw.codeUnitAt(raw.length - 1) != _end.codeUnitAt(0)) return (raw, null);

  var i = raw.length - 2;
  final values = <int>[];
  while (i >= 0) {
    final ch = String.fromCharCode(raw.codeUnitAt(i));
    final index = _symbols.indexOf(ch);
    if (index < 0) break;
    values.add(index);
    i--;
  }
  if (i < 0) return (raw, null);
  if (String.fromCharCode(raw.codeUnitAt(i)) != _start) return (raw, null);
  final start = i;

  final bits = <int>[];
  for (final value in values.reversed) {
    for (var n = _bitsPerSymbol - 1; n >= 0; n--) {
      bits.add((value >> n) & 1);
    }
  }
  if (bits.length < 20) return (raw, null);

  var cursor = 0;
  int take(int width) {
    var value = 0;
    for (var n = 0; n < width; n++) {
      value = (value << 1) | bits[cursor + n];
    }
    cursor += width;
    return value;
  }

  final magic = take(8);
  final version = take(3);
  if (magic != kMnEnvelopeMagic || version > kMnEnvelopeVersion) {
    return (raw, null);
  }
  final count = take(9);
  if (count <= 0 || bits.length - cursor < count * 6) return (raw, null);

  final chars = StringBuffer();
  for (var n = 0; n < count; n++) {
    final index = take(6);
    if (index >= _b64Alphabet.length) return (raw, null);
    chars.write(_b64Alphabet[index]);
  }

  try {
    final padded = chars.toString();
    final decoded = utf8.decode(base64Url.decode('$padded${'=' * ((4 - padded.length % 4) % 4)}'));
    final json = jsonDecode(decoded);
    if (json is! Map) return (raw, null);
    final kindName = json['k']?.toString();
    MnEnvelopeKind? kind;
    for (final candidate in MnEnvelopeKind.values) {
      if (candidate.name == kindName) {
        kind = candidate;
        break;
      }
    }
    if (kind == null) return (raw, null);
    final payload = <String, Object?>{
      for (final e in json.entries)
        if (e.key != 'k') e.key.toString(): e.value,
    };
    return (raw.substring(0, start), MnEnvelope(kind, payload));
  } catch (_) {
    // 结构合法但 JSON/UTF-8 坏了：同样退回原文本。
    return (raw, null);
  }
}
