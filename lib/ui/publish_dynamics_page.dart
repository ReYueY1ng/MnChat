/// 发布动态页 —— 正文 + 话题 + 图片(≤9) + 可见范围 + @好友 + 投票（可选）。
///
/// 对齐反编译 dynamicsdatamanager.lua：
/// - `AddPosting`（:1376-1450）：content / from / homepage_hide / auth_see /
///   notice_uins / topic_list / vote_id，图片走 `seq`（`1..curPicCount`
///   逗号分隔，见 :1394-1403、:1446-1448）；
/// - `AddPostPic`（:7727-7778）：`add_posting_pic&seq=N&md5=<文件md5>&ext=..[&show_idx=N]`；
/// - `DeleteUploadPicture`（:3851）：`delete_posting_pic&seq=N`；
/// - `ReqCreateVote`（:4462）：`end_time`（秒）由发布页选择。
///
/// 发布页交互对齐 dynamics_frame_news/dynamics_frame_newsctrl.lua：
/// `notice_uins = uins`（:2315）、`auth_see = publishType`（:2316）、
/// `curPicCount = #pic_list`（:2318）、`end_time = cfg.endTime`（:2532）；
/// 截止时间选择器对齐 dynamics_time_selecter（年/月/日/时/分）。
///
/// 注意：content 原样传给 [DynamicsClient.addPostingRaw]，其内部 `_url` 已对
/// 每个值做一次 `Uri.encodeQueryComponent`；这里再编码一次会破坏中文正文。
library;

import 'dart:convert' show jsonEncode;
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart' show FilePicker, FileType;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/models/messages.dart' show Contact;
import '../core/models/nickname.dart' show plainNickname;
import '../core/services/dynamics.dart';
import '../state/providers.dart';
import 'theme/app_tokens.dart';

/// 选中的本地图片（[bytes] 为原始字节，[name] 用于取扩展名）。
typedef DynamicsPickedImage = ({String name, List<int> bytes});

/// 选图注入点（测试用）：[remaining] 为还能再选的张数。
///
/// 为空时走真实 [FilePicker]（`FileType.image`，多选）。
typedef DynamicsImagePicker = Future<List<DynamicsPickedImage>> Function(
  int remaining,
);

/// 正文输入框 Key。
const Key publishDynamicsContentKey = Key('publishDynamicsContent');

/// 「添加图片」按钮 Key。
const Key publishDynamicsAddImageKey = Key('publishDynamicsAddImage');

/// 「@好友」按钮 Key。
const Key publishDynamicsNoticeUinsKey = Key('publishDynamicsNoticeUins');

/// 投票截止时间按钮 Key。
const Key publishDynamicsVoteEndKey = Key('publishDynamicsVoteEnd');

/// 「发布」按钮 Key。
const Key publishDynamicsSubmitKey = Key('publishDynamicsSubmit');

/// 可见范围选项 Key（按 [DynamicsAuth] 的取值）。
Key publishDynamicsAuthSeeKey(int value) =>
    ValueKey<String>('publishDynamicsAuthSee-$value');

/// 已选图片格子 Key（按 1-based seq）。
Key publishDynamicsPicKey(int seq) => ValueKey<String>('publishDynamicsPic-$seq');

/// 发布动态页。
class PublishDynamicsPage extends ConsumerStatefulWidget {
  const PublishDynamicsPage({super.key, this.client, this.imagePicker});

  /// 注入的动态客户端（测试用）；为空时由 `chatServiceProvider` 的 auth 现建。
  final DynamicsClient? client;

  /// 选图注入点（测试用）；为空时走真实 [FilePicker]。
  final DynamicsImagePicker? imagePicker;

  @override
  ConsumerState<PublishDynamicsPage> createState() =>
      _PublishDynamicsPageState();
}

/// 一张待发布的图片（seq 与上传顺序一致，删除后不重排）。
class _PublishPic {
  _PublishPic({
    required this.seq,
    required this.name,
    required this.bytes,
    required this.ext,
    required this.md5,
  });

  /// 1-based 序号；`add_posting_pic` 与 `add_posting` 的 seq 用它配对。
  final int seq;
  final String name;
  final List<int> bytes;
  final String ext;
  final String md5;

  /// 登记成功后的图片 url；null = 尚未上传成功。
  String? url;
}

class _PublishDynamicsPageState extends ConsumerState<PublishDynamicsPage> {
  /// 单条动态最多 9 张图（对齐 `self.define.maxPic`）。
  static const int _maxPics = 9;

