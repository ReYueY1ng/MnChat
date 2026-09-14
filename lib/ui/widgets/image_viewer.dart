import 'package:flutter/material.dart';

/// 打开全屏图片查看器（左右翻页，点按关闭，双指缩放）。
void openImageViewer(BuildContext context, List<String> urls, int initialIndex) {
  if (urls.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ImageViewerPage(urls: urls, initialIndex: initialIndex),
  ));
}

class ImageViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const ImageViewerPage({super.key, required this.urls, required this.initialIndex});

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        title: Text('${_index + 1}/${widget.urls.length}'),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            child: Center(
              child: Image.network(widget.urls[i], fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Icon(Icons.broken_image, color: cs.onSurface, size: 48),
                  loadingBuilder: (c, w, p) => p == null ? w : const Center(child: CircularProgressIndicator())),
            ),
          ),
        ),
      ),
    );
  }
}
