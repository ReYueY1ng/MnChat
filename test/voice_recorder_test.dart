// 录音封装的降级口径：没有平台实现 / 没在录时一律安全返回，绝不抛。
//
// 真机（或 Linux + parecord）上的实际采集由 tool 级人工验证覆盖，这里只锁住
// "任何异常都不冒泡" 这一条 —— 与 models/ 的 lenient 口径一致。
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/voice_recorder.dart';

void main() {
  test('未开始时 stop 返回 null，isRecording 返回 false，都不抛', () async {
    final recorder = VoiceRecorder();
    expect(await recorder.stop(), isNull);
    expect(await recorder.isRecording(), isFalse);
    await recorder.cancel();
    await recorder.dispose();
  });

  test('WAV 头常量就是 44 字节（只读到头 = 没录到内容）', () {
    expect(kWavHeaderBytes, 44);
  });
}
