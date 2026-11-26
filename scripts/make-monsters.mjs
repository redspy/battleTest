// 오리지널 몬스터 그림 만들기: data/monsters/species.json 의 종마다 움직이는 GIF 를
// monster_gifs/도감번호_영문명_한글명/도감번호_영문명_순번_폼.gif 로 만든다 (pokemon_gifs 와 같은 폴더 규칙).
// 그림은 이 스크립트가 도형으로 직접 그린다. 사용: node scripts/make-monsters.mjs
import sharp from 'sharp';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const OUT = join(ROOT, 'monster_gifs');
const S = 360, FRAMES = 24, DELAY = 45;
const TAU = Math.PI * 2;

const star = (cx, cy, n, r1, r2, rot = 0) => Array.from({ length: n * 2 }, (_, i) => {
  const r = i % 2 ? r2 : r1, a = rot + (i * Math.PI) / n - Math.PI / 2;
  return `${(cx + r * Math.cos(a)).toFixed(1)},${(cy + r * Math.sin(a)).toFixed(1)}`;
}).join(' ');

// 얼굴: 눈 두 개(가끔 깜빡임) + 입
function face(cx, cy, gap, t, o = {}) {
  const blink = t > 0.86 && t < 0.94;
  const r = o.r ?? 13, pupil = o.pupil ?? '#1d1d28';
  let s = '';
  for (const dx of [-gap, gap]) {
    s += blink
      ? `<path d="M${cx + dx - r} ${cy} q${r} 7 ${r * 2} 0" stroke="${pupil}" stroke-width="4" fill="none" stroke-linecap="round"/>`
      : `<ellipse cx="${cx + dx}" cy="${cy}" rx="${r}" ry="${r * 1.15}" fill="#fff"/><circle cx="${cx + dx + 2}" cy="${cy + 2}" r="${r * 0.55}" fill="${pupil}"/><circle cx="${cx + dx - 2}" cy="${cy - 4}" r="${r * 0.22}" fill="#fff"/>`;
  }
  const m = o.mouth ?? 'smile';
  if (m === 'smile') s += `<path d="M${cx - 9} ${cy + 22} q9 9 18 0" stroke="#1d1d28" stroke-width="3.5" fill="none" stroke-linecap="round"/>`;
  if (m === 'flat') s += `<path d="M${cx - 9} ${cy + 24} h18" stroke="#1d1d28" stroke-width="3.5" stroke-linecap="round"/>`;
  if (m === 'fang') s += `<path d="M${cx - 12} ${cy + 22} h24" stroke="#1d1d28" stroke-width="3.5" stroke-linecap="round"/><path d="M${cx - 8} ${cy + 23} l4 9 l4 -9z M${cx + 1} ${cy + 23} l4 9 l4 -9z" fill="#fff"/>`;
  if (m === 'o') s += `<ellipse cx="${cx}" cy="${cy + 24}" rx="6" ry="7" fill="#1d1d28"/>`;
  return s;
}

const OUTLINE = 'stroke="#1d1d28" stroke-width="5" stroke-linejoin="round"';

