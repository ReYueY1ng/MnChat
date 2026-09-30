# 动态表情动图素材（spine → webp）

游戏的「动态表情」是 **spine** 格式，spine 运行时不能商用，所以这里约定：
把 spine 动画在外部渲染成 **动图 webp** 后放进本目录，客户端用
`Image.asset` 直接播放（与 `assets/headframes_anim/` 的头像框做法一致）。

Flutter 原生支持动画 WebP，**只要放进这个目录就会被 `pubspec.yaml` 打包**，
无需改代码。

## 命名

| 场景 | 文件名 | 来源 |
|------|--------|------|
| 骰子（`@IMFC&1_3`，3 点） | `1_3.webp` | `ani_expression_saizi.skel` 的 `animation3` |
| 猜拳（`@IMFC&2_2`，剪刀） | `2_2.webp` | `ani_expression_caiquan.skel` 的 `animation2` |
| 表情包内的骰子/猜拳（`[mdemo]2&10006&ani_expression_saizi>5[/mdemo]`，掷出 5） | `1_5.webp` | 同上（`>序号` 就是结果，见下） |
| 表情包内表情（`[mdemo]2&10006&ani_expression_022[/mdemo]`） | `p10006-ani_expression_022.webp` | 包内 `infos.list` 的 `icon` |

即：互动表情用 `<序号>_<结果>.webp`；表情包内表情用 `p<包ID>-<图ID>.webp`。

**骰子/猜拳在表情包里是「图 ID + `>序号`」**：包内并没有叫 `ani_expression_saizi>5`
的图，它指的是 `ani_expression_saizi` 这条骨架的第 5 个动画（`GetEmojiLabel` 拼
`图ID>序号`，`SetItemIcon` 取 `anis[序号]`），序号即结果。客户端由
`interactiveAnimName()` 映射到内置的 `1_5.webp`；漏了这一步就会退化成**灰色占位图标**
（`Icons.emoji_emotions_outlined`）。

**为什么表情包必须带包 ID**：不同包会有同名图 —— 真实数据里 `10006` 与 `10007`
都有 `ani_expression_022` 和 `ani_expression_025`。只按图名命名会互相覆盖，
表现就是「这个表情显示成了别的表情」。

**注意**：Flutter **不会**递归打包子目录，所以这里保持扁平命名
（`pubspec.yaml` 只需声明 `assets/emoticon/anim/` 一条）。

## 目录里已有什么

| 文件 | 说明 |
|------|------|
| `1_1.webp` ~ `1_6.webp` | 骰子：掷 2 秒后停在 1~6 点（21 帧 / 2.1s；**这是游戏自己的帧率**——它的关键帧每 0.1s 换一次面，再高的 fps 只是重复帧） |
| `2_1.webp` ~ `2_3.webp` | 猜拳：1=布 2=剪刀 3=石头（24 帧 / 2.4s，同上） |
| `p<包ID>-*.webp` 等 | 其余 37 个动态表情（`spine2webp` 渲染，**30fps**） |

游戏数据里 `10013/ani_expression_zhendejiade` 缺 atlas/skel（游戏本身也缺），故无对应文件。


## 播放策略

| 类别 | 播放方式 | 原因 |
|------|----------|------|
| 骰子 / 猜拳（`1_N`、`2_N`） | **播一次，停在最后一帧** | 结果（点数 / 手势）就写在末帧上，循环播会读不出结果 |
| 表情包（`ani_expression_*`） | **循环播放** | 是持续的表情动作，不走循环会停成一张静图 |

实现在 `lib/core/emoticon.dart` 的 `EmojiAnimImage`：循环那类交给 `Image.asset`
（原生、高效）；停末帧那类自己用 `ui.instantiateImageCodec` 解码逐帧，
`AnimationController.forward()` 推进，因此天然停在最后一帧。

## 缺失时的回退

- 骰子/猜拳：有动图就播动图；没有则回退到内置图集 `assets/emoticon/emoticon.webp`
  里的**结果帧**（`1_1..1_6` / `2_0..2_3`，与游戏停留 5 秒后的最终画面一致）；
- 动态表情包：有动图就播动图；没有则占位图标。

## 转换方法（开发期一次性，可复跑）

游戏端的这些「动态表情」是 **Spine 3.8.99** 骨架。spine 运行时不能商用，所以：
运行时**只作为开发期工具**把动画渲成 webp，产物随包发布，运行时本体不进 App。

两条产线（复跑脚本见仓库 `tool/emoji_anim/`，含 `README.md`）：

- **表情包内表情**：`spine2webp`（官方 spine-cpp 光栅化器，mesh 绑定与 clipping 遮罩都靠它）；
- **骰子 / 猜拳**：`dump_timeline.js` + `build_interactive_webp.py` 按图集区域时间轴拼帧。
  它们是纯 attachment 时间轴动画，且**结果面只出现在最后一帧**
  （`animation3` 的 21 个关键帧里只有 t=2.0 那一个写着 `1_3`），
  `spine2webp` 的采样取不到那个时刻，会把 6 个结果导成同一份内容 ——
  表现就是「互动表情永远是同一个占位图」。

## 素材来源

游戏运行时的表情缓存目录（`GetEmojiDirPath` = `data/http/emoji/<包ID>/`），
每个包里是 `infos.list` + 每个表情的 `<icon>.atlas/.skel/.png`。
`anis` 字段给出每个表情的动画名列表（骰子 6 个、猜拳 3 个，序号与结果一致）。
