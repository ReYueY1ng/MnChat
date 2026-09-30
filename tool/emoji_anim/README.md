# 动态表情动图转换（spine 3.8 → 动画 webp）

把游戏运行时的表情缓存（`data/http/emoji/<包ID>/`，Spine **3.8.99** 骨架）渲成动画
webp，产物放进 `assets/emoticon/anim/`（命名约定见该目录的 README）。

**spine 运行时不能商用**，所以只在**开发期**用它出图，产物随包发布，运行时本体
**不进 App、也不 vendor 进本仓库**（`pubspec.yaml` 里只有图片资源）。

## 渲染器：`spine3.8-to-webp`（官方 spine-cpp + libwebp）

用外部的 `spine2webp`（基于官方 **spine-cpp 3.8** 的 CPU 光栅化器，支持
`SkeletonClipping` / 混合模式 / 变形时间轴 / 预乘 alpha / 超采样）：

```sh
SPINE2WEBP=/home/<you>/spine3.8-to-webp/build/spine2webp

# 1) 表情包内表情（mesh 绑定）：一次导出全部包
#    （<包ID>/<图ID>_<动画名>.webp，保留包目录结构）
"$SPINE2WEBP" --dir <游戏 emoji 缓存根目录> --out-dir /tmp/emoji_out \
    --fps 30 --lossy --quality 92
python3 tool/emoji_anim/install_from_spine2webp.py /tmp/emoji_out

# 2) 骰子/猜拳（纯 attachment 时间轴）：spine2webp 导不了，见下节
P=<游戏 emoji 缓存根目录>/10006
for item in ani_expression_saizi ani_expression_caiquan; do
  node tool/emoji_anim/dump_timeline.js "$P" $item /tmp/$item.json
  python3 tool/emoji_anim/build_interactive_webp.py "$P" /tmp/$item.json
done
```

要用无损画质就把 `--lossy --quality 92` 换成 `--lossless`（体积约 15MB → 8.4MB 的差别）。

### 骰子/猜拳为什么不能用 `spine2webp`

它们是 **1 根骨骼 + 1 个 RegionAttachment + 1 条 attachment 时间轴**，动画就是
「图集区域每 0.1s 换一面」，而**结果面只出现在 t = duration 的最后一个关键帧**。
`spine2webp` 的采样是 `time = frame / fps`（共 `duration*fps` 帧），取不到那个时刻
（试过 `--frames duration*fps+1`、`--no-loop` 等组合，最后一个关键帧仍然不生效），
结果是 6 个 animation 被导成**同一份内容** —— 表现就是「互动表情永远是同一个占位图」。

`build_interactive_webp.py` 直接按时间轴取区域图拼帧（没有任何骨架变换/网格要算），
结果与游戏逐帧一致，最后一帧就是结果面。

### 为什么必须用官方运行时，而不是自己渲

这些表情是**带权重的 mesh 绑定**（最多 164 根骨骼、75 个 slot），而且带
**clipping 遮罩**。两个曾经踩过的坑：

- 3.8 的 `spine-canvas` `SkeletonRenderer` 默认 `drawImages` **只画
  `RegionAttachment`**，mesh 直接跳过 → 画出来是残缺的；打开
  `triangleRendering` 会画 mesh，但它**完全忽略 `ClippingAttachment`** →
  本该被裁掉的部分照画，表现就是**「超出轮廓的碎块 / 灰色三角」**
  （典型例子 `10007/ani_expression_003`）。
- 用 canvas 的 `drawImage` + `clip()` 补裁剪也不够：整页贴图被变换后绘制，
  三角形裁剪区里会带进**相邻图素的线性插值**，表现为角色边缘多出细碎的浅色描边。

官方 `spine-cpp` 的光栅化器逐像素重心插值 + 真正的 `SkeletonClipping`，两个问题都没有，
所以这里直接用它。

## 命名与帧率

- 表情包：`p<包ID>-<图ID>.webp`（**必须带包 ID**：`10006`/`10007` 都有
  `ani_expression_022`/`025`，只用图名会互相覆盖，表现为「这个表情显示成了别的表情」）。
- 互动类：`ani_expression_saizi_animation<N>` → `1_<N>.webp`（骰子 6 面）、
  `ani_expression_caiquan_animation<N>` → `2_<N>.webp`（猜拳 3 手）。
- 帧率统一 30fps（`--fps 30`）。注意 libwebp 会**合并连续相同帧**，所以产物的帧数
  比渲染帧数少是正常的，别在测试里写死帧数。

脚本会自动跳过 `ani_expression_002_animation2` 这类**同骨架的第二条动画**
（游戏播的是 `animation`），以及缺 atlas/skel 的项（真实数据里
`10013/ani_expression_zhendejiade` 就缺文件，游戏本身也没有）。
