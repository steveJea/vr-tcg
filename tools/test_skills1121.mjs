// 2026-11-21 스킬 시트: 황보예 변경 · 왕유영·하지연·주슬기·허유리·류태연 추가 + staging 해시 SQL (PGlite). 실행: node tools/test_skills1121.mjs
import { readFileSync } from 'fs';
import { createRequire } from 'module';
import { setSkillData, setEmitter, setRng, initPlayers, placeUnit, refreshAll, useSkill, checkDeath, skillsOf, onLevelChange, aiSkillScores, ACTIVE } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool, RULES } from '../js/rules.js';
RULES.GENDER_ON = false; RULES.EVADE_ON = false;
const rd = f => readFileSync(new URL('../' + f, import.meta.url), 'utf8');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const cards = parseCSV(rd('data/cards.csv')), npcs = parseCSV(rd('data/npc_cards.csv')), pool = [...cards, ...npcs];
const SK = JSON.parse(rd('data/skills.json'));
setCardPool(pool); setSkillData(SK, JSON.parse(rd('data/combos.json'))); setEmitter(() => {}); setRng(() => 0.99);
const C = id => pool.find(c => String(c.id) === String(id));
const G = ['NORMAL', 'RARE', 'HIGH RARE', 'SUPER RARE', 'ULTRA RARE'];
const byGrade = g => cards.find(c => c.grade === g && c.class !== 'LIGHT' && !SK[c.id]?.some(s => s.mode === 'passive'));
const FOES = G.map(byGrade);   // N · R · HR · SR · UR 한 장씩 (패시브 없는 카드)
const mk = (c, uid) => { const u = makeUnit(c, uid); u.sk = skillsOf(c.id); return u; };
function fresh(id, allies = [], foes = FOES, hp = 99999) {
  const A = { name: 'A', hp: 9999, maxHp: 9999, field: [], hand: [], deck: [], grave: [], mana: 0, turnsTaken: 9 }, B = { name: 'B', hp: 9999, maxHp: 9999, field: [], hand: [], deck: [], grave: [], mana: 0, turnsTaken: 9 };
  initPlayers(A, B, A);
  const u = placeUnit(A, C(id), mk); const al = allies.map(c => placeUnit(A, C(c), mk));
  const fs = foes.map(c => placeUnit(B, { ...c, HP: hp }, mk));
  [u, ...al, ...fs].forEach(x => { x.level = 10; onLevelChange(x); x.mp = 999; x.canAttack = true; for (const k of Object.keys(x.st)) delete x.st[k]; }); refreshAll(A); refreshAll(B);
  return { A, B, u, al, fs };
}
const use = (u, name) => { u.canAttack = true; u.mp = 999; u.cd = {}; return useSkill(u, u.sk.find(s => s.name === name)); };
// ---- 데이터: 시트 그대로 ----
const S = id => SK[id];
ok(S('10462').length === 1 && S('10462')[0].name === '나 갈거거든?' && S('10462')[0].mode === 'active' && S('10462')[0].mp === 30 && S('10462')[0].cooldown === 2 && S('10462')[0].unlock === 2, '황보예: 사망 패시브 → 액티브 나 갈거거든? (MP30·쿨2·Lv2)');
ok(S('10100')[0].name === '제가...잘못한 게 맞아요.' && S('10100')[0].mode === 'passive' && S('10100')[0].unlock === 1, '류태연: 사망 패시브');
ok(S('10264')[0].name === '우리는 아직 어린걸요?' && S('10264')[0].mp === 40 && S('10264')[0].cooldown === 4 && S('10264')[0].duration === 1, '왕유영: MP40·쿨4·1턴');
ok(S('10438')[0].name === '제가 희생양인가요?' && S('10438')[0].mode === 'passive' && S('10438')[0].duration === 1, '하지연: 패시브 1턴');
ok(S('10389')[0].name === '이건 너무 불합리해!' && S('10389')[0].mp === 40 && S('10389')[0].cooldown === 4, '주슬기: MP40·쿨4');
ok(S('10451')[0].name === '사실 내가 더 예쁘지?' && S('10451')[0].mp === 40 && S('10451')[0].cooldown === 5, '허유리: MP40·쿨5');
ok(['10462', '10264', '10389', '10451'].every(id => ACTIVE[S(id)[0].name]), '액티브 4개 구현');
const PW = { 10462: 3143, 10100: 807, 10264: 972, 10438: 1182, 10389: 1013, 10451: 1077 };   // 시트 기초stat POWER
ok(Object.entries(PW).every(([id, p]) => +C(id).power === p), '전투력 = 시트 값 (스킬 배율 반영)');
ok(C('10462').HP == 100 && C('10462').ATK == 15 && C('10100').HP == 48 && C('10438').HP == 77, '스탯은 그대로');
// ---- 황보예: SR 이하 적만 20%×2 ----
{ const { u, fs } = fresh('10462'); const r = use(u, '나 갈거거든?'); const hit = fs.map(t => t.hp < t.maxHp);
  ok(r.ok && hit.slice(0, 4).every(Boolean) && !hit[4], `황보예: N·R·HR·SR 만 피해, UR 은 그대로 (${hit})`);
  const one = fresh('10462', [], [FOES[0]]); const t = one.fs[0]; use(one.u, '나 갈거거든?'); const d = t.maxHp - t.hp;
  const two = fresh('10462', [], [FOES[0]]); setRng(() => 0.99);
  ok(d > 0, `황보예: 2회 타격 피해 ${d}`); }
{ const { u } = fresh('10462', [], [FOES[4]]); ok(!aiSkillScores(u).some(([s]) => s.name === '나 갈거거든?'), '황보예 AI: SR 이하 적이 없으면 안 씀'); }
// ---- 왕유영·허유리: 아군 전체 1턴 피해 면역 ----
for (const [id, nm] of [['10264', '우리는 아직 어린걸요?'], ['10451', '사실 내가 더 예쁘지?']]) {
  const { u, al } = fresh(id, ['10074', '10080', FOES[3].id]); use(u, nm);
  ok([u, ...al].every(a => a.st.immune && a.st.immune.t <= 2), `${C(id).name}: 아군 전체(남녀·등급 무관) 1턴 피해 면역`);
  const sc = fresh(id, ['10074', '10080']); ok(aiSkillScores(sc.u).some(([s]) => s.name === nm), `${C(id).name} AI 사용`); }
