import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/profile.dart' show PlayerProfile, ProfileClient;
import '../state/providers.dart';
import 'player_home_page.dart';
import 'theme/app_tokens.dart';
import 'widgets/avatar_view.dart';
import 'widgets/head_frame.dart' show kAvatarListTileDensity, headFrameSlotSize;
import 'widgets/rich_text_view.dart';

/// 附近的人（`cmd=get_nearby` / `report_location`，对齐 nearbyfriendserver.lua）。
///
/// 说明：外部客户端没有接入系统定位，需**手动填入经纬度**上报后再查询。
/// 服务端返回 `nearby_users` 是 `<geohash>_<uin>` 字符串，此处本地解码算出距离。
class NearbyPage extends ConsumerStatefulWidget {
  const NearbyPage({super.key});

  @override
  ConsumerState<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyUser {
  final int uin;
  final double? distanceKm;
  const _NearbyUser(this.uin, this.distanceKm);
}

class _NearbyPageState extends ConsumerState<NearbyPage> {
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _loaded = false;
  List<_NearbyUser> _users = const [];

  /// uin → 昵称 / 头像（DIY 头像 URL、角色头像本体 type-id、头像框）；拉不到则空。
  Map<int, PlayerProfile> _profiles = const {};

  bool _allowAdd = false;
  bool _allowAddLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAllowAdd();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  static int _num(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> _loadAllowAdd() async {
    try {
      final friend = ref.read(chatServiceProvider).friend;
      if (friend == null) return;
      final resp = await friend.getAddByNearbyFlag();
      final flag = resp['flag'] ?? resp['data'];
      if (!mounted) return;
      setState(() {
        _allowAdd = flag == 1 || flag == true || flag == '1';
        _allowAddLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _allowAddLoaded = true);
    }
  }

  Future<void> _toggleAllowAdd(bool v) async {
    setState(() => _allowAdd = v);
    try {
      await ref.read(chatServiceProvider).friend?.allowAddByNearby(allow: v);
    } catch (e) {
      _toast('设置失败: $e');
    }
  }

  Future<void> _search() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    if (lat == null || lon == null) {
      _toast('请先填写有效的经纬度');
      return;
    }
    final friend = ref.read(chatServiceProvider).friend;
    if (friend == null) {
      _toast('未登录');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await friend.reportLocation(latitude: lat, longitude: lon);
      final resp = await friend.getNearby(
        page: 1,
        latitude: lat,
        longitude: lon,
      );
      final raw = resp['nearby_users'];
      final out = <_NearbyUser>[];
      if (raw is List) {
        for (final e in raw) {
          final s = '$e';
          final idx = s.lastIndexOf('_');
          if (idx <= 0) continue;
          final uin = _num(s.substring(idx + 1));
          if (uin <= 0) continue;
          final decoded = _geohashDecode(s.substring(0, idx));
          final dist = decoded == null
              ? null
              : _distanceKm(lat, lon, decoded.$1, decoded.$2);
          out.add(_NearbyUser(uin, dist));
        }
      }
      out.sort((a, b) => (a.distanceKm ?? double.infinity).compareTo(
            b.distanceKm ?? double.infinity,
          ));
      // 服务端只回 `<geohash>_<uin>`：昵称与头像（含角色头像本体 / 头像框）
      // 得自己按 uin 批量补一次，否则列表只有迷你号与占位图标。
      Map<int, PlayerProfile> profiles = const {};
      if (out.isNotEmpty) {
        final profileClient = _profileClient();
        if (profileClient != null) {
          try {
            profiles = await profileClient.fetchAvatarProfiles(
              out.map((u) => u.uin).toList(),
            );
          } catch (_) {
            // 资料拉取失败 → 退回迷你号 + 首字占位
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _users = out;
        _profiles = profiles;
        _loaded = true;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
        _loaded = true;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 共享资料客户端（带 30s 缓存）；未登录 / 测试环境读 provider 会抛 → null。
  ProfileClient? _profileClient() {
    try {
      return ref.read(profileClientProvider);
    } catch (_) {
      return null;
    }
  }

  static const String _geoBase32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  /// geohash 解码 → (lat, lon)；非法返回 null。
  static (double, double)? _geohashDecode(String hash) {
    if (hash.isEmpty) return null;
    var even = true;
    var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
    for (final ch in hash.toLowerCase().split('')) {
      final idx = _geoBase32.indexOf(ch);
      if (idx < 0) return null;
      for (var mask = 16; mask != 0; mask >>= 1) {
        final bit = (idx & mask) != 0;
        if (even) {
          final mid = (lonMin + lonMax) / 2;
          if (bit) {
            lonMin = mid;
          } else {
            lonMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if (bit) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        even = !even;
      }
    }
    return ((latMin + latMax) / 2, (lonMin + lonMax) / 2);
  }

  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  String _distText(double? km) {
    if (km == null) return '距离未知';
    if (km < 1) return '${(km * 1000).round()} 米';
    if (km < 10) return '${km.toStringAsFixed(1)} 公里';
    return '${km.round()} 公里';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('附近的人')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            '外部客户端未接入系统定位，请手动填写经纬度后再查询。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '纬度 latitude',
                    hintText: '如 39.9042',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _lonCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '经度 longitude',
                    hintText: '如 116.4074',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _busy ? null : _search,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.near_me_outlined),
            label: const Text('上报位置并查找附近的人'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('允许附近的人加我'),
              subtitle: Text(
                _allowAddLoaded ? '开启后附近的人可搜索到我并加好友' : '读取中…',
              ),
              trailing: Switch(
                value: _allowAdd,
                onChanged: _allowAddLoaded ? _toggleAllowAdd : null,
              ),
            ),
          ),
          const Divider(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                '查询失败：$_error',
                style: TextStyle(color: scheme.error),
              ),
            )
          else if (_loaded && _users.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  '附近没有找到人',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ..._users.map((u) {
              final profile = _profiles[u.uin];
              final nickname = profile?.nickname ?? '';
              final name = nickname.isNotEmpty ? nickname : '${u.uin}';
              return ListTile(
                // 带头像框的槽位高于 ListTile 的 leading 上限（紧凑密度下 48dp），
                // 不抬高纵向密度会被压扁并裁掉框外圈（见 [kAvatarListTileDensity]）。
                visualDensity: kAvatarListTileDensity,
                minTileHeight: headFrameSlotSize(24),
                leading: AvatarView(
                  name: name,
                  avatarUrl: profile?.avatarUrl,
                  radius: 24,
                  headType: profile?.headType,
                  headId: profile?.headId,
                  frameId: profile?.headFrameId,
                ),
                title: RichTextView(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('迷你号 ${u.uin} · ${_distText(u.distanceKm)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerHomePage(targetUin: u.uin),
                  ),
                ),
              );
            }),
          if (_loaded && _users.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '共 ${_users.length} 人（仅显示第 1 页）',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
