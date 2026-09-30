// 导出「图集区域随时间的切换序列」：骰子/猜拳这类只有 attachment 时间轴的动画，
// 不需要骨架变换，直接按时间轴逐帧取区域图即可。
// 用法: node dump_timeline.js <packDir> <item> <outJson>
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const code = fs.readFileSync(path.join(__dirname, 'spine-core.js'), 'utf8');
const ctx = { console, Math, Date, window: {}, global: {} };
vm.createContext(ctx);
const spine = vm.runInContext(code + '\n;spine;', ctx);

const [, , packDir, item, outJson] = process.argv;
const atlasText = fs.readFileSync(path.join(packDir, `${item}.atlas`), 'utf8');
const sizes = {};
{
  const L = atlasText.split(/\r?\n/);
  for (let i = 0; i < L.length; i++) {
    if (/\.png\s*$/.test(L[i].trim())) {
      const m = (L[i + 1] || '').match(/size:\s*(\d+)\s*,\s*(\d+)/);
      sizes[L[i].trim()] = m ? [Number(m[1]), Number(m[2])] : [0, 0];
    }
  }
}

const textures = {};
const atlas = new spine.TextureAtlas(atlasText, (p) => {
  if (!textures[p]) {
    textures[p] = {
      name: p,
      getImage: () => ({ width: sizes[p][0], height: sizes[p][1] }),
      setFilters() {},
      setWraps() {},
      dispose() {},
    };
  }
  return textures[p];
});

const data = new spine.SkeletonBinary(new spine.AtlasAttachmentLoader(atlas))
  .readSkeletonData(new Uint8Array(fs.readFileSync(path.join(packDir, `${item}.skel`))));

const animations = {};
for (const anim of data.animations) {
  const keys = [];
  for (const tl of anim.timelines) {
    if (!(tl instanceof spine.AttachmentTimeline)) continue;
    for (let i = 0; i < tl.frames.length; i++) {
      keys.push([Number(tl.frames[i].toFixed(4)), tl.attachmentNames[i]]);
    }
  }
  keys.sort((a, b) => a[0] - b[0]);
  animations[anim.name] = { duration: Number(anim.duration.toFixed(4)), keys };
}

const page = atlasText.split(/\r?\n/).find((l) => /\.png\s*$/.test(l)).trim();
fs.writeFileSync(outJson, JSON.stringify({ item, page, animations }, null, 1));
console.log(`${item}: ${Object.keys(animations).length} animations -> ${outJson}`);
