/// 发布动态页 —— 文字正文 + 选填话题 + 投票（可选）。
///
/// 对齐反编译 dynamicsdatamanager.lua：
/// - add_posting：content/from/homepage_hide/topic_list/question；
/// - create_vote：title/end_time/opt_num/opN/multi_mode/mode/name/from；
/// - 发布投票动态：先 create_vote 拿 vote_id，再 add_posting 带 vote_id。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/dynamics.dart';
import '../state/providers.dart';

class PublishDynamicsPage extends ConsumerStatefulWidget {
  const PublishDynamicsPage({super.key});

  @override
  ConsumerState<PublishDynamicsPage> createState() => _PublishDynamicsPageState();
}

class _PublishDynamicsPageState extends ConsumerState<PublishDynamicsPage> {
  final _textCtrl = TextEditingController();

  // 话题
  final _topicCtrl = TextEditingController();
  List<Map<String, Object?>> _topicResults = [];
  Map<String, Object?>? _selectedTopic;

  // 投票
  bool _withVote = false;
  final _voteTitleCtrl = TextEditingController();
  final List<TextEditingController> _voteOptCtrls = List.generate(4, (_) => TextEditingController());
  bool _voteMulti = false;

  DynamicsClient? _client;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(chatServiceProvider).auth;
    if (auth != null) {
      _client = DynamicsClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    }
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
      final resp = await client.searchTopic(q);
      final data = resp['data'];
      final list = <Map<String, Object?>>[];
      if (data is Map) {
        final raw = data['topic_list'] ?? data['list'];
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) list.add(e.cast<String, Object?>());
          }
        }
      }
      if (!mounted) return;
      setState(() => _topicResults = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _topicResults = []);
    }
  }

  Future<void> _publish() async {
    final client = _client;
    final text = _textCtrl.text.trim();
    if (client == null) return;
    if (text.isEmpty) {
      _toast('请输入内容');
      return;
    }
    if (_withVote) {
      final title = _voteTitleCtrl.text.trim();
      final opts = _voteOptCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      if (title.isEmpty || opts.length < 2) {
        _toast('投票需要标题和至少 2 个选项');
        return;
      }
    }
    setState(() => _publishing = true);
    try {
      String? voteId;
      if (_withVote) {
        final endTime = DateTime.now()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch ~/
            1000;
        final voteResp = await client.createVote(
          title: _voteTitleCtrl.text.trim(),
          endTime: endTime,
          opts: _voteOptCtrls
              .map((c) => c.text.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
          multiMode: _voteMulti ? 1 : 0,
          voteMode: 0,
        );
        final vdata = voteResp['data'];
        if (vdata is Map) {
          final vi = vdata['vote_info'];
          if (vi is Map) voteId = '${vi['vote_id']}';
        }
        if (voteId == null || voteId == 'null') {
          _toast('投票创建失败');
          return;
        }
      }
      Map<String, Object?> params = {
        'content': Uri.encodeQueryComponent(text),
        'from': '0',
        'homepage_hide': '0',
      };
      if (_selectedTopic != null) {
        params['topic_list'] =
            '[{"topic_id":${_selectedTopic!['topic_id']},"title":"${_selectedTopic!['title']}"}]';
      }
      if (voteId != null) params['vote_id'] = voteId;
      final resp = await client.addPostingRaw(params);
      if (!mounted) return;
      final ret = resp['ret'] ?? resp['code'];
      if (ret is num && ret != 0) {
        _toast('发布失败: ret=$ret ${resp['msg'] ?? ''}');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布动态'),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: const Text('发布'),
          ),
        ],
      ),
      body: _publishing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _textCtrl,
                  maxLines: 6,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: '分享新鲜事…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // 话题选择
                Text('话题（可选）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
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
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '搜索',
                      icon: const Icon(Icons.search),
                      onPressed: _searchTopic,
                    ),
                  ],
                ),
                if (_selectedTopic != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InputChip(
                      label: Text('#${_selectedTopic!['title']}'),
                      onDeleted: () => setState(() => _selectedTopic = null),
                    ),
                  ),
                if (_topicResults.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ..._topicResults.take(5).map((t) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('#${t['title']}'),
                        onTap: () => setState(() {
                          _selectedTopic = t;
                          _topicResults = [];
                          _topicCtrl.text = '';
                        }),
                      )),
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
                  const SizedBox(height: 8),
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
                ],
              ],
            ),
    );
  }
}
