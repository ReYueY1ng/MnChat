/// 表情系统模型与纯解析 —— 对齐反编译 `emojisysdatamanager.lua`。
///
/// 三块内容：
/// 1. **代码流**（`emoji_defines`，emojisysdatamanager.lua:239）：
///    - 旧表情（包 ID 1/3，走内置图集）→ `#A<包ID><两位图ID>`，如 `#A106`
///      （`static_pic_fmt = "#A%s%s"`）；
///    - 新表情（远程表情包）→ `[mdemo]<Type>&<包ID>&<图ID>[>动画序号][/mdemo]`
///      （`dynamic_fill_fmt`，`GetEmojiLabel` 决定用哪种）。
/// 2. **表情包配置**：远程 visual-cfg `emoji_system` 的 `emojis` 数组，每项含
///    `ID / Type(1=静态 2=动态) / GetType / emoji_cfgs_url / emoji_files_url`。
/// 3. **包内图列表**：下载 `emoji_cfgs_url` 得到的 JSON（`infos.list`）形如
///    `{ID:[图id...], icon:[图标文件名...], anis:{...}}`（`ParseEmojiCfgs`）。
///
/// 内置的 1/3 号包定义直接照抄反编译 `chatconfig.lua` 的 `ChatConfig.emojis`
/// （1=熊孩子 18 个、3=花小楼 18 个），不依赖网络即可展示。
library;


/// 表情包类型（`Emoji_Type`，emojisysdatamanager.lua:6）。
class EmojiPackType {
  static const int static = 1;
  static const int dynamic = 2;

  static bool isDynamic(int t) => t == dynamic;
}

/// 获取方式（`Emoji_Get_Type`，emojisysdatamanager.lua:10）。
class EmojiGetType {
  static const int defaultType = 0;
  static const int free = 1;
  static const int buy = 2;
  static const int vip = 3;
  static const int activity = 4;
  static const int prop = 5;
}

/// 单个表情项（包内一张图）。
class EmojiPic {
  /// 所属包 ID。
  final String packId;

  /// 图 ID（`infos.list` 的 `ID[i]`，如 `ani_expression_saizi`、`06`）。
  final String picId;

  /// 图标文件名（`infos.list` 的 `icon[i]`；动态包不带扩展名）。
  final String icon;

  /// 动画名列表（`infos.list` 的 `anis[图ID]`）。
  ///
  /// 只对动态包（spine）有值：骰子 6 个、猜拳 3 个，**序号与结果一一对应**
  /// （`GetEmojiLabel` 把结果拼成 `图ID>序号`，`SetItemIcon` 取 `anis[序号]`
  /// 作为 spine 动画名）。
  final List<String> anis;

  const EmojiPic({
    required this.packId,
    required this.picId,
    this.icon = '',
    this.anis = const [],
  });

  /// 去掉扩展名的图标名（内置图集 sprite 名 / 动图素材名，如 `hua_qinqin`）。
  String get iconName {
    final i = icon.lastIndexOf('.');
    return i > 0 ? icon.substring(0, i) : icon;
  }
}

/// 一个表情包。
class EmojiPack {
  /// 包 ID（字符串，兼容数字/字符串两种来源）。
  final String id;

  /// `EmojiPackType`。
  final int type;

  /// `EmojiGetType`。
  final int getType;

  /// 包内图列表配置的下载地址（`emoji_cfgs_url`）。
  final String cfgsUrl;

  /// 图 id → 素材压缩包地址（`emoji_files_url`）。
  final Map<String, String> filesUrl;

  /// 包标题（内置包有；远程包可能没有）。
  final String title;

  const EmojiPack({
    required this.id,
    this.type = EmojiPackType.static,
    this.getType = EmojiGetType.defaultType,
    this.cfgsUrl = '',
    this.filesUrl = const {},
    this.title = '',
  });

  /// 是否内置旧包（ID 1/3）—— 用本地图集渲染，不走下载（`IsOldEmoji`）。
  bool get isLegacy => id == '1' || id == '3';

  bool get isDynamic => EmojiPackType.isDynamic(type);

  /// 展示名（无标题则回退「表情包 + ID」）。
  String get displayTitle => title.isNotEmpty ? title : '表情包 $id';
}

