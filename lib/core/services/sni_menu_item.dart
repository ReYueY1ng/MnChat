/// 自研 Linux 托盘（SNI）的菜单项。
class SniMenuItem {
  const SniMenuItem.label(this.id, this.label) : separator = false;

  const SniMenuItem.separator(this.id)
    : label = '',
      separator = true;

  final int id;
  final String label;
  final bool separator;
}
