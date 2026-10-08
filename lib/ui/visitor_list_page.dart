/// 访客记录页 —— 谁来看过我（`get_visitor_list`）。
///
/// 数据流（对齐反编译 playercenterv2homepagectrl.lua:ReqVisitorList）：
///   1. `PlayerHomeClient.getVisitorList(ownerUin)` 取 `[{uin, time}]`
///      （time 为 epoch 秒，官方客户端只取 offset=0 的第一页）；
///   2. 用 `ProfileClient.fetchAvatarProfiles` 批量补全昵称 / 头像 / 头像框；
///   3. 按服务端返回顺序逐行渲染（不排序、不分页）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/player_home.dart';
import '../core/services/profile.dart' show PlayerProfile, ProfileClient;
import '../state/providers.dart';
import 'player_home_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart';
import 'widgets/rich_text_view.dart';

/// 访客记录页。
class VisitorListPage extends ConsumerStatefulWidget {
  /// 要查询的玩家 uin（当前入口仅传入本人 uin）。
  final int ownerUin;

  /// 页面标题。
  final String title;

  const VisitorListPage({
    super.key,
    required this.ownerUin,
    this.title = '访客记录',
  });

  @override
  ConsumerState<VisitorListPage> createState() => _VisitorListPageState();
}

class _VisitorListPageState extends ConsumerState<VisitorListPage> {
  /// 访客记录（保持服务端返回顺序）。
  List<VisitRecord> _records = const [];

  /// uin → 访客资料（昵称 / 头像 / 头像框）；拉取失败时为空。
  Map<int, PlayerProfile> _profiles = const {};

  /// 加载中（首屏与手动刷新共用）。
  bool _loading = true;

  /// 错误信息；非 null 时展示错误态与重试按钮。
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 加载访客列表，并批量补全访客资料。
  ///
  /// 资料接口失败只降级为迷你号 + 首字占位，不影响访客列表本身。
  Future<void> _load() async {
    final auth = ref.read(authProvider).auth;
    if (auth == null) {
      setState(() {
        _loading = false;
        _error = '未登录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final home = PlayerHomeClient(uin: auth.uin, s2: auth.s2, s2t: auth.s2t);
    final profileClient = ProfileClient(
      uin: auth.uin,
      s2: auth.s2,
      s2t: auth.s2t,
    );
    try {
      final records = await home.getVisitorList(widget.ownerUin);
      var profiles = <int, PlayerProfile>{};
      if (records.isNotEmpty) {
        try {
          // 头像要连头像本体 / DIY 一起取（`header*` 不是头像）。
          profiles = await profileClient.fetchAvatarProfiles(
            records.map((r) => r.uin).toList(),
          );
        } catch (_) {
          // 忽略：资料拉取失败时展示迷你号与首字占位头像
        }
      }
      if (!mounted) return;
      setState(() {
        _records = records;
        _profiles = profiles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 打开访客的玩家主页。
  void _openHome(int uin) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerHomePage(targetUin: uin)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.narrowContent),
          child: _buildBody(),
        ),
      ),
    );
  }

  /// 按 加载中 → 错误 → 空 → 列表 的顺序选择主体内容。
  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError();
    }
    if (_records.isEmpty) {
      return _buildEmpty();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _records.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final rec = _records[i];
          final profile = _profiles[rec.uin];
          final nickname = profile?.nickname ?? '';
          return ListTile(
            // ListTile 给 leading 的高度上限受密度钳制（桌面紧凑密度下 48），
            // 会把有框槽位（radius * 2 / 0.76 ≈ 63.2）压成非正方形并裁掉框外圈。
            // 抬高纵向密度并用 minTileHeight 兜住行高（见 [kAvatarListTileDensity]）。
            visualDensity: kAvatarListTileDensity,
            minTileHeight: headFrameSlotSize(24),
            leading: AvatarView(
              avatarUrl: profile?.avatarUrl,
              name: profile?.nickname ?? '${rec.uin}',
              radius: 24,
              frameId: profile?.headFrameId,
            ),
            title: RichTextView(
              nickname.isNotEmpty ? nickname : '${rec.uin}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_fmtTime(rec.time * 1000)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openHome(rec.uin),
          );
        },
      ),
    );
  }

  /// 错误态：提示信息 + 重试。
  Widget _buildError() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('加载失败：$_error', textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  /// 空态：可下拉刷新，避免短内容无法触发 RefreshIndicator。
  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('还没有人来访'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 格式化访客时间（毫秒时间戳）：今天显示 HH:mm，否则 MM-dd。
/// 与会话列表 / 好友申请的展示约定保持一致。
String _fmtTime(int ts) {
  if (ts <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
