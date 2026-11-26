// GIF → Godot 용 프레임 시트(WebP) 변환 + 데이터 복사. 원본 GIF 는 건드리지 않는다.
//   data/<세트>/*.json            → godot/data/<세트>/*.json
//   <gifRoot>/<폴더>/<파일>.gif   → godot/sprites/<세트>/<파일>.webp (크게 보기), <파일>_t.webp (목록)
//   godot/data/<세트>/sprites.json : 파일별 { cols, rows, frames, fw, fh, fps } (big / thumb)
// 사용: node scripts/build-sprites.mjs [--force] [--set=세트]
import sharp from 'sharp';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const FORCE = process.argv.includes('--force');
const requestedSet = process.argv.find((arg) => arg.startsWith('--set='))?.slice('--set='.length);
const SIZES = { big: { long: 384, maxFrames: 30 }, thumb: { long: 160, maxFrames: 12 } };

async function sheet(src, dst, { long, maxFrames }) {
  const meta = await sharp(src, { animated: true }).metadata();
  const pages = meta.pages ?? 1, w = meta.width, h = meta.pageHeight ?? meta.height;
  const step = Math.max(1, Math.ceil(pages / maxFrames));
  const idx = []; for (let i = 0; i < pages; i += step) idx.push(i);
  const k = long / Math.max(w, h), fw = Math.round(w * k), fh = Math.round(h * k);
  const cols = Math.ceil(Math.sqrt(idx.length)), rows = Math.ceil(idx.length / cols);
  const delay = (meta.delay?.[0] || 30) * step;
  const out = { cols, rows, frames: idx.length, fw, fh, fps: Math.round((1000 / delay) * 10) / 10 };
  if (!FORCE && existsSync(dst) && statSync(dst).mtimeMs > statSync(src).mtimeMs) return out;
  const comps = [];
  for (let n = 0; n < idx.length; n++) {
    const input = await sharp(src, { page: idx[n] }).resize(fw, fh, { fit: 'fill' }).ensureAlpha().png().toBuffer();
    comps.push({ input, left: (n % cols) * fw, top: Math.floor(n / cols) * fh });
  }
  await sharp({ create: { width: cols * fw, height: rows * fh, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
    .composite(comps).webp({ quality: 82, alphaQuality: 90 }).toFile(dst);
  return out;
}

for (const set of requestedSet ? [requestedSet] : readdirSync(join(ROOT, 'data'))) {
  const dir = join(ROOT, 'data', set);
  if (!existsSync(join(dir, 'species.json'))) continue;
  const outData = join(ROOT, 'godot/data', set), outSpr = join(ROOT, 'godot/sprites', set);
  mkdirSync(outData, { recursive: true }); mkdirSync(outSpr, { recursive: true });
  for (const f of readdirSync(dir)) if (f.endsWith('.json')) copyFileSync(join(dir, f), join(outData, f));

  const sp = JSON.parse(readFileSync(join(dir, 'species.json'), 'utf8'));
  const gifRoot = join(ROOT, sp.gifRoot);
  const folders = readdirSync(gifRoot).filter((d) => /^\d{4}_/.test(d));
  const sprites = {};
  let made = 0, missing = 0;
  for (const s of sp.species) {
    const folder = folders.find((d) => d.startsWith(String(s.no).padStart(4, '0') + '_'));
    for (const form of s.forms) {
      if (!form.file || form.file.startsWith("emblem:")) continue;
      const src = folder ? join(gifRoot, folder, form.file + '.gif') : '';
      if (!src || !existsSync(src)) { console.warn(`  없음: ${form.file}.gif`); missing++; continue; }
      sprites[form.file] = {
        big: await sheet(src, join(outSpr, form.file + '.webp'), SIZES.big),
        thumb: await sheet(src, join(outSpr, form.file + '_t.webp'), SIZES.thumb),
      };
      made++;
    }
  }
  writeFileSync(join(outData, 'sprites.json'), JSON.stringify(sprites));
  const bytes = readdirSync(outSpr).filter((f) => f.endsWith('.webp')).reduce((a, f) => a + statSync(join(outSpr, f)).size, 0);
  console.log(`${set}: 그림 ${made}개 (없음 ${missing}), 시트 합계 ${(bytes / 1e6).toFixed(1)}MB`);
}
