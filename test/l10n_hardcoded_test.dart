// 本地化护栏：`lib/ui/**` 里不允许再出现硬编码的中文 UI 文案。
//
// 约定（见 `lib/ui/widgets/app_l10n.dart`）：所有用户可见文案必须走
// `l10nOf(context)?.someKey ?? '中文回退'`，其中 `??` 之后的中文回退是刻意保留的，
// 用于未挂 delegate 的 widget 测试与降级显示。
//
// 本测试只做纯文本扫描（没有新依赖），命中以下“展示位”中的中文**字面量**即失败：
//   Text('…')、tooltip:、label:、hintText:、labelText:、helpText:、title:、
//   subtitle:、message:、content:、dialogTitle:、Tab(text:)、SnackBar(...)、
//   AlertDialog(...)、_toast(…)、_snack(…)、showSettingsToast(…)。
//
// 例外：紧跟在 `??` 之后的中文回退；日志 / assert / StateError 等非展示位。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _cjkRe = RegExp('[\u4e00-\u9fa5]');

/// 去掉行注释与块注释（保留字符偏移与行号）。
String _stripComments(String src) {
  final out = src.split('');
  var i = 0;
  String? quote;
  while (i < src.length) {
    final c = src[i];
    if (quote == null) {
      if (src.startsWith('//', i)) {
        final end = src.indexOf('\n', i);
        final stop = end < 0 ? src.length : end;
        for (var k = i; k < stop; k++) {
          out[k] = ' ';
        }
        i = stop;
        continue;
      }
      if (src.startsWith('/*', i)) {
        final end = src.indexOf('*/', i + 2);
        final stop = end < 0 ? src.length : end + 2;
        for (var k = i; k < stop; k++) {
          if (out[k] != '\n') out[k] = ' ';
        }
        i = stop;
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        i++;
        continue;
      }
      i++;
    } else {
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
    }
  }
  return out.join();
}

/// 一个字符串字面量的位置与内容（偏移相对于去掉注释后的源码）。
class _Literal {
  const _Literal(this.start, this.end, this.body);
  final int start;
  final int end;
  final String body;
}

/// 手写扫描字符串字面量（支持单/双引号、三引号、`r` 前缀与转义）。
List<_Literal> _literals(String code) {
  final result = <_Literal>[];
  var i = 0;
  while (i < code.length) {
    final c = code[i];
    if (c != "'" && c != '"') {
      i++;
      continue;
    }
    final raw = i > 0 && code[i - 1] == 'r' &&
        (i < 2 || !RegExp(r'[A-Za-z0-9_]').hasMatch(code[i - 2]));
    final triple = i + 2 < code.length &&
        code[i + 1] == c &&
        code[i + 2] == c;
    final q = triple ? c * 3 : c;
    final bodyStart = i + q.length;
    var j = bodyStart;
    while (j < code.length) {
      if (!raw && code[j] == r'\') {
        j += 2;
        continue;
      }
      if (code.startsWith(q, j)) break;
      j++;
    }
    if (j >= code.length) break;
    result.add(_Literal(i, j + q.length, code.substring(bodyStart, j)));
    i = j + q.length;
  }
  return result;
}

/// 展示位前缀：命中即认为这个中文串会直接显示给用户。
final _visiblePrefixRe = RegExp(
  r'(?:Text|tooltip|label|labelText|hintText|helpText|title|subtitle|message|'
  r'content|dialogTitle|text|_toast|_snack|showSettingsToast)\s*[:,(]\s*$',
);

/// `??` 之后的中文回退是刻意保留的。
final _fallbackRe = RegExp(r'\?\?\s*$');

void _scan(String path) {
  final src = File(path).readAsStringSync();
  final code = _stripComments(src);
  for (final lit in _literals(code)) {
    if (!_cjkRe.hasMatch(lit.body)) continue;
    final before = code.substring(0, lit.start);
    final tail = before.length > 240
        ? before.substring(before.length - 240)
        : before;
    if (_fallbackRe.hasMatch(tail)) continue;
    if (!_visiblePrefixRe.hasMatch(tail)) continue;
    final line = before.split('\n').length;
    fail(
      '硬编码中文 UI 文案：$path:$line\n  "${lit.body}"\n'
      "请改用 l10nOf(context)?.someKey ?? '${lit.body}'。",
    );
  }
}

void main() {
  test('lib/ui 下没有硬编码的中文展示文案', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);
    for (final f in files) {
      _scan(f.path);
    }
  });
}
