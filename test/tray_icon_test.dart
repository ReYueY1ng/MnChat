import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/services/tray_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('托盘图标载荷必须小到能走通 D-Bus', () async {
    final icon = await TrayService.loadIconArgb();

    expect(icon, isNotNull, reason: 'assets/tray_icon.png 必须能解码');
    final (argb, width, height) = icon!;

    expect(width, TrayService.trayIconSize);
    expect(height, TrayService.trayIconSize);
    expect(
      argb.lengthInBytes,
      lessThanOrEqualTo(
        TrayService.trayIconSize * TrayService.trayIconSize * 4,
      ),
      reason: 'IconPixmap 是经 D-Bus 的裸 ARGB；1 MiB 会让宿主 GetAll 超时，'
          '图标拿不到会导致托盘整个不显示',
    );
  });
}
