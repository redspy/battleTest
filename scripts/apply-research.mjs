// 조사 결과(data/research/team_sets.json)를 data/pokemon/teams.json · moves.json 에 반영한다.
// 확인된 값만 옮긴다: 지닌 도구, (있으면) 특성·기술, 공개 팀 시트 주소. 없는 값은 건드리지 않는다.
// 사용: node scripts/apply-research.mjs  →  node scripts/build-sprites.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const read = (p) => JSON.parse(readFileSync(ROOT + p, 'utf8'));
const research = read('data/research/team_sets.json');
const species = read('data/pokemon/species.json').species;
const teams = read('data/pokemon/teams.json');
const moves = read('data/pokemon/moves.json');

const byEn = Object.fromEntries(species.map((s) => [s.en.toLowerCase(), s]));
const formId = (sp, form) => {
  const f = (form ?? '').toLowerCase();
  const want = f.includes('mega y') ? 'megay' : f.includes('mega x') ? 'megax' : f.includes('mega') ? 'mega' : f.includes('hisui') ? 'hisui' : f.includes('alola') ? 'alola' : 'base';
  return sp.forms.some((x) => x.id === want) ? want : 'base';
};

let items = 0, sets = 0, added = 0;
for (const rt of research.teams) {
  const id = `${rt.event.toLowerCase()}-${rt.rank}`;
  let team = teams.teams.find((t) => t.id === id);
  if (!team) {
    const members = rt.members.map((m) => { const sp = byEn[m.species.toLowerCase()]; return sp ? { species: sp.id, form: formId(sp, m.form) } : null; });
    if (members.includes(null) || members.length !== 6) { console.warn(`건너뜀: ${id} (모르는 종)`); continue; }
    team = { id, event: rt.event, rank: rt.rank, player: rt.player, name: `${rt.player} 팀`, tags: [], summary: '조사로 구성만 확인한 팀입니다.', members };
    teams.teams.push(team);
    added++;
  }
  if (rt.sourceUrl) team.sourceUrl = rt.sourceUrl;
  for (const m of rt.members) {
    const sp = byEn[m.species.toLowerCase()];
    const tm = sp && team.members.find((x) => x.species === sp.id);
    if (!tm) continue;
    if (m.item) { tm.item = m.item; items++; }
    if (m.ability) tm.ability = m.ability;
    if (m.moves?.length) { tm.moves = m.moves; sets++; }
  }
}
// 대회 순서, 순위 순으로 정렬
const evOrder = teams.events.map((e) => e.id);
teams.teams.sort((a, b) => evOrder.indexOf(a.event) - evOrder.indexOf(b.event) || a.rank - b.rank);
for (const [id, parameters] of Object.entries(research.moves ?? {})) {
  // Keep Champions PP when applying older research that predates the PP rules.
  const updated = { ...moves.moves[id], ...parameters };
  delete updated.cost;
  if (!Number.isInteger(updated.pp) || updated.pp < 1) {
    throw new Error(`Champions PP missing for ${id}`);
  }
  moves.moves[id] = updated;
}
for (const key of ['items', 'abilities']) Object.assign(moves[key], research[key] ?? {});

writeFileSync(ROOT + 'data/pokemon/teams.json', JSON.stringify(teams, null, 2) + '\n');
writeFileSync(ROOT + 'data/pokemon/moves.json', JSON.stringify(moves, null, 2) + '\n');
console.log(`도구 ${items}개, 기술 구성 ${sets}마리, 새 팀 ${added}개 반영`);
