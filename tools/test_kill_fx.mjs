import { readFileSync, existsSync } from 'node:fs';
import { KILL_FX, KILL_FX_SE, KILL_FX_MS, skillKillKind, beginSkillKill, endSkillKill } from '../js/kill-fx.js';

let fails = 0;
const ok = (m, c, d = '') => { if (c) console.log('  ok', m); else { fails++; console.log('FAIL', m, d); } };

const kinds = { slash: 0, shatter: 0, burn: 0, shock: 0, freeze: 0 };
for (const [id, k] of Object.entries(KILL_FX)) {
  kinds[k] = (kinds[k] || 0) + 1;
  ok(`id ${id} is 5-digit`, /^\d{5}$/.test(id));
  ok(`${id} kind valid`, k in KILL_FX_MS);
}
ok('slash 20', kinds.slash === 20, kinds.slash);
ok('shatter 18', kinds.shatter === 18, kinds.shatter);
ok('burn 11', kinds.burn === 11, kinds.burn);
ok('shock 4', kinds.shock === 4, kinds.shock);
ok('freeze 4', kinds.freeze === 4, kinds.freeze);
ok('total 57', Object.keys(KILL_FX).length === 57, Object.keys(KILL_FX).length);

for (const [k, code] of Object.entries(KILL_FX_SE)) {
  const f = `audio/se/${String(code).padStart(3, '0')}_01.mp3`;
  ok(`SE ${k} ${f}`, existsSync(f));
}

beginSkillKill({ card: { id: '10051' } });
ok('skill killer slash', skillKillKind() === 'slash');
beginSkillKill({ card: { id: '10304' } });
ok('skill killer burn', skillKillKind() === 'burn');
endSkillKill();
ok('no killer after end', skillKillKind() === null);
ok('normal attack context has no kind', skillKillKind({ card: { id: '10051' } }) === 'slash'); // explicit unit still works
ok('unmapped id', skillKillKind({ card: { id: '10013' } }) === null);

const game = readFileSync('js/game.js', 'utf8');
ok('game imports kill-fx', game.includes("from './kill-fx.js'"));
ok('skills.js untouched in this feature (no kill-fx import)', !readFileSync('js/skills.js', 'utf8').includes('kill-fx'));
ok('index has css', readFileSync('index.html', 'utf8').includes('css/kill-fx.css'));

console.log(fails ? `${fails} FAIL` : 'ALL PASS');
if (fails) process.exit(1);
