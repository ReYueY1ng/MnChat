// 由反编译 playercentermedalmanager.lua 生成：勋章 id → 图标名 + 等级边框。
// 图标已由 FGUI 图集 iconsourceachievement 裁剪到 assets/medals/。
library;

/// 勋章图标资源路径：`assets/medals/<iconName>.png`。
String medalIconAsset(String iconName) => 'assets/medals/$iconName.png';

/// 勋章 id → 图标名（AchievementData.icon_Resources）。
const Map<int, String> kMedalIconName = {
  1001: 'cj_bosskiller',
  1002: 'cj_baozangnum',
  1003: 'cj_shengcuntianshu',
  1004: 'cj_jixianbosskiller',
  1005: 'cj_shenmiliwu',
  1006: 'cj_hotmapnum',
  1007: 'cj_jianshangjia',
  1008: 'cj_haoyounum',
  1009: 'cj_fensinum',
  1010: 'cj_dianzan',
  1011: 'cj_jiaohua',
  1012: 'cj_chuchong',
  1013: 'cj_tujiannum',
  1014: 'cj_shouhuonum',
  1015: 'cj_guoshilv',
  1016: 'cj_juesenum',
  1017: 'cj_jueselv',
  1018: 'cj_pifunum',
  1019: 'cj_zuojinum',
  1020: 'cj_avtnum',
  1021: 'cj_shimingzhi',
  1022: 'cj_chixudenglu',
  1024: 'cj_fangzhapian',
  1025: 'cj_mapcreator',
  1026: 'cj_videocreator',
  1027: 'cj_communitystar',
  1028: 'cj_finalists',
  1029: 'cj_gunskin',
  1030: 'cj_yinxiang',
  1031: 'cj_aotudasai',
  1032: 'cj_communitystar',
  1034: 'cj_gunskin',
  1035: 'cj_yinxiang',
  1036: 'cj_aotudasai',
  1037: 'cj_pifunum',
  1038: 'cj_haoyounum',
  1039: 'cj_zuojinum',
  1040: 'cj_dianzan',
  1041: 'cj_avtnum',
};

/// isNew 勋章 id → 按等级(1..5)的徽章图标名（icon_ResourcesOthers）。
const Map<int, List<String>> kMedalLevelIcons = {
  1032: [
    'icon_badge_wood_game_expert',
    'icon_badge_stone_game_expert',
    'icon_badge_iron_game_expert',
    'icon_badge_gold_game_expert',
    'icon_badge_diamond_game_expert',
  ],
  1034: [
    'icon_badge_wood_creative_expert',
    'icon_badge_stone_creative_expert',
    'icon_badge_iron_creative_expert',
    'icon_badge_gold_creative_expert',
    'icon_badge_diamond_creative_expert',
  ],
  1035: [
    'icon_badge_wood_sandbox',
    'icon_badge_stone_sandbox',
    'icon_badge_iron_sandbox',
    'icon_badge_gold_sandbox',
    'icon_badge_diamond_sandbox',
  ],
  1036: [
    'icon_badge_wood_big_star',
    'icon_badge_stone_big_star',
    'icon_badge_iron_big_star',
    'icon_badge_gold_big_star',
    'icon_badge_diamond_big_star',
  ],
  1037: [
    'icon_badge_wood_shapeshifting',
    'icon_badge_stone_shapeshifting',
    'icon_badge_iron_shapeshifting',
    'icon_badge_gold_shapeshifting',
    'icon_badge_diamond_shapeshifting',
  ],
  1038: [
    'icon_badge_wood_shejiao',
    'icon_badge_stone_shejiao',
    'icon_badge_iron_shejiao',
    'icon_badge_gold_shejiao',
    'icon_badge_diamond_shejiao',
  ],
  1039: [
    'icon_badge_wood_xunshou',
    'icon_badge_stone_xunshou',
    'icon_badge_iron_xunshou',
    'icon_badge_gold_xunshou',
    'icon_badge_diamond_xunshou',
  ],
  1040: [
    'icon_badge_wood_jizan',
    'icon_badge_stone_jizan',
    'icon_badge_iron_jizan',
    'icon_badge_gold_jizan',
    'icon_badge_diamond_jizan',
  ],
  1041: [
    'icon_badge_wood_baiban',
    'icon_badge_stone_baiban',
    'icon_badge_iron_baiban',
    'icon_badge_gold_baiban',
    'icon_badge_diamond_baiban',
  ],
  1042: [
    'icon_badge_wood_dianfeng',
    'icon_badge_stone_dianfeng',
    'icon_badge_iron_dianfeng',
    'icon_badge_gold_dianfeng',
    'icon_badge_diamond_dianfeng',
  ],
  1043: [
    'icon_badge_wood_guize',
    'icon_badge_stone_guize',
    'icon_badge_iron_guize',
    'icon_badge_gold_guize',
    'icon_badge_diamond_guize',
  ],
  1044: [
    'icon_badge_wood_zaomeng',
    'icon_badge_stone_zaomeng',
    'icon_badge_iron_zaomeng',
    'icon_badge_gold_zaomeng',
    'icon_badge_diamond_zaomeng',
  ],
  1045: [
    'icon_badge_wood_dianping',
    'icon_badge_stone_dianping',
    'icon_badge_iron_dianping',
    'icon_badge_gold_dianping',
    'icon_badge_diamond_dianping',
  ],
};

/// 等级边框图标名（frame_Resources，level 1..5）。
const List<String> kMedalFrameByLevel = [
  'cj_wood',
  'cj_stone',
  'cj_iron',
  'cj_gold',
  'cj_diamond',
];