  final _textCtrl = TextEditingController();

  // 话题
  final _topicCtrl = TextEditingController();
  List<DynamicsTopic> _topicResults = [];
  DynamicsTopic? _selectedTopic;

  // 图片
  final List<_PublishPic> _pics = [];
  bool _imageBusy = false;

  // 可见范围（auth_see）
  int _authSee = DynamicsAuth.all;

  // @好友（notice_uins）
  Set<int> _noticeUins = <int>{};

  // 投票
  bool _withVote = false;
  final _voteTitleCtrl = TextEditingController();
  final List<TextEditingController> _voteOptCtrls =
      List.generate(4, (_) => TextEditingController());
  bool _voteMulti = false;

  /// 投票截止时间；默认 now + 7 天（可改，见 [_pickVoteEnd]）。
  DateTime _voteEnd = DateTime.now().add(const Duration(days: 7));

  DynamicsClient? _client;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? _clientFromAuth();
  }

  DynamicsClient? _clientFromAuth() {
    final auth = ref.read(chatServiceProvider).auth;
    if (auth == null) return null;
    return DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _topicCtrl.dispose();
    _voteTitleCtrl.dispose();
    for (final c in _voteOptCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _searchTopic() async {
    final client = _client;
    final q = _topicCtrl.text.trim();
    if (client == null || q.isEmpty) return;
    try {
      final topics = await client.searchTopic(q);
      if (!mounted) return;
      setState(() => _topicResults = topics);
    } catch (_) {
      if (!mounted) return;
      setState(() => _topicResults = []);
    }
  }

  // ── 图片 ────────────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    final client = _client;
    if (client == null || _imageBusy) return;
    final remaining = _maxPics - _pics.length;
    if (remaining <= 0) {
      _toast('最多只能上传 $_maxPics 张图片');
      return;
    }
    List<DynamicsPickedImage> picked;
    try {
      picked = widget.imagePicker != null
          ? await widget.imagePicker!(remaining)
          : await _pickViaFilePicker();
    } catch (e) {
      _toast('选择图片失败：$e');
      return;
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _imageBusy = true);
    for (final img in picked.take(remaining)) {
      final pic = _PublishPic(
        seq: _nextSeq(),
        name: img.name,
        bytes: img.bytes,
        ext: _extOf(img.name),
        md5: crypto.md5.convert(img.bytes).toString(),
      );
      setState(() => _pics.add(pic));
      await _uploadPic(client, pic);
    }
    if (mounted) setState(() => _imageBusy = false);
  }

  Future<List<DynamicsPickedImage>> _pickViaFilePicker() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择图片',
      type: FileType.image,
    );
    final out = <DynamicsPickedImage>[];
    for (final f in files) {
      out.add((name: f.name, bytes: await f.readAsBytes()));
    }
    return out;
  }

  /// 直传并登记一张图片（对齐 `UploadPicFile` + `AddPostPic` 两步）。
  Future<void> _uploadPic(DynamicsClient client, _PublishPic pic) async {
    try {
      final url = await client.uploadPostingPic(
        seq: pic.seq,
        bytes: pic.bytes,
        fileMd5: pic.md5,
        ext: pic.ext,
        showIdx: pic.seq,
      );
      if (!mounted) return;
      if (url == null) {
        _toast('图片上传失败：${pic.name}');
        return;
      }
      setState(() => pic.url = url);
    } catch (e) {
      if (mounted) _toast('图片上传失败：$e');
    }
  }

  /// 移除一张图片：服务端 `delete_posting_pic&seq=N` + 本地移除。
  Future<void> _removePic(_PublishPic pic) async {
    final client = _client;
    setState(() => _pics.remove(pic));
    if (client == null || pic.url == null) return;
    try {
      await client.deletePostingPic(pic.seq);
    } catch (e) {
      if (mounted) _toast('图片删除失败：$e');
    }
  }

  /// 下一个可用序号（删除后不重排，保证 seq 与已登记的服务端图片一一对应）。
  int _nextSeq() {
    var max = 0;
    for (final p in _pics) {
      if (p.seq > max) max = p.seq;
    }
    return max + 1;
  }

  /// 取扩展名（小写、不含点）；无扩展名回退 jpg。
  String _extOf(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return 'jpg';
    return name.substring(i + 1).toLowerCase();
  }

  // ── 可见范围 / @好友 / 投票截止 ─────────────────────────────────────────

  Future<void> _pickNoticeUins(List<Contact> contacts) async {
    final friends = contacts.where((c) => (c.relation & 8) != 0).toList()
      ..sort(
        (a, b) => a.nickname.toLowerCase().compareTo(b.nickname.toLowerCase()),
      );
    if (friends.isEmpty) {
      _toast('暂无好友可 @');
      return;
    }
    final selected = <int>{..._noticeUins};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('@好友'),
          content: SizedBox(
            width: dialogContentWidth(ctx, 420),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in friends)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(c.uin),
                    // 昵称来自服务端，可能带 `[i][color][b]` 标记；纯文本需先洗。
                    title: Text(
                      plainNickname(c.nickname).isEmpty
                          ? '${c.uin}'
                          : plainNickname(c.nickname),
                    ),
                    subtitle: Text('迷你号 ${c.uin}'),
                    onChanged: (v) => setDialogState(() {
                      if (v == true) {
                        selected.add(c.uin);
                      } else {
                        selected.remove(c.uin);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) setState(() => _noticeUins = selected);
  }

  /// 选择投票截止时间：日期 + 时间（对齐 dynamics_time_selecter 的年月日时分）。
  Future<void> _pickVoteEnd() async {
    final now = DateTime.now();
    // 服务端要求 end_time ≥ now + 1800s（dynamics_vote_setupctrl.lua:209）。
    final earliest = now.add(const Duration(minutes: 30));
    final date = await showDatePicker(
      context: context,
      initialDate: _voteEnd.isAfter(earliest) ? _voteEnd : earliest,
      firstDate: earliest,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_voteEnd),
    );
    if (time == null || !mounted) return;
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!end.isAfter(earliest)) {
      _toast('截止时间需晚于当前时间 30 分钟');
      return;
    }
    setState(() => _voteEnd = end);
  }

  // ── 发布 ────────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    final client = _client;
    final text = _textCtrl.text.trim();
    if (client == null) return;
    if (_imageBusy) {
      _toast('图片上传中，请稍候');
      return;
    }
    if (text.isEmpty && _pics.isEmpty) {
      _toast('请输入内容');
      return;
    }
    if (_pics.any((p) => p.url == null)) {
      _toast('有图片尚未上传成功');
      return;
    }
    if (_withVote) {
      final title = _voteTitleCtrl.text.trim();
      final opts = _voteOptCtrls
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (title.isEmpty || opts.length < 2) {
        _toast('投票需要标题和至少 2 个选项');
        return;
      }
    }
    setState(() => _publishing = true);
    try {
      String? voteId;
      if (_withVote) {
        final voteResp = await client.createVote(
          title: _voteTitleCtrl.text.trim(),
          endTime: _voteEnd.millisecondsSinceEpoch ~/ 1000,
          opts: _voteOptCtrls
              .map((c) => c.text.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          multiMode: _voteMulti ? 1 : 0,
          voteMode: 0,
        );
        voteId = voteResp.voteInfo?.voteId;
        if (voteId == null || voteId.isEmpty || voteId == 'null') {
          _toast('投票创建失败');
          return;
        }
      }
      final topic = _selectedTopic;
      final params = <String, Object?>{
        // 原样正文：addPostingRaw → _url 已 encodeQueryComponent 一次。
        'content': text,
        'from': '0',
        'homepage_hide': '0',
        'auth_see': '$_authSee',
      };
      // 图片：已登记图片的 seq 列表（1-based、逗号分隔、按上传顺序）。
      if (_pics.isNotEmpty) {
        params['seq'] = _pics.map((p) => p.seq).join(',');
      }
      if (_noticeUins.isNotEmpty) {
        params['notice_uins'] = _noticeUins.join(',');
      }
      if (topic != null) {
        params['topic_list'] = jsonEncode([
          {'topic_id': topic.topicId, 'title': topic.title},
        ]);
      }
      if (voteId != null) params['vote_id'] = voteId;
      final resp = await client.addPostingRaw(params);
      if (!mounted) return;
      if (resp.code != 0) {
        _toast('发布失败: ret=${resp.code} ${resp.message}');
        return;
      }
      _toast('发布成功');
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast('发布失败: $e');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 好友列表：StreamProvider 只在 build 里 watch 才有值（read 冷启动只有
    // loading），与 dynamics_card.dart 同款。
    final contacts = ref.watch(contactsProvider).value ?? const <Contact>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布动态'),
        actions: [
          TextButton(
            key: publishDynamicsSubmitKey,
            onPressed: _publishing ? null : _publish,
            child: const Text('发布'),
          ),
        ],
      ),
      body: _publishing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                TextField(
                  key: publishDynamicsContentKey,
                  controller: _textCtrl,
                  maxLines: 6,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: '分享新鲜事…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // 图片（≤9）
                _buildPicSection(theme),
                const SizedBox(height: AppSpacing.md),
                // 可见范围（auth_see）
                Text('可见范围', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final e in DynamicsAuth.labels.entries)
                      ChoiceChip(
                        key: publishDynamicsAuthSeeKey(e.key),
                        label: Text(e.value),
                        selected: _authSee == e.key,
                        onSelected: (_) => setState(() => _authSee = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // @好友（notice_uins）
                Row(
                  children: [
                    Text('@好友', style: theme.textTheme.titleSmall),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      key: publishDynamicsNoticeUinsKey,
                      onPressed: () => _pickNoticeUins(contacts),
                      icon: const Icon(Icons.alternate_email, size: 18),
                      label: const Text('选择好友'),
                    ),
                  ],
                ),
                if (_noticeUins.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final uin in _noticeUins)
                          InputChip(
                            label: Text('@$uin'),
                            onDeleted: () =>
                                setState(() => _noticeUins.remove(uin)),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                // 话题选择
                Text('话题（可选）', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _topicCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '搜索话题',
                          prefixText: '# ',
                        ),
                        onSubmitted: (_) => _searchTopic(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      tooltip: '搜索',
                      icon: const Icon(Icons.search),
                      onPressed: _searchTopic,
                    ),
                  ],
                ),
                if (_selectedTopic != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: InputChip(
                      label: Text('#${_selectedTopic!.title}'),
                      onDeleted: () => setState(() => _selectedTopic = null),
                    ),
                  ),
                if (_topicResults.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ..._topicResults.take(5).map(
                        (t) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('#${t.title}'),
                          onTap: () => setState(() {
                            _selectedTopic = t;
                            _topicResults = [];
                            _topicCtrl.text = '';
                          }),
                        ),
                      ),
                ],
                const Divider(height: 24),
                // 投票开关
                SwitchListTile(
                  title: const Text('附带投票'),
                  subtitle: const Text('发布后可让好友投票'),
                  value: _withVote,
                  onChanged: (v) => setState(() => _withVote = v),
                ),
                if (_withVote) ...[
                  TextField(
                    controller: _voteTitleCtrl,
                    decoration: const InputDecoration(
                      labelText: '投票标题',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TextField(
                        controller: _voteOptCtrls[i],
                        decoration: InputDecoration(
                          labelText: '选项 ${i + 1}',
                          isDense: true,
                        ),
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('允许多选'),
                    value: _voteMulti,
                    onChanged: (v) => setState(() => _voteMulti = v),
                  ),
                  ListTile(
                    key: publishDynamicsVoteEndKey,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('截止时间'),
                    subtitle: Text(_formatVoteEnd(_voteEnd)),
                    trailing: const Icon(Icons.schedule),
                    onTap: _pickVoteEnd,
                  ),
                ],
              ],
            ),
    );
  }

  /// 图片区：已选图片缩略图（含删除）+ 添加按钮。
  Widget _buildPicSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '图片（${_pics.length}/$_maxPics）',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(width: AppSpacing.sm),
            if (_imageBusy)
              const SizedBox(
                width: AppSpacing.lg,
                height: AppSpacing.lg,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final pic in _pics)
              SizedBox(
                key: publishDynamicsPicKey(pic.seq),
                width: 72,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.chipR,
                      child: Image.memory(
                        Uint8List.fromList(pic.bytes),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Colors.black12,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    if (pic.url == null)
                      const ColoredBox(
                        color: Colors.black26,
                        child: Center(
                          child: SizedBox(
                            width: AppSpacing.lg,
                            height: AppSpacing.lg,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        tooltip: '删除图片',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: const Icon(Icons.cancel),
                        onPressed: () => _removePic(pic),
                      ),
                    ),
                  ],
                ),
              ),
            if (_pics.length < _maxPics)
              OutlinedButton(
                key: publishDynamicsAddImageKey,
                onPressed: _imageBusy ? null : _pickImages,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Icon(Icons.add_photo_alternate_outlined),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  /// 截止时间文案：`YYYY-MM-DD HH:MM`（对齐 dynamics_time_selecterCtrl）。
  static String _formatVoteEnd(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
}