// 종마다: (t 0~1, 각성 여부) → 몸통 SVG (중심 180,190 기준)
const DRAW = {
  embercub(t, a) {
    const f = Math.sin(t * TAU * 2) * 6, c = a ? '#ff7a1a' : '#f39a3d';
    return `<path d="M180 ${62 - f} q26 34 8 62 q-22 -8 -30 -30 q-4 18 4 34 q-30 -18 -6 -60 q10 6 12 22 q6 -14 12 -28z" fill="${a ? '#ffe34d' : '#ffc23d'}" ${OUTLINE}/>
      <path d="M112 132 l-14 -44 l42 22z M248 132 l14 -44 l-42 22z" fill="${c}" ${OUTLINE}/>
      <ellipse cx="180" cy="200" rx="88" ry="84" fill="${c}" ${OUTLINE}/><ellipse cx="180" cy="232" rx="50" ry="40" fill="#ffe0b0"/>` + face(180, 180, 30, t, { mouth: 'smile' });
  },
  blazorn(t, a) {
    const f = Math.sin(t * TAU * 2) * 8, c = a ? '#e0331f' : '#c8492f';
    return `<path d="M270 250 q${50 + f} -10 ${40} -70 q-8 30 -30 28 q8 -24 -6 -40 q-2 40 -30 50z" fill="#ffb02e" ${OUTLINE}/>
      <path d="M122 120 q-40 -30 -30 -78 q22 40 58 50z M238 120 q40 -30 30 -78 q-22 40 -58 50z" fill="${a ? '#fff2a0' : '#f4d35e'}" ${OUTLINE}/>
      <path d="M180 96 c70 0 100 60 100 116 c0 60 -44 84 -100 84 s-100 -24 -100 -84 c0 -56 30 -116 100 -116z" fill="${c}" ${OUTLINE}/><ellipse cx="180" cy="244" rx="54" ry="36" fill="#f6c9a0"/>` + face(180, 176, 32, t, { mouth: 'fang' });
  },
  mossle(t, a) {
    const sway = Math.sin(t * TAU) * 8, c = a ? '#4fc45a' : '#5aa85a';
    return `<path d="M180 108 q${-30 + sway} -44 ${-6 + sway} -70 q30 14 20 66z M184 108 q${40 + sway} -30 ${62 + sway} -22 q-18 30 -56 28z" fill="${a ? '#b6f26b' : '#8fd36a'}" ${OUTLINE}/>
      <path d="M60 250 c0 -90 54 -142 120 -142 s120 52 120 142 c0 30 -40 44 -120 44 s-120 -14 -120 -44z" fill="${c}" ${OUTLINE}/>
      <circle cx="104" cy="186" r="13" fill="#3d7f44"/><circle cx="258" cy="200" r="16" fill="#3d7f44"/><circle cx="222" cy="146" r="10" fill="#3d7f44"/><circle cx="92" cy="244" r="9" fill="#3d7f44"/>` + face(180, 206, 34, t, { mouth: 'flat' });
  },
  thornap(t, a) {
    const c = a ? '#2fa36b' : '#3f8f62', rot = Math.sin(t * TAU) * 0.05;
    return `<polygon points="${star(180, 190, 9, 122, 92, rot)}" fill="${a ? '#e6ff7a' : '#c9e27a'}" ${OUTLINE}/>
      <path d="M180 78 q92 50 66 150 q-20 62 -66 74 q-46 -12 -66 -74 q-26 -100 66 -150z" fill="${c}" ${OUTLINE}/><path d="M180 96 v186" stroke="#2c6a48" stroke-width="5"/>` + face(180, 186, 28, t, { mouth: 'fang' });
  },
  pebblet(t, a) {
    const o = t * TAU, c = a ? '#b9a98f' : '#9a9aa6';
    let peb = '';
    for (let i = 0; i < 3; i++) { const an = o + (i * TAU) / 3; peb += `<circle cx="${180 + Math.cos(an) * 138}" cy="${200 + Math.sin(an) * 34}" r="${a ? 15 : 12}" fill="${a ? '#f0c86a' : '#7b7b88'}" ${OUTLINE}/>`; }
    return `<polygon points="92,150 150,98 236,104 282,166 270,258 198,296 120,284 78,222" fill="${c}" ${OUTLINE}/>
      <path d="M150 98 l20 44 l66 -38 M170 142 l-78 8 M270 258 l-44 -30" stroke="#6d6d7a" stroke-width="4" fill="none"/>` + face(176, 198, 32, t, { mouth: 'flat' }) + peb;
  },
  cragon(t, a) {
    const c = a ? '#b5703a' : '#96684a';
    return `<polygon points="96,150 124,84 158,136 180,66 206,134 240,80 262,150" fill="${a ? '#ffd36a' : '#c9b08a'}" ${OUTLINE}/>
      <path d="M70 262 q-6 -120 110 -124 q116 4 110 124 q-4 38 -110 38 q-106 0 -110 -38z" fill="${c}" ${OUTLINE}/>
      <path d="M92 262 q88 26 176 0" stroke="#6b4630" stroke-width="5" fill="none"/>` + face(180, 204, 36, t, { mouth: 'fang' });
  },
  zapple(t, a) {
    const fl = Math.floor(t * 8) % 2, c = a ? '#c79bff' : '#a98be0';
    const bolt = (x, y, sx) => `<path d="M${x} ${y} l${14 * sx} -30 l${-12 * sx} 4 l${10 * sx} -34 l${-30 * sx} 44 l${14 * sx} -4z" fill="${a ? '#7ae7ff' : '#fff7b0'}" ${OUTLINE}/>`;
    return bolt(128, 122, -1) + bolt(232, 122, 1) + `<circle cx="180" cy="200" r="88" fill="${c}" ${OUTLINE}/>
      <path d="M150 262 l14 -22 l12 16 l12 -16 l12 16 l10 -16" stroke="#fff7b0" stroke-width="6" fill="none" stroke-linejoin="round" stroke-linecap="round"/>` + face(180, 186, 30, t, { mouth: 'flat', pupil: '#3a2a6a' })
      + (fl ? `<path d="M70 150 l-22 -10 l14 -4 l-20 -12 M290 250 l22 10 l-14 4 l20 12" stroke="${a ? '#7ae7ff' : '#fff7b0'}" stroke-width="5" fill="none" stroke-linecap="round"/>` : '');
  },
  voltusk(t, a) {
    const c = a ? '#3a57d0' : '#3d4f8f', g = 0.6 + Math.sin(t * TAU * 2) * 0.4;
    return `<path d="M180 118 l26 -66 l-24 10 l20 -52 l-58 78 l26 -8z" fill="#ffe14a" opacity="${a ? 1 : g.toFixed(2)}" ${OUTLINE}/>
      <path d="M82 214 q0 -98 98 -98 q98 0 98 98 q0 82 -98 82 q-98 0 -98 -82z" fill="${c}" ${OUTLINE}/>
      <path d="M96 250 q84 40 168 0 q-10 46 -84 46 q-74 0 -84 -46z" fill="#ffe14a"/>
      <path d="M126 244 q-14 26 -30 28 M234 244 q14 26 30 28" stroke="#fff" stroke-width="9" fill="none" stroke-linecap="round"/>` + face(180, 190, 32, t, { mouth: 'flat' });
  },
  ripplet(t, a) {
    const c = a ? '#35b6ff' : '#5aa9e6';
    let rings = '';
    for (let i = 0; i < 2; i++) { const p = (t + i / 2) % 1; rings += `<ellipse cx="180" cy="300" rx="${50 + p * 90}" ry="${8 + p * 14}" fill="none" stroke="${a ? '#b8f0ff' : '#9fd2f5'}" stroke-width="5" opacity="${(1 - p).toFixed(2)}"/>`; }
    return rings + `<path d="M180 62 q84 96 84 150 q0 82 -84 82 q-84 0 -84 -82 q0 -54 84 -150z" fill="${c}" ${OUTLINE}/>
      <path d="M132 176 q4 -30 26 -50" stroke="#e6f7ff" stroke-width="9" fill="none" stroke-linecap="round"/>` + face(180, 212, 28, t, { mouth: 'smile' });
  },
  tidalon(t, a) {
    const w = Math.sin(t * TAU) * 10, c = a ? '#1f7fd6' : '#3f78b8';
    return `<path d="M250 150 q60 ${-30 + w} 70 ${-80} q-34 16 -56 10 q8 -24 -4 -40 q-30 30 -40 80z" fill="${a ? '#8ff0ff' : '#8fc4e8'}" ${OUTLINE}/>
      <path d="M66 240 q-8 -112 96 -130 q108 -12 124 86 q10 100 -110 102 q-102 2 -110 -58z" fill="${c}" ${OUTLINE}/>
      <path d="M84 256 q40 ${-14 + w} 80 0 t80 0 t40 -8" stroke="#dff3ff" stroke-width="7" fill="none" stroke-linecap="round"/>` + face(170, 188, 32, t, { mouth: 'smile' });
  },
  frostel(t, a) {
    const rot = t * TAU / 6, c = a ? '#9fe8ff' : '#bfe4f5';
    return `<polygon points="${star(180, 190, 6, 132, 60, rot)}" fill="${a ? '#ffffff' : '#e8f6fc'}" ${OUTLINE}/>
      <polygon points="${star(180, 190, 6, 100, 78, -rot)}" fill="${c}" ${OUTLINE}/>` + face(180, 184, 26, t, { mouth: 'smile', pupil: '#27507a' });
  },
  glacub(t, a) {
    const c = a ? '#7fd4f2' : '#a5cfe0', sh = (t * 260) % 260;
    return `<path d="M104 112 l-10 -40 l36 30z M256 112 l10 -40 l-36 30z" fill="${c}" ${OUTLINE}/>
      <rect x="82" y="104" width="196" height="186" rx="44" fill="${c}" ${OUTLINE}/>
      <path d="M${90 + sh} 110 l-50 176" stroke="#fff" stroke-width="12" opacity="0.5" stroke-linecap="round" clip-path="url(#cb)"/>
      <path d="M112 288 l10 30 l12 -30z M172 290 l8 36 l10 -36z M228 288 l10 30 l12 -30z" fill="#e8f6fc" ${OUTLINE}/>` + face(180, 190, 36, t, { mouth: 'flat', pupil: '#27507a' });
  },
};

