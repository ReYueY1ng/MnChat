/// 应用内视频播放页（media_kit + 系统 libmpv）。
///
/// 深链入口：`mnchat://video?url=<http(s) URL 或本地路径>`。
/// 播放内核用系统 libmpv（Linux 需要 `libmpv.so`，本机已装）；Android 端还需
/// `media_kit_libs_android_video` 才会带上解码库。
library;

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 视频播放页的测试定位 key（保持名字稳定）。
const Key videoPlayerPageKey = Key('video_player_page');

/// 全屏播放一个视频地址。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.source, this.title = '视频'});

  /// 本地文件路径或 http(s) URL。
  final String source;

  /// 标题栏文案。
  final String title;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(widget.source));
    } catch (e) {
      // 打不开（文件不在、协议不支持）→ 页面上直接说明，不留黑屏。
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      key: videoPlayerPageKey,
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: Colors.black,
      body: Center(
        child: error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '无法播放：$error',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              )
            : Video(controller: _controller, controls: AdaptiveVideoControls),
      ),
    );
  }
}
