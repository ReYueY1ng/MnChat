/// msgpack 封装 (对应 Python ormsgpack.packb/unpackb)。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:msgpack_codec/msgpack_codec.dart';

const MsgpackEncoder _encoder = MsgpackEncoder();
const MsgpackDecoder _decoder = MsgpackDecoder();

/// Ormsgpack-equivalent packing: List → bytes.
Uint8List msgpackPack(Object data) => _encoder.convert(data);

/// Ormsgpack-equivalent unpacking: bytes → dynamic List/Map.
dynamic msgpackUnpack(List<int> bytes) => _decoder.convert(Uint8List.fromList(bytes));

/// Strict JSON round-trip for the ChatPush channel (JSON, NOT msgpack).
List<dynamic> chatpushJsonDecode(String text) =>
    (jsonDecode(text) as List<dynamic>);

String chatpushJsonEncode(List<dynamic> data) => jsonEncode(data);