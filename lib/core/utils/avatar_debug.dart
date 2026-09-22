/// 临时诊断：把头像取数过程写到应用文档目录下的 `avatar-debug.txt`。
///
/// 背景：真机上「本人头像/头像框不显示」「自定义头像被角色头像覆盖」，而用户
/// 抓不到 logcat。写到文件后可以直接取出：
/// ```
/// cat /data/data/me.yuey1ng.mnchat/app_flutter/avatar-debug.txt
/// ```
/// （与 `mnchat.sqlite` 同一个目录。）
///
/// **定位完成后应删除本文件与全部调用点。**
library;

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 追加一行诊断。**同步返回、内部 fire-and-forget**，失败静默 ——
/// 诊断本身绝不能影响功能，也不该让调用方被迫 await。
void avatarDebug(String line) {
  unawaited(_append(line));
}

Future<void> _append(String line) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/avatar-debug.txt');
    await file.writeAsString(
      '${DateTime.now().toIso8601String()} $line\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // 忽略：拿不到目录（如单元测试）时不写
  }
}
