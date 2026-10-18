/// 语音消息条：圆形播放/停止键 + 可拖动定位的波形进度 + 时长。
///
/// 载荷来自私有信封（`metadata['mn']` = `{k: 'voice', url, seconds}`）：
/// 官方客户端只看到 `[语音] 3″` 正文，MNChat 之间才是可点的语音条。
///
/// 进度来自 [startVoicePlayback]（media_kit 的 position/duration 流，真值）；
/// 播放中波形会流动，横向拖动可在播放中定位（松手才 seek，拖动中只做预览）；
/// 未播放时拖动不做任何事（避免误触就开播）。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/services/voice_clip.dart'
    show VoicePlayback, startVoicePlayback, voiceSecondsLabel;
import '../theme/app_tokens.dart' show AppSpacing;

/// 语音条本体（测试定位用）。
const Key voiceBubbleKey = Key('voice_bubble');

/// 语音条上的播放/停止键（测试定位用）。
const Key voicePlayButtonKey = Key('voice_play_button');

/// 波形（拖动定位的热区，测试定位用）。
const Key voiceWaveformKey = Key('voice_waveform');

/// 一条语音消息的可播放条。
class VoiceMessageBar extends StatefulWidget {
  const VoiceMessageBar({super.key, required this.url, required this.seconds});

  /// 音频地址（CDN）。为空表示没拿到载荷，只展示不可播的占位。
  final String url;

  /// 载荷里带的时长（秒）；0 表示未知。
  final int seconds;

  /// 波形柱子数量（宽度按它铺满）。
  static const int barCount = 22;

  /// 波形绘制区宽度（拖动定位按它换算比例）。
  static const double waveformWidth = 92;

  /// 波形绘制区高度。
  static const double waveformHeight = 24;

  @override
  State<VoiceMessageBar> createState() => _VoiceMessageBarState();
}

class _VoiceMessageBarState extends State<VoiceMessageBar>
    with SingleTickerProviderStateMixin {
  VoicePlayback? _pb;
  StreamSubscription<double>? _sub;
  double _progress = 0;
  bool _loading = false;

  /// 拖动中的预览位置（0..1）；为 null 表示没在拖。
  double? _scrub;

  /// 播放中波形流动的相位（0..1 循环）。
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void dispose() {
    _sub?.cancel();
    _flow.dispose();
    // 离开会话就别再响了。
    unawaited(_pb?.stop() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _toggle() async {
    final playing = _pb;
    if (playing != null) {
      await playing.stop();
      _sub?.cancel();
      _flow.stop();
      if (mounted) {
        setState(() {
          _pb = null;
          _progress = 0;
          _scrub = null;
        });
      }
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    final pb = await startVoicePlayback(widget.url, seconds: widget.seconds);
    if (!mounted) {
      await pb?.stop();
      return;
    }
    setState(() {
      _loading = false;
      _pb = pb;
      _progress = 0;
    });
    if (pb == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台暂不支持播放语音')),
      );
      return;
    }
    if (!_flow.isAnimating) _flow.repeat();
    _sub?.cancel();
    _sub = pb.progress.listen((v) {
      // 拖动预览优先，别被播放位置回冲。
      if (mounted && _scrub == null) setState(() => _progress = v);
    });
    unawaited(
      pb.done.then((_) {
        _sub?.cancel();
        _flow.stop();
        if (mounted) {
          setState(() {
            _pb = null;
            _progress = 0;
            _scrub = null;
          });
        }
      }),
    );
  }

  /// 拖动中：只更新预览（不 seek，避免拖动时反复跳）。
  void _onDragUpdate(double localX) {
    if (_pb == null) return; // 没在播就不响应，避免误触开播
    final f = (localX / VoiceMessageBar.waveformWidth).clamp(0.0, 1.0);
    setState(() => _scrub = f);
  }

  /// 松手：把预览位置落到播放器上。
  void _onDragEnd() {
    final f = _scrub;
    final pb = _pb;
    if (f == null) return;
    if (pb != null) unawaited(pb.seekFraction(f));
    setState(() {
      _progress = f;
      _scrub = null;
    });
  }

  /// 由 URL 派生的稳定波形（同一段语音每次画出来一样，不是随机抽动）。
  double _baseBarHeight(int i) {
    final seed = widget.url.codeUnits.fold<int>(
      7,
      (a, c) => (a * 31 + c) & 0xffff,
    );
    final v = ((seed >> (i % 8)) ^ (i * 2654435761)) & 0xff;
    return 5 + (v % 17);
  }

  /// 播放中的流动效果：一道波从右往左扫过，柱子高度随之起伏。
  double _barHeight(int i, {required bool flowing}) {
    final base = _baseBarHeight(i);
    if (!flowing) return base;
    final offset =
        (i / VoiceMessageBar.barCount - _flow.value) % 1.0;
    final wave = 0.72 + 0.28 * math.sin(2 * math.pi * offset);
    return base * wave;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final playing = _pb != null;
    final total = widget.seconds;
    final shown = _scrub ?? _progress;
    final elapsed = (total > 0 && (playing || _scrub != null))
        ? (shown * total).floor()
        : 0;
    final label = total > 0
        ? voiceSecondsLabel(playing && elapsed > 0 ? elapsed : total)
        : (elapsed > 0 ? voiceSecondsLabel(elapsed) : '语音');

    return Semantics(
      button: true,
      label: '播放语音 $total 秒',
      child: Padding(
        key: voiceBubbleKey,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _playButton(scheme, playing),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              key: voiceWaveformKey,
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _onDragUpdate(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => _onDragUpdate(d.localPosition.dx),
              onHorizontalDragEnd: (_) => _onDragEnd(),
              onHorizontalDragCancel: _onDragEnd,
              onTapDown: (d) => _onDragUpdate(d.localPosition.dx),
              onTapUp: (_) => _onDragEnd(),
              child: AnimatedBuilder(
                animation: _flow,
                builder: (_, _) => SizedBox(
                  width: VoiceMessageBar.waveformWidth,
                  height: VoiceMessageBar.waveformHeight,
                  child: Row(
                    children: List<Widget>.generate(VoiceMessageBar.barCount, (
                      i,
                    ) {
                      final done =
                          shown >= (i + 1) / VoiceMessageBar.barCount;
                      return Padding(
                        padding: EdgeInsets.only(
                          right: i == VoiceMessageBar.barCount - 1 ? 0 : 1.5,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 2.5,
                          height: _barHeight(i, flowing: playing),
                          decoration: BoxDecoration(
                            color: done
                                ? scheme.primary
                                : scheme.onSurfaceVariant.withValues(
                                    alpha: 0.35,
                                  ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: playing
                    ? scheme.primary
                    : theme.textTheme.labelMedium?.color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playButton(ColorScheme scheme, bool playing) {
    if (_loading) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }
    return Material(
      color: playing
          ? scheme.primary
          : scheme.primary.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        key: voicePlayButtonKey,
        customBorder: const CircleBorder(),
        onTap: _toggle,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: playing ? scheme.onPrimary : scheme.primary,
          ),
        ),
      ),
    );
  }
}
