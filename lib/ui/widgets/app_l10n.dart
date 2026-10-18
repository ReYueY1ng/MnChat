/// 本地化文案访问器（容忍未挂 delegate 的测试环境）。
///
/// 生产路径上 `MaterialApp` 一定装了 `AppLocalizations.delegate`（见 `main.dart`），
/// 但仓库里大量既有 widget 测试直接 pump 裸 `MaterialApp`，而
/// `AppLocalizations.of(context)` 在缺 delegate 时会因非空断言抛错，把不相关的
/// 测试打红。
///
/// 约定：新增 UI 一律用本函数取文案，并在调用点写同义中文回退
/// （`l10nOf(context)?.menuCopy ?? '复制'`）。两处文案必须一致；测试断言覆盖的
/// 是行为，不是字符串本身。
library;

import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// 当前 [AppLocalizations]；未挂 delegate 时返回 null。
AppLocalizations? l10nOf(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations);
