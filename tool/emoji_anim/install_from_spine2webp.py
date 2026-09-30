#!/usr/bin/env python3
"""把 spine2webp 的导出结果按 App 的命名约定装进 assets/emoticon/anim/。

用法:
    spine2webp --dir <游戏 emoji 缓存目录> --out-dir /tmp/emoji_out \
        --fps 30 --lossy --quality 92
    python3 tool/emoji_anim/install_from_spine2webp.py /tmp/emoji_out

命名映射（App 侧见 lib/core/models/emoticon.dart: emojiPackAnimName / emojiAnimAsset）：

    <包ID>/ani_expression_<图ID>_animation.webp  ->  p<包ID>-ani_expression_<图ID>.webp

**骰子/猜拳不在这里**：它们是纯 attachment 时间轴动画，spine2webp 取不到
t = duration 的最后一个关键帧（结果面只在那一帧），会导成 6 份一样的内容。
那两个用 `build_interactive_webp.py` 出图，本脚本会把它们跳过。

包前缀是必须的：不同包有同名图（10006 与 10007 都有 ani_expression_022/025），
不带前缀会互相覆盖，表现为「这个表情显示成了别的表情」。
"""
import os
import re
import shutil
import sys

DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                    'assets', 'emoticon', 'anim')
# 严格以 `_animation` 结尾：少数 skeleton 带多条动画
# （如 10007/ani_expression_002 还有 animation2），游戏播的是 animation。
EXPR = re.compile(r'^ani_expression_(.+)_animation\.webp$')
INTERACTIVE = ('saizi', 'caiquan')


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = sys.argv[1]
    dest = os.path.normpath(DEST)

    keep = {'README.md'}
    # 骰子/猜拳由 build_interactive_webp.py 产出，别被这里删掉。
    keep.update(f'{p}_{n}.webp' for p in '12' for n in range(1, 7))
    for name in os.listdir(dest):
        if name not in keep:
            path = os.path.join(dest, name)
            shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)

    written = {}
    skipped = []
    for pack in sorted(os.listdir(src)):
        packdir = os.path.join(src, pack)
        if not os.path.isdir(packdir):
            continue
        for name in sorted(os.listdir(packdir)):
            if any(i in name for i in INTERACTIVE):
                skipped.append(f'{pack}/{name}')
                continue
            m_expr = EXPR.match(name)
            if not m_expr:
                print(f'  跳过 {pack}/{name}')
                continue
            out = f'p{pack}-ani_expression_{m_expr.group(1)}.webp'
            if out in written:
                print(f'  警告：{out} 被 {pack}/{name} 与 {written[out]} 同时占用')
            written[out] = f'{pack}/{name}'
            shutil.copyfile(os.path.join(packdir, name), os.path.join(dest, out))

    print(f'装入 {len(written)} 个表情包动图'
          + (f'；跳过 {len(skipped)} 个互动表情（由 build_interactive_webp.py 产出）'
             if skipped else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