function frame(id, i, awake) {
  const t = i / FRAMES;
  const bob = Math.sin(t * TAU) * 7, sq = 1 + Math.sin(t * TAU) * 0.035;
  const aura = awake
    ? `<circle cx="180" cy="190" r="${150 + Math.sin(t * TAU * 2) * 8}" fill="none" stroke="#fff3a0" stroke-width="8" opacity="0.55" stroke-dasharray="26 18" transform="rotate(${t * 360} 180 190)"/>` : '';
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${S}" height="${S}" viewBox="0 0 ${S} ${S}">
    <defs><clipPath id="cb"><rect x="82" y="104" width="196" height="186" rx="44"/></clipPath></defs>
    <ellipse cx="180" cy="328" rx="${86 - bob}" ry="13" fill="#000" opacity="0.18"/>${aura}
    <g transform="translate(0 ${bob.toFixed(1)}) translate(180 300) scale(${(2 - sq).toFixed(3)} ${sq.toFixed(3)}) translate(-180 -300)">${DRAW[id](t, awake)}</g></svg>`);
}

const { species } = JSON.parse(readFileSync(join(ROOT, 'data/monsters/species.json'), 'utf8'));
const report = {};
for (const sp of species) {
  const dirName = `${String(sp.no).padStart(4, '0')}_${sp.en}_${sp.ko}`;
  mkdirSync(join(OUT, dirName), { recursive: true });
  report[dirName] = { generator: 'scripts/make-monsters.mjs', images: [] };
  for (const f of sp.forms) {
    const frames = [];
    for (let i = 0; i < FRAMES; i++) frames.push(await sharp(frame(sp.id, i, f.id === 'awake')).png().toBuffer());
    const file = `${f.file}.gif`;
    const info = await sharp(frames, { join: { animated: true } }).gif({ delay: Array(FRAMES).fill(DELAY), loop: 0 }).toFile(join(OUT, dirName, file));
    report[dirName].images.push({ file, alt: `${dirName.slice(0, 4)} - ${sp.en}${f.id === 'awake' ? ' (Awakened)' : ''}`, bytes: info.size });
  }
  console.log(dirName);
}
writeFileSync(join(OUT, '_generate_report.json'), JSON.stringify(report, null, 1));

// README: pokemon_gifs/README.md 와 같은 짜임(폴더 구조 설명 + 팀 표)
const teams = JSON.parse(readFileSync(join(ROOT, 'data/monsters/teams.json'), 'utf8'));
const ko = Object.fromEntries(species.map((s) => [s.id, s.ko]));
let md = `# 오리지널 몬스터 GIF 모음\n\n- 그림 출처: \`scripts/make-monsters.mjs\` 가 도형으로 직접 그린 그림 (\`_generate_report.json\` 에 파일 목록 기록)\n- 규칙: 오리지널 규칙, 6마리 중 3마리 선출 (싱글) — \`data/monsters/rules.json\`\n\n## 폴더 구조\n\n\`도감번호_영문명_한글명/도감번호_영문명_순번_폼.gif\`\n한 폴더에 기본 폼과 각성 폼이 들어 있습니다.\n\n## 기본 팀\n\n| 번호 | 성격 | 팀 |\n|---|---|---|\n`;
for (const t of teams.teams) md += `| ${t.rank} | ${t.name} | ${t.members.map((m) => ko[m.species]).join(', ')} |\n`;
writeFileSync(join(OUT, 'README.md'), md);
