/// 邮件中心的导航状态：当前入口/频道、类型筛选、本页已关注的人。
///
/// 从 `_MailPageState` 抽出的纯交互状态（不加载数据、不持客户端）；
/// 页面监听它做重建，数据拉取仍留在页面里。
library;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'mail_page.dart' show MailSelection;

class MailNavigationController extends ChangeNotifier {
  MailNavigationController(MailSelection initial) : _selected = initial;

  MailSelection _selected;
  MailSelection get selected => _selected;

  String _typeFilter = '';
  String get typeFilter => _typeFilter;
  set typeFilter(String value) {
    if (value == _typeFilter) return;
    _typeFilter = value;
    notifyListeners();
  }

  final Set<int> followed = <int>{};

  void select(MailSelection selection) {
    if (selection == _selected) return;
    _selected = selection;
    notifyListeners();
  }

  void markFollowed(int uin) {
    if (followed.add(uin)) notifyListeners();
  }
}