/// 从「包 + 图」生成发送用的表情代码。
///
/// 对齐 `GetEmojiLabel`：旧包 → `#A<id><picId>`；其余 → `[mdemo]<Type>&<id>&<picId>[/mdemo]`。
/// [aniIndex] 为动态表情随机动画序号（有则拼 `>序号`）。
String emojiSendCode(EmojiPack pack, EmojiPic pic, {int? aniIndex}) {
  if (pack.isLegacy) return '#A${pack.id}${pic.picId}';
  final picId = aniIndex != null ? '${pic.picId}>$aniIndex' : pic.picId;
  return '[mdemo]${pack.type}&${pack.id}&$picId[/mdemo]';
}

/// 文本里的一个表情引用。
class EmojiCodeRef {
  final String packId;
  final String picId;
  final int type;

  /// `图ID>动画` 里 `>` 后面那段（`GetEmojiLabel` 拼的序号）。
  ///
  /// 互动表情（骰子/猜拳）里它就是**结果**（1..6 / 1..3）；
  /// 普通表情则是配置里 `anis` 的序号，用来选具体动画。
  final String? anim;

  /// 动态表情（`[mdemo]` 形式）。
  final bool fromDynamic;

  /// 原始匹配文本。
  final String raw;

  const EmojiCodeRef({
    required this.packId,
    required this.picId,
    required this.type,
    required this.fromDynamic,
    required this.raw,
    this.anim,
  });
}

/// 旧表情代码正则：`#A(\d+)(\d\d)`（贪婪匹配后回退两位，见 `static_match_fmt`）。
final RegExp _kStaticCodeRe = RegExp(r'#A(\d+)(\d\d)');

/// 动态表情代码正则：`[mdemo]<1|2>&<包ID>&<图ID>[>动画][/mdemo]`
/// （`dynamic_match_fmt`）。
final RegExp _kDynamicCodeRe = RegExp(
  r'\[mdemo\]([12])&([^&\s]+)&([^\]\s]+)\[/mdemo\]',
);

/// 扫描文本里的全部表情引用（旧 + 动态），按出现顺序返回。
List<EmojiCodeRef> parseEmojiCodeRefs(String text) {
  if (text.isEmpty) return const [];
  final out = <EmojiCodeRef>[];
  final occupied = <(int, int)>[]; // [start, end)

  bool overlaps(int s, int e) =>
      occupied.any((r) => s < r.$2 && e > r.$1);

  for (final m in _kDynamicCodeRe.allMatches(text)) {
    final picRaw = m.group(3)!;
    final gt = picRaw.indexOf('>');
    out.add(
      EmojiCodeRef(
        packId: m.group(2)!,
        picId: gt >= 0 ? picRaw.substring(0, gt) : picRaw,
        type: int.tryParse(m.group(1)!) ?? EmojiPackType.static,
        fromDynamic: true,
        raw: m.group(0)!,
        anim: gt >= 0 ? picRaw.substring(gt + 1) : null,
      ),
    );
    occupied.add((m.start, m.end));
  }
  for (final m in _kStaticCodeRe.allMatches(text)) {
    if (overlaps(m.start, m.end)) continue;
    out.add(
      EmojiCodeRef(
        packId: m.group(1)!,
        picId: m.group(2)!,
        type: EmojiPackType.static,
        fromDynamic: false,
        raw: m.group(0)!,
      ),
    );
  }
  return out;
}

/// 解析远程 visual-cfg `emoji_system` 的文本 → 包列表。
///
/// 兼容 Lua table 字面量与 JSON（走项目现有 `decodeHttpResponse`）。
/// 缺 `ID` 的项跳过；`emoji_files_url` 的键统一转字符串。
List<EmojiPack> parseEmojiSystemConfig(Object? decoded) {
  final root = _asMap(decoded);
  if (root == null) return const [];
  final emojis = root['emojis'];
  if (emojis is! List) return const [];
  final out = <EmojiPack>[];
  for (final e in emojis) {
    final m = _asMap(e);
    if (m == null) continue;
    final idRaw = m['ID'] ?? m['id'];
    final id = idRaw?.toString() ?? '';
    if (id.isEmpty) continue;
    final typeRaw = m['Type'] ?? m['type'];
    out.add(
      EmojiPack(
        id: id,
        type: typeRaw is num
            ? typeRaw.toInt()
            : int.tryParse('$typeRaw') ?? EmojiPackType.static,
        getType: _asInt(m['GetType'] ?? m['get_type']),
        cfgsUrl: (m['emoji_cfgs_url'] ?? '').toString(),
        filesUrl: _toStringMap(m['emoji_files_url']),
        // 线上配置的包名在 `Name`（如「拾之蜜语」「花小楼」）；兼容 sTitle/title。
        title: (m['Name'] ?? m['sTitle'] ?? m['title'] ?? '').toString(),
      ),
    );
  }
  return out;
}

