// 앱 빌드: 데이터·그림 변환 → Godot 리소스 가져오기 → 자가 테스트 → 내보내기
//   node scripts/build-app.mjs            APK (build/BattleTest.apk)
//   node scripts/build-app.mjs --install  APK 를 만들고 연결된 기기(adb)에 설치·실행
//   node scripts/build-app.mjs --win      Windows 실행 파일 (build/windows/BattleTest.exe)
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../', import.meta.url));
const GODOT_DIR = join(ROOT, 'godot');
const PKG = 'com.battletest.viewer';

function findGodot() {
  if (process.env.GODOT) return process.env.GODOT;
  const base = join(process.env.LOCALAPPDATA ?? '', 'Microsoft', 'WinGet', 'Packages');
  for (const d of existsSync(base) ? readdirSync(base) : []) {
    if (!d.startsWith('GodotEngine.GodotEngine_')) continue;
    const exe = readdirSync(join(base, d)).find((f) => /^Godot_v4.*_console\.exe$/.test(f));
    if (exe) return join(base, d, exe);
  }
  throw new Error('Godot 실행 파일을 찾지 못했습니다. 환경변수 GODOT 에 경로를 지정하세요.');
}
const run = (cmd, args, opts = {}) => execFileSync(cmd, args, { stdio: 'inherit', ...opts });
const godot = findGodot();
const win = process.argv.includes('--win');
const out = win ? join(ROOT, 'build', 'windows', 'BattleTest.exe') : join(ROOT, 'build', 'BattleTest.apk');
mkdirSync(join(out, '..'), { recursive: true });

console.log('▶ 데이터·그림 변환');
run(process.execPath, [join(ROOT, 'scripts', 'build-sprites.mjs'), '--set=pokemon']);
console.log('▶ Godot 리소스 가져오기');
run(godot, ['--headless', '--path', GODOT_DIR, '--import'], { stdio: 'ignore' });
console.log('▶ 자가 테스트');
run(godot, ['--headless', '--path', GODOT_DIR, '--', '--selftest'], { stdio: ['ignore', 'ignore', 'inherit'] });
console.log(`▶ ${win ? 'Windows 실행 파일' : 'APK'} 내보내기`);
run(godot, ['--headless', '--path', GODOT_DIR, '--export-debug', win ? 'Windows Desktop' : 'Android', out.replaceAll('\\', '/')], { stdio: 'ignore' });
if (!existsSync(out)) throw new Error('내보내기에 실패했습니다.');
console.log(`  → ${out}`);

if (!win && process.argv.includes('--install')) {
  console.log('▶ 기기에 설치');
  run('adb', ['install', '-r', out]);
  run('adb', ['shell', 'monkey', '-p', PKG, '-c', 'android.intent.category.LAUNCHER', '1'], { stdio: 'ignore' });
}
