/// 录音弹窗：打开即开始录，显示已录秒数，停止后把音频字节交给调用方。
///
/// 只做采集与展示，不做上传/发送 —— 那部分留在 chat_page 的发送流程里。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/services/voice_clip.dart' show voiceSecondsLabel;
import '../../core/services/voice_recorder.dart';

/// 录音弹窗的测试定位 key（保持名字稳定）。
const Key voiceRecordDialogKey = Key('voice_record_dialog');

/// 弹出录音框；返回录到的音频字节（取消或没录到返回 null）。
Future<Uint8List?> showVoiceRecordDialog(BuildContext context) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _VoiceRecordDialog(),
  );
}

class _VoiceRecordDialog extends StatefulWidget {
  const _VoiceRecordDialog();

  @override
  State<_VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends State<_VoiceRecordDialog> {
  final VoiceRecorder _recorder = VoiceRecorder();
  Timer? _ticker;
  int _seconds = 0;
  bool _recording = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final ok = await _recorder.start();
    if (!mounted) return;
    setState(() {
      _recording = ok;
      _error = ok ? null : '拿不到麦克风权限，或设备不可用';
    });
    if (ok) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    }
  }

  /// 结束录音并关闭；[send] 为 false 表示放弃。
  Future<void> _finish({bool send = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    _ticker?.cancel();
    final bytes = send ? await _recorder.stop() : null;
    if (!send) await _recorder.cancel();
    await _recorder.dispose();
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      key: voiceRecordDialogKey,
      title: const Text('录音'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error == null ? Icons.mic : Icons.mic_off,
            size: 40,
            color: error == null ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(height: 12),
          Text(
            error ?? voiceSecondsLabel(_seconds),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _finish(send: false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (!_recording || _busy) ? null : () => _finish(),
          child: const Text('停止并发送'),
        ),
      ],
    );
  }
}