/// 解析某个包的 `infos.list`（JSON/LuaTable）→ 包内图列表。
///
/// 结构：`{ID:[图id...], icon:[文件名...], anis:{图id:[动画名...]}}`
/// （`ParseEmojiCfgs`）。`icon` 缺项时留空（展示时回退文字）。
List<EmojiPic> parsePackInfosList(String packId, Object? decoded) {
  final root = _asMap(decoded);
  if (root == null) return const [];
  final ids = root['ID'] ?? root['id'];
  if (ids is! List) return const [];
  final icons = root['icon'];
  final anis = _asMap(root['anis']);
  final out = <EmojiPic>[];
  for (var i = 0; i < ids.length; i++) {
    final picId = ids[i]?.toString() ?? '';
    if (picId.isEmpty) continue;
    final icon = (icons is List && i < icons.length)
        ? (icons[i]?.toString() ?? '')
        : '';
    final aniList = <String>[];
    final rawAni = anis?[picId];
    if (rawAni is List) {
      for (final a in rawAni) {
        final name = a?.toString() ?? '';
        if (name.isNotEmpty) aniList.add(name);
      }
    }
    out.add(
      EmojiPic(packId: packId, picId: picId, icon: icon, anis: aniList),
    );
  }
  return out;
}

Map<String, Object?>? _asMap(Object? v) {
  if (v is Map) {
    return {for (final e in v.entries) '${e.key}': e.value};
  }
  return null;
}

