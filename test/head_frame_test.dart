import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnchat/core/models/animated_frames.dart';
import 'package:mnchat/core/models/messages.dart';
import 'package:mnchat/ui/widgets/avatar_view.dart';
import 'package:mnchat/ui/widgets/head_frame.dart';

void main() {
  // 解码静态头像框需要引擎绑定（plain test 里也会调用 instantiateImageCodec）。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('headFrameAsset', () {
    test('静态 id 拼出 webp 资源路径', () {
      expect(headFrameAsset(20201), 'assets/headframes/20201.webp');
      expect(headFrameIsAnimated(20201), isFalse);
    });

    test('动画 id 拼出 webp 资源路径', () {
      const id = 20265;
      expect(headFrameIsAnimated(id), isTrue);
      expect(headFrameAsset(id), 'assets/headframes_anim/$id.webp');
    });

    test('资源随包提供（抽查若干 id 存在）', () {
      for (final id in [1, 20201, 33298, 33302]) {
        expect(
          File(headFrameAsset(id)).existsSync(),
          isTrue,
          reason: '缺少头像框资源 $id',
        );
      }
    });

    test('全部动画头像框资源随包提供且非空', () {
      expect(kAnimatedFrameIds, isNotEmpty);
      for (final id in kAnimatedFrameIds) {
        final file = File(headFrameAsset(id));
        expect(file.existsSync(), isTrue, reason: '缺少动画头像框 $id');
        expect(file.lengthSync(), greaterThan(0), reason: '动画头像框 $id 为空');
      }
    });

    test('每个动画 id 均有对应静态头像框（WebP 128x128、非空）', () async {
      for (final id in kAnimatedFrameIds) {
        final file = File(headFrameStaticAsset(id));
        expect(file.existsSync(), isTrue, reason: '缺少静态头像框 $id');
        final bytes = file.readAsBytesSync();
        expect(bytes.length, greaterThan(1000), reason: '静态头像框 $id 疑似空白');
        // 真实解码后再断言尺寸，不依赖容器格式（资源已由 PNG 迁移为 WebP）。
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 128, reason: '静态头像框 $id 宽度非 128');
        expect(image.height, 128, reason: '静态头像框 $id 高度非 128');
        image.dispose();
        codec.dispose();
      }
    });

    test('此前缺失静态图的 6 个动画 id 现已补齐', () {
      for (final id in [20265, 20267, 20279, 20280, 20281, 20290]) {
        expect(
          File(headFrameStaticAsset(id)).existsSync(),
          isTrue,
          reason: '缺少静态头像框 $id',
        );
      }
    });
  });

  group('HeadFrameOverlay', () {
    testWidgets('无框 id 不渲染图像层', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HeadFrameOverlay(frameId: null, size: 48)),
        ),
      );
      expect(find.byType(Image), findsNothing);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HeadFrameOverlay(frameId: 0, size: 48)),
        ),
      );
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('有效 id 渲染图像层', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HeadFrameOverlay(frameId: 20201, size: 48)),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('动画 id 解码为多帧（引擎支持动画 WebP）', (tester) async {
      const id = 20265;
      final data = await rootBundle.load(headFrameAsset(id));
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      expect(codec.frameCount, greaterThan(1));
      codec.dispose();
    });

    testWidgets('动画框铺满画布（防 AABB 退化缩水/偏移）', (tester) async {
      // 这些 id 在早期按 AABB 裁剪时内容只占画布 ~42%~55%，是回归重点。
      // toByteData 需要真实异步，必须放在 runAsync 内。
      await tester.runAsync(() async {
        for (final id in [33181, 33283, 33244, 20265]) {
          final data = await rootBundle.load(headFrameAsset(id));
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          final image = (await codec.getNextFrame()).image;
          final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (rgba!.getUint8((y * image.width + x) * 4 + 3) > 8) {
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
              }
            }
          }
          expect(maxX - minX, greaterThan(100), reason: '头像框 $id 横向未铺满画布');
          expect(maxY - minY, greaterThan(100), reason: '头像框 $id 纵向未铺满画布');
          image.dispose();
          codec.dispose();
        }
      });
    });
  });

  group('头像框槽位比例', () {
    test('kHeadFrameAvatarInset 取官方 70:92 ≈ 0.76', () {
      expect(kHeadFrameAvatarInset, 0.76);
      // 槽位 = 头像本体 / 0.76，即框盒相对头像放大到 ≈1.316x。
      expect(headFrameSlotSize(24), closeTo(24 * 2 / 0.76, 1e-9));
      expect(headFrameSlotSize(18), closeTo(18 * 2 / 0.76, 1e-9));
    });
  });

  group('AvatarView 头像框包围头像', () {
    // radius 24 时：头像本体 24 * 2 = 48，槽位 48 / 0.76 ≈ 63.158。
    const avatarSide = 24.0 * 2;
    const slotSide = avatarSide / kHeadFrameAvatarInset;

    Future<void> pumpAvatar(
      WidgetTester tester, {
      int? frameId,
      ChatSessionType? type,
    }) {
      return tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Center(
              child: AvatarView(
                frameId: frameId,
                radius: 24,
                name: 'ab',
                type: type,
              ),
            ),
          ),
        ),
      );
    }

    void expectSquare(Size size, double side) {
      expect(size.width, closeTo(side, 1e-9));
      expect(size.height, closeTo(side, 1e-9));
    }

    testWidgets('有框：头像保持 radius*2，槽位放大到 1/0.76，框铺满槽位', (tester) async {
      await pumpAvatar(tester, frameId: 20201);

      // 槽位变大：24 * 2 / 0.76 ≈ 63.158，外圈不再被挤进头像内部。
      expectSquare(tester.getSize(find.byType(AvatarView)), slotSide);
      // 头像框铺满整个槽位，不被内缩/裁剪。
      expectSquare(tester.getSize(find.byType(HeadFrameOverlay)), slotSide);
      // 头像本体保持原尺寸：24 * 2 = 48，不再缩到 76%。
      expect(
        tester.getSize(find.byKey(avatarViewAvatarBoxKey)),
        const Size(avatarSide, avatarSide),
      );
      // 头像与框保持同心（默认测试画布 800×600）。
      expect(
        tester.getCenter(find.byKey(avatarViewAvatarBoxKey)),
        const Offset(400, 300),
      );
      expect(
        tester.getCenter(find.byType(HeadFrameOverlay)),
        const Offset(400, 300),
      );
    });

    testWidgets('无框：头像 48 居中，外框与有框时完全一致', (tester) async {
      await pumpAvatar(tester);

      expectSquare(tester.getSize(find.byType(AvatarView)), slotSide);
      expect(find.byType(HeadFrameOverlay), findsNothing);
      expect(
        tester.getSize(find.byKey(avatarViewAvatarBoxKey)),
        const Size(avatarSide, avatarSide),
      );
      expect(
        tester.getSize(
          find.descendant(
            of: find.byType(AvatarView),
            matching: find.byType(Container),
          ),
        ),
        const Size(avatarSide, avatarSide),
      );
      expect(
        tester.getCenter(find.byKey(avatarViewAvatarBoxKey)),
        const Offset(400, 300),
      );
    });

    testWidgets('有框与无框的外框尺寸完全一致（列表行高不抖动）', (tester) async {
      await pumpAvatar(tester, frameId: 20201);
      final framedSize = tester.getSize(find.byType(AvatarView));

      await pumpAvatar(tester);
      final unframedSize = tester.getSize(find.byType(AvatarView));

      expect(framedSize, unframedSize);
      expectSquare(framedSize, slotSide);
    });

    testWidgets('群组即使带框 id 也不叠加框，但几何与无框一致', (tester) async {
      await pumpAvatar(
        tester,
        frameId: 20201,
        type: ChatSessionType.group,
      );

      expectSquare(tester.getSize(find.byType(AvatarView)), slotSide);
      expect(find.byType(HeadFrameOverlay), findsNothing);
      // 群头像本体仍为 48，不再出现「群头像被内缩」。
      expect(
        tester.getSize(find.byKey(avatarViewAvatarBoxKey)),
        const Size(avatarSide, avatarSide),
      );
      expect(
        tester.getSize(
          find.descendant(
            of: find.byType(AvatarView),
            matching: find.byType(Container),
          ),
        ),
        const Size(avatarSide, avatarSide),
      );
    });
  });

  // 回归：ListTile 会给 leading/trailing/secondary 加高度上限
  // `(isDense ? 48 : 56) + visualDensity.dy`（宽度是松约束）。曾用 OverflowBox
  // 绕过，结果其自身尺寸膨胀到父约束最大宽度，触发
  // 「Leading widget consumes the entire tile width」运行时断言崩溃。
  // 以下用例在真实行结构（ListTile + 有框 AvatarView）下锁死该行为。
  group('ListTile 承载带头像框头像（运行时布局约束）', () {
    const radius = 24.0;
    const avatarSide = radius * 2;
    const slotSide = avatarSide / kHeadFrameAvatarInset;

    void expectSquare(Size size, double side) {
      expect(size.width, closeTo(side, 1e-6));
      expect(size.height, closeTo(side, 1e-6));
    }

    /// 复刻会话 / 好友 / 访客行的结构：ListTile + 带头像框的 leading。
    Future<void> pumpRow(
      WidgetTester tester, {
      required bool styled,
      required bool withSubtitle,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ListTile(
                    visualDensity: styled ? kAvatarListTileDensity : null,
                    minTileHeight: styled ? slotSide : null,
                    leading: const AvatarView(
                      frameId: 20201,
                      radius: radius,
                      name: 'ab',
                    ),
                    title: const Text('昵称'),
                    subtitle: withSubtitle ? const Text('副标题') : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('带框 leading 不被压扁，且不触发 ListTile 布局断言', (tester) async {
      await pumpRow(tester, styled: true, withSubtitle: true);
      expect(tester.takeException(), isNull);
      expectSquare(tester.getSize(find.byType(AvatarView)), slotSide);
      expectSquare(tester.getSize(find.byType(HeadFrameOverlay)), slotSide);
      expect(
        tester.getSize(find.byKey(avatarViewAvatarBoxKey)),
        const Size(avatarSide, avatarSide),
      );
    });

    testWidgets('单行行（如群成员）同样能容纳槽位', (tester) async {
      await pumpRow(tester, styled: true, withSubtitle: false);
      expect(tester.takeException(), isNull);
      expectSquare(tester.getSize(find.byType(AvatarView)), slotSide);
    });

    testWidgets('去掉 kAvatarListTileDensity 会被钳成非正方形（守护该常量）', (tester) async {
      await pumpRow(tester, styled: false, withSubtitle: true);
      final size = tester.getSize(find.byType(AvatarView));
      expect(size.height, lessThan(slotSide));
      expect(size.width, closeTo(slotSide, 1e-6));
    });
  });
}
