#!/usr/bin/env python3
"""把骰子/猜拳转成动画 webp（结果面必须落在最后一帧）。

这两个 skeleton 只有 **1 根骨骼 + 1 个 RegionAttachment + 1 条 attachment 时间轴**，
没有任何骨架变换或网格 —— 动画纯粹是「图集区域随时间切换」，所以不需要栅格化：
按时间轴逐帧取区域图拼起来即可，与游戏**逐帧一致**（含最后一帧的结果面）。

为什么不用 spine2webp 导这两个：它按 `time = frame / fps`（共 duration*fps 帧）采样，
取不到 t = duration 的**最后一个关键帧** —— 而骰子/猜拳的结果面恰好只出现在那一帧，
于是 6 个 animation 会被导成同一份内容（表现为「互动表情永远是同一个/占位图」）。

用法:
    node dump_timeline.js <包目录> ani_expression_saizi /tmp/saizi.json
    python3 build_interactive_webp.py <包目录> /tmp/saizi.json [输出目录]

输出: `<输出目录>/1_<结果>.webp`（骰子）、`2_<结果>.webp`（猜拳），
默认输出目录就是 `assets/emoticon/anim/`。
"""
import json
import os
import re
import sys

from PIL import Image

DEFAULT_OUT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                 'assets', 'emoticon', 'anim'))

# 素材名前缀：骰子 → 1_<结果>，猜拳 → 2_<结果>（见 core/models/emoji_catalog.dart）
PREFIX = {'saizi': '1', 'caiquan': '2'}
PAD = 2


def parse_atlas(text):
    """atlas 文本 → {区域名: {page,x,y,w,h,orig,offset,rotate}}"""
    regions, page, lines, i = {}, None, text.splitlines(), 0
    while i < len(lines):
        line = lines[i].strip()
        if line.endswith('.png'):
            page = line
            i += 1
            continue
        if line and not line.startswith(('size:', 'format:', 'filter:', 'repeat:')):
            props, j = {}, i + 1
            while j < len(lines) and lines[j].startswith('  '):
                k, _, v = lines[j].strip().partition(':')
                props[k.strip()] = v.strip()
                j += 1
            if 'xy' in props:
                xy = [int(x) for x in props['xy'].split(',')]
                size = [int(x) for x in props['size'].split(',')]
                regions[line] = {
                    'page': page, 'x': xy[0], 'y': xy[1],
                    'w': size[0], 'h': size[1],
                    'orig': [int(x) for x in
                             (props.get('orig') or props['size']).split(',')],
                    'offset': [int(x) for x in
                               (props.get('offset') or '0,0').split(',')],
                    'rotate': props.get('rotate') == 'true',
                }
            i = j
            continue
        i += 1
    return regions


def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        return 2
    pack_dir, timeline_json = sys.argv[1], sys.argv[2]
    out_dir = sys.argv[3] if len(sys.argv) == 4 else DEFAULT_OUT

    tl = json.load(open(timeline_json))
    item = tl['item']
    prefix = next(v for k, v in PREFIX.items() if k in item)

    regions = parse_atlas(open(os.path.join(pack_dir, item + '.atlas')).read())
    pages = {}
    for r in regions.values():
        pages.setdefault(
            r['page'],
            Image.open(os.path.join(pack_dir, r['page'])).convert('RGBA'))

    # 统一画布：所有结果、所有帧用同一套 orig+offset 对齐，避免互相错位。
    used = {name for a in tl['animations'].values() for _, name in a['keys'] if name}
    min_x = min(regions[n]['offset'][0] for n in used)
    min_y = min(regions[n]['offset'][1] for n in used)
    cw = max(regions[n]['offset'][0] + regions[n]['orig'][0] for n in used) - min_x
    ch = max(regions[n]['offset'][1] + regions[n]['orig'][1] for n in used) - min_y

    def frame_for(region_name):
        r = regions[region_name]
        crop = pages[r['page']].crop(
            (r['x'], r['y'], r['x'] + r['w'], r['y'] + r['h']))
        if r['rotate']:
            crop = crop.transpose(Image.ROTATE_90)
        canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
        canvas.paste(crop, (r['offset'][0] - min_x, r['offset'][1] - min_y), crop)
        return canvas

    # 裁到「所有结果的所有帧」的并集包围盒（+PAD）：
    # 单看某一面会把画布缩到那一面的大小，各结果尺寸不一 → 播起来会跳动；
    # 直接用 orig+offset 又会留下大片透明边 → 看起来偏到一角。
    sequences = {}
    for name, anim in sorted(tl['animations'].items()):
        sequences[int(re.sub(r'\D', '', name))] = (
            [frame_for(a) for _, a in anim['keys']],
            [int(round((anim['keys'][i + 1][0] - anim['keys'][i][0]) * 1000))
             for i in range(len(anim['keys']) - 1)],
        )

    box = None
    for frames, _ in sequences.values():
        for f in frames:
            b = f.getbbox()
            if b is None:
                continue
            box = b if box is None else (
                min(box[0], b[0]), min(box[1], b[1]),
                max(box[2], b[2]), max(box[3], b[3]))
    if box is None:
        print(f'{item}: 所有帧都是空的，跳过')
        return 1
    box = (max(0, box[0] - PAD), max(0, box[1] - PAD),
           min(cw, box[2] + PAD), min(ch, box[3] + PAD))

    os.makedirs(out_dir, exist_ok=True)
    for result, (frames, delays) in sorted(sequences.items()):
        delays = delays + [delays[-1] if delays else 100]
        out = os.path.join(out_dir, f'{prefix}_{result}.webp')
        crops = [f.crop(box) for f in frames]
        crops[0].save(out, save_all=True, append_images=crops[1:],
                      duration=delays, loop=0, lossless=True, quality=100,
                      method=6)
        print(f'  {os.path.basename(out)}: {len(crops)} 帧 '
              f'{crops[0].size[0]}x{crops[0].size[1]}, '
              f'{sum(delays)}ms, 末帧={prefix}_{result}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