int _asInt(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

/// 把可能带 int 键的 map 统一成 String→String（非字符串值跳过）。
Map<String, String> _toStringMap(Object? v) {
  if (v is! Map) return const {};
  final out = <String, String>{};
  v.forEach((k, val) {
    if (val is String && val.isNotEmpty) out['$k'] = val;
  });
  return out;
}

/// 内置旧表情包（1=熊孩子 / 3=花小楼），照抄 `chatconfig.lua` 的 `emojis`。
/// 这两个包不依赖网络配置与下载，用本地图集（pack 1）或近似 Unicode（pack 3）渲染。
const List<EmojiPack> kBuiltinEmojiPacks = [
  EmojiPack(id: '1', title: '熊孩子'),
  EmojiPack(id: '3', title: '花小楼', getType: EmojiGetType.vip),
];

/// 内置旧表情包的图列表：包 ID → 图列表（顺序与 `chatconfig.lua` 一致）。
const Map<String, List<EmojiPic>> kBuiltinPackPics = {
  '1': [
    EmojiPic(packId: '1', picId: '06', icon: 'qinqin.png'),
    EmojiPic(packId: '1', picId: '01', icon: 'xieyanxiao.png'),
    EmojiPic(packId: '1', picId: '04', icon: 'xianqi.png'),
    EmojiPic(packId: '1', picId: '02', icon: 'baimu.png'),
    EmojiPic(packId: '1', picId: '03', icon: 'shengqi.png'),
    EmojiPic(packId: '1', picId: '05', icon: 'daku.png'),
    EmojiPic(packId: '1', picId: '07', icon: 'xihuan.png'),
    EmojiPic(packId: '1', picId: '08', icon: 'wabikong.png'),
    EmojiPic(packId: '1', picId: '09', icon: 'dianzan.png'),
    EmojiPic(packId: '1', picId: '10', icon: 'haixiu.png'),
    EmojiPic(packId: '1', picId: '11', icon: 'liulei.png'),
    EmojiPic(packId: '1', picId: '12', icon: 'keai.png'),
    EmojiPic(packId: '1', picId: '13', icon: 'shouqibao.png'),
    EmojiPic(packId: '1', picId: '14', icon: 'kun.png'),
    EmojiPic(packId: '1', picId: '15', icon: 'jingya.png'),
    EmojiPic(packId: '1', picId: '16', icon: 'yun.png'),
    EmojiPic(packId: '1', picId: '17', icon: 'shaojiao.png'),
    EmojiPic(packId: '1', picId: '18', icon: 'bye.png'),
  ],
  '3': [
    EmojiPic(packId: '3', picId: '06', icon: 'hua_qinqin.png'),
    EmojiPic(packId: '3', picId: '01', icon: 'hua_xieyanxiao.png'),
    EmojiPic(packId: '3', picId: '04', icon: 'hua_xianqi.png'),
    EmojiPic(packId: '3', picId: '02', icon: 'hua_baimu.png'),
    EmojiPic(packId: '3', picId: '03', icon: 'hua_shengqi.png'),
    EmojiPic(packId: '3', picId: '05', icon: 'hua_daku.png'),
    EmojiPic(packId: '3', picId: '07', icon: 'hua_xihuan.png'),
    EmojiPic(packId: '3', picId: '08', icon: 'hua_wabikong.png'),
    EmojiPic(packId: '3', picId: '09', icon: 'hua_dianzan.png'),
    EmojiPic(packId: '3', picId: '10', icon: 'hua_haixiu.png'),
    EmojiPic(packId: '3', picId: '11', icon: 'hua_liulei.png'),
    EmojiPic(packId: '3', picId: '12', icon: 'hua_keai.png'),
    EmojiPic(packId: '3', picId: '13', icon: 'hua_shouqibao.png'),
    EmojiPic(packId: '3', picId: '14', icon: 'hua_kun.png'),
    EmojiPic(packId: '3', picId: '15', icon: 'hua_jingya.png'),
    EmojiPic(packId: '3', picId: '16', icon: 'hua_yun.png'),
    EmojiPic(packId: '3', picId: '17', icon: 'hua_shaojiao.png'),
    EmojiPic(packId: '3', picId: '18', icon: 'hua_bye.png'),
  ],
};

// ── 互动表情（chatconfig.lua 的 `ChatEmojiCfg[3]`「动态表情」）──────────────────
//
// 骰子 / 猜拳：点按后**随机**得到结果，并把结果编码进消息（`@IMFC&<序号>_<结果>`）。
// 发送（`EmojiBtnTemplate_StructureSendText`）：
//   result = random(1..mod); interCode = code .. "_" .. result
//   消息文本 = JSON{content: 低版本占位文案, extend_data: interCode}
// 接收（`DeCodeIMFCMsg` + `SplitenterCode`）：从 parsKey / extend_data.interCode
// 取出 `@IMFC&<序号>_<结果>`，再按 `<序号>_<结果>` 取图集 sprite。
// 图集 `emoticon.xml` 里 1_1..1_6=骰子 1..6、2_1..2_3=布/剪刀/石头（2_0 是封面）。

/// 互动表情前缀（`ChatEmojiCfg[3].prefix`）。
const String kImfcPrefix = '@IMFC&';

/// 互动表情在消息文本里的分隔标记（`ChatEmojiCfg[3].parsKey`）。
const String kImfcParsKey = '&IM&F&C';

/// 低版本客户端看到的占位文案（`GetS(190014)`）。
const String kImfcFallbackText = '【版本过低，请前往升级】';

/// 一个互动表情（骰子 / 猜拳）。
class ImfcEmoji {
  /// 序号（`@IMFC&<index>`）：1=骰子 2=猜拳。
  final int index;

  /// 结果种类数（`mod`）：骰子 6、猜拳 3。
  final int mod;

  /// 选择器图标（图集 sprite 名）：骰子 `1_1`、猜拳 `2_0`（三种手势的合集图）。
  final String icon;

  final String title;

  const ImfcEmoji({
    required this.index,
    required this.mod,
    required this.icon,
    required this.title,
  });
}

/// 内置互动表情（照抄 `chatconfig.lua` 的 `emojis[3]`）。
const List<ImfcEmoji> kImfcEmojis = [
  ImfcEmoji(index: 1, mod: 6, icon: '1_1', title: '骰子'),
  ImfcEmoji(index: 2, mod: 3, icon: '2_0', title: '猜拳'),
];

/// 一次互动表情的结果。
class ImfcRef {
  /// 序号（1=骰子 2=猜拳）。
  final int index;

  /// 结果（1 起）。
  final int result;

  const ImfcRef({required this.index, required this.result});

  /// 图集 sprite 名：`<序号>_<结果>`（如 `1_3` 骰子 3 点、`2_2` 剪刀）。
  String get sprite => '${index}_$result';
}

/// 组装互动表情的 interCode（`@IMFC&<index>_<result>`）。
String imfcInterCode(int index, int result) => '$kImfcPrefix${index}_$result';

/// 组装互动表情的消息文本：`<低版本文案>&IM&F&C@IMFC&<序号>_<结果>`。
///
/// 对齐反编译 `ChatHelper:DoSendRoomChat` / `ChatViewCtrl`：
/// `realSendContent = new_datas.content .. ChatEmojiCfg[3].parsKey .. interCode`
/// —— 真身放在 parsKey 之后，文本给低版本客户端看。
/// 我们早期发的是 JSON 信封，游戏端会当成普通文本原样显示，所以改回这个格式。
String imfcMessageText(int index, int result) =>
    '$kImfcFallbackText$kImfcParsKey${imfcInterCode(index, result)}';

final RegExp _kImfcRe = RegExp(r'@IMFC&(\d+)_(\d+)');

/// 从文本 / interCode 里解析互动表情结果；没有则 null。
///
/// 兼容三种形态：裸 `@IMFC&1_3`、`<正文>&IM&F&C@IMFC&1_3`（parsKey 拼接）、
/// 以及整段 JSON 文本 `{"content":"...","extend_data":"@IMFC&1_3"}`。
ImfcRef? parseImfc(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final m = _kImfcRe.firstMatch(raw);
  if (m == null) return null;
  final index = int.tryParse(m.group(1)!);
  final result = int.tryParse(m.group(2)!);
  if (index == null || result == null || index <= 0 || result <= 0) return null;
  return ImfcRef(index: index, result: result);
}

/// 动态表情动画素材目录（spine 不能商用，外部转成 webp 动图后放进来）。
///
/// 命名：
/// - 互动表情（骰子/猜拳）：`<序号>_<结果>.webp`，如 `1_3.webp`；
/// - 表情包内表情：`p<包ID>-<图ID>.webp`，如 `p10006-ani_expression_022.webp`
///   —— **必须带包 ID**：不同包会有同名图（真实数据里 `10006` 与 `10007` 都有
///   `ani_expression_022` / `ani_expression_025`），只用图名会互相覆盖，
///   表现为「这个表情显示成了别的表情」。
///
/// 注意：Flutter **不会**递归打包子目录，所以这里保持扁平命名。
const String kEmojiAnimDir = 'assets/emoticon/anim/';

/// 动态素材路径：`assets/emoticon/anim/<name>.webp`。
String emojiAnimAsset(String name) => '$kEmojiAnimDir$name.webp';

/// 表情包内某个表情的动图素材名（带包 ID，避免跨包同名互相覆盖）。
String emojiPackAnimName(String packId, String icon) => 'p$packId-$icon';

/// 表情包里的两个「互动表情」：图 ID → (内置素材前缀, 结果种类数)。
///
/// 它们不是普通表情图，而是 `ani_expression_saizi` / `ani_expression_caiquan`
/// 这两条 spine 骨架（骰子 6 面、猜拳 3 手，就是 `amis` 里的动画列表）。
/// 游戏把结果拼成 **`图ID>序号`**（`GetEmojiLabel`），序号即结果，
/// 对应内置互动素材 `1_<结果>` / `2_<结果>`（见 assets/emoticon/anim/README.md）。
const Map<String, (String, int)> kInteractivePics = {
  'ani_expression_saizi': ('1', 6),
  'ani_expression_caiquan': ('2', 3),
};

/// 表情包图 ID（可带 `>序号`）→ 内置互动素材名；不是互动表情则返回 null。
///
/// 真实收到的 interCode 形如
/// `[mdemo]2&10006&ani_expression_saizi>5[/mdemo]` —— 没有这张「图」，
/// 必须映射到 `1_5.webp`，否则会退化成灰色占位图标。
/// 面板里的包内图标不带 `>序号`，取第一个结果当图标。
String? interactiveAnimName(String picId, {String? anim}) {
  final entry = kInteractivePics[picId];
  if (entry == null) return null;
  final (prefix, count) = entry;
  final n = int.tryParse(anim ?? '') ?? 1;
  return '${prefix}_${n >= 1 && n <= count ? n : 1}';
}

/// 收到动态表情时游戏塞进 `text` 的低版本提示文案（`GetS(210001)`）。
///
/// 真正的表情在 `extend_data.interCode` 里；万一解不出来（老数据 / 离线历史
/// 只有三元组 / 素材缺失），不要把这句提示当成正文显示给用户。
const String kDynamicEmojiHintText = '【您收到一条动态表情，请升级到最新版本查看】';

/// 文本是否是「动态表情的低版本提示」。
bool isDynamicEmojiHint(String? text) =>
    text != null && text.trim() == kDynamicEmojiHintText;

/// 互动表情的近似 Unicode（图集不可用时兜底展示）。
String imfcUnicode(ImfcRef ref) {
  if (ref.index == 1) {
    // 骰子 1..6 → ⚀⚁⚂⚃⚄⚅
    if (ref.result >= 1 && ref.result <= 6) {
      return String.fromCharCode(0x2680 + ref.result - 1);
    }
    return '🎲';
  }
  if (ref.index == 2) {
    // 1=布 2=剪刀 3=石头
    return switch (ref.result) {
      1 => '✋',
      2 => '✌️',
      3 => '✊',
      _ => '✊',
    };
  }
  return '❓';
}