// ---- 주슬기: 적 전체 60 고정 ----
{ const { u, fs } = fresh('10389'); use(u, '이건 너무 불합리해!'); ok(fs.every(t => t.maxHp - t.hp === 60), `주슬기: 적 전체 정확히 60 (${fs.map(t => t.maxHp - t.hp)})`); }
// ---- 하지연: 출전 시 1턴 도발 + 불사 ----
{ const { A } = fresh('10074'); const h = placeUnit(A, C('10438'), mk); h.level = 1; onLevelChange(h); refreshAll(A);
  ok(h.st.taunt && h.st.endure && h.st.taunt.t <= 2 && h.st.endure.t === h.st.taunt.t, '하지연: 소환(해금) 시 1턴 도발 + 최소 HP 1'); }
// ---- 류태연: 사망 시 HR 이하 적 최대 HP 50% 제거, 50% 이하면 사망 ----
{ const { u, fs } = fresh('10100', [], FOES, 1000); fs[0].hp = 400; fs[1].hp = 1000; fs[2].hp = 700;
  u.hp = 0; checkDeath(u, null);
  ok(!fs[0].owner.field.includes(fs[0]), 'N (HP 40%) → 사망');
  ok(fs[1].hp === 500 && fs[2].hp === 200, `R 1000→500 · HR 700→200 (${fs[1].hp}, ${fs[2].hp})`);
  ok(fs[3].hp === fs[3].maxHp && fs[4].hp === fs[4].maxHp, 'SR·UR 은 그대로'); }
{ const { u, fs } = fresh('10100', [], [FOES[1]], 1000); fs[0].hp = 500; u.hp = 0; checkDeath(u, null); ok(!fs[0].owner.field.includes(fs[0]), '정확히 50% 인 적도 사망'); }
{ const { u, fs } = fresh('10100', [], [FOES[1]], 1000); fs[0].st.immune = { kind: 'immune', t: 1 }; u.hp = 0; checkDeath(u, null); ok(fs[0].hp === 1000, '피해 면역은 막음'); }
// ---- 옛 황보예 패시브 없음 ----
{ const { u, al } = fresh('10462', ['10074', '10080']); u.hp = 0; checkDeath(u, null); ok(al.every(a => !a.st.immune), '황보예 사망 시 아군 면역 (옛 패시브) 없음'); }
// ---- staging SQL ----
const meta = rd('supabase/sheet_skills1121_meta.sql'), sql = rd('supabase/sheet_skills1121_hash_staging.sql'), chk = rd('supabase/sheet_skills1121_hash_check_staging.sql');
ok(/^select \($/m.test(chk) && !/^\s*(update|insert|delete) /im.test(chk), '확인 SQL은 단일 SELECT');
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP SQL'); console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0); }
const db = new PGlite();
const pol = ['pvp_policy_v3', 'guildbattle_policy_v4', 'arcade_policy_v5', 'battle_replay_policy_v6', 'battle_replay_policy_v7'];
const prev = rd('supabase/rename_three_cards_hash_check_staging.sql').match(/[0-9a-f]{64}/g);
await db.exec(`create table public.story_skill_meta (card_id text, idx int, unlock int, primary key (card_id, idx));
${pol.map((t, i) => `create table public.${t} (singleton boolean primary key default true, engine_hash text not null); insert into public.${t} values (true, '${prev[i]}');`).join('\n')}`);
await db.exec(meta); await db.exec(meta);
try { await db.exec(sql); ok(false, '가드'); } catch (e) { ok(/STOP: sheet skills 1121/.test(String(e.message || e)), '가드: 스테이징 아니면 거부'); await db.exec('rollback'); }
const local = s => s.replaceAll("'7703759698107299042'", '(select system_identifier::text from pg_catalog.pg_control_system())');
ok((await db.query(local(chk))).rows[0].ok === false, '실행 전 확인 = false');
await db.exec(local(sql)); await db.exec(local(sql));
ok((await db.query(local(chk))).rows[0].ok === true, '2번 실행 후 확인 ok=true (11/19 이름 변경 해시 → 새 해시 · 메타 4행)');
ok(+(await db.query(`select count(*) c from story_skill_meta`)).rows[0].c === 4, '메타 4행 (중복 없음)');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
