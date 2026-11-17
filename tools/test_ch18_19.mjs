// 디버그 64번 (11/17): CH18·19 데이터 · 신규 카드 10533~10543 · NPC 스킬 10종 · 16-1 어린 최국선 · staging SQL (PGlite)
// 실행: node tools/test_ch18_19.mjs
import { readFileSync, existsSync } from 'fs';
import { createRequire } from 'module';
import { setSkillData, setEmitter, setRng, initPlayers, placeUnit, refreshAll, useSkill, ACTIVE } from '../js/skills.js';
import { parseCSV, makeUnit, setCardPool } from '../js/rules.js';
const rd = f => readFileSync(new URL('../' + f, import.meta.url), 'utf8');
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
const cards = parseCSV(rd('data/cards.csv')), npcs = parseCSV(rd('data/npc_cards.csv')), pool = [...cards, ...npcs];
const SK = JSON.parse(rd('data/skills.json'));
setCardPool(pool); setSkillData(SK, JSON.parse(rd('data/combos.json'))); setEmitter(() => {});
const C = id => pool.find(c => String(c.id) === String(id));
// ---- 카드 ----
ok(cards.some(c => c.id == 10533) && !npcs.some(c => c.id == 10533) && C(10533).grade === 'RARE' && !SK['10533'], '우승찬 10533: 플레이어 카드(시트 NPC 칸 빈칸) · R · 스킬 없음');
const NPC = Array.from({ length: 10 }, (_, i) => String(10534 + i));
ok(NPC.every(id => npcs.some(c => String(c.id) === id && c.npc == 1)) && NPC.every(id => !cards.some(c => String(c.id) === id)), 'NPC 10534~10543 npc_cards.csv (뽑기 아님)');
ok(C(10537).age == 7 && C(10538).age == 7 && C(10535).age == 9, '어린 민지은·장초롱 7살 (형님 답변, 시트는 16) · 어린 임예리 9살');
ok(['경호원A', '경호원B', '경호원C', '경호원D', '경호원E'].every((n, i) => C(10539 + i).name === n) && C(10543).grade === 'SUPER RARE' && C(10542).HP == 240, '경호원A~E 시트 스탯');
ok(C(10534).base_id == 10118 && C(10536).base_id == 10406, '[상념] 민홍기·어린 최국선 base_id');
const fallback = rd('js/img-fallback.js');
for (const id of ['10533', ...NPC]) ok(existsSync(new URL(`../img/npc/${id}.webp`, import.meta.url)) && existsSync(new URL(`../img/thumb/${id}.webp`, import.meta.url)) && fallback.includes(`'${id}'`), `${id} 프로필 img/npc + thumb + OVERRIDE`);
// ---- NPC 스킬 (시트 284~293행) ----
const NS = ['10534', '10535', '10536', '10537', '10538'].flatMap(id => (SK[id] || []).map(s => ({ id, s })));
ok(NS.length === 10 && NS.every(({ s }) => s.mode === 'active' && ACTIVE[s.name]) && NS.every(({ id, s }) => s.fx.startsWith(id + '_') && existsSync(new URL('../data/fx/' + s.fx, import.meta.url))), 'NPC 스킬 10개 · 액티브 구현 · fx 존재');
let R = 0.5; setRng(() => R);
const foesM = pool.filter(c => c.gender === 'MALE' && c.class !== 'LIGHT' && c.HP > 0 && !NPC.includes(String(c.id))).slice(0, 2);
const foesF = pool.filter(c => c.gender === 'FEMALE' && c.class !== 'LIGHT' && c.HP > 0 && !NPC.includes(String(c.id))).slice(0, 3);
function fresh(id, allies = [], foes = [...foesM, ...foesF], hp = 99999) {
  const A = { name: 'A', hp: 9999, field: [], hand: [], deck: [], grave: [], mana: 0 }, B = { name: 'B', hp: 9999, field: [], hand: [], deck: [], grave: [], mana: 0 };
  initPlayers(A, B, A);
  const u = placeUnit(A, C(id), makeUnit); u.level = 10; u.mp = 999;
  const al = allies.map(c => placeUnit(A, C(c), makeUnit));
  const fs = foes.map(c => placeUnit(B, { ...c, HP: hp }, makeUnit)); refreshAll(A);
  return { A, B, u, al, fs };
}
const use = (u, id, name) => { u.canAttack = true; u.mp = 999; u.cd = {}; return useSkill(u, SK[id].find(s => s.name === name)); };
for (const { id, s } of NS) { R = 0.5; const { u } = fresh(id); let r; try { r = use(u, id, s.name); } catch (e) { r = { ok: false, reason: e.message }; } ok(r.ok, `${id} ${s.name} 실행 ${r.ok ? '' : r.reason}`); }
{ R = 0.05; const { u, fs } = fresh('10534'); use(u, '10534', '용서가...안...되는...데?'); ok(fs.every(t => t.hp < t.maxHp) && fs.every(t => t.st.confuse), '[상념] 민홍기: 적 전체 피해 + 확률 성공 시 혼란');
  R = 0.5; const o = fresh('10534'); use(o.u, '10534', '절대...복수한...다...'); ok(o.fs.every(t => !t.st.confuse), '10% 실패 시 혼란 없음'); }
{ R = 0.5; const { u, fs } = fresh('10536'); const top = fs.reduce((a, t) => (t.card.ATK > a.card.ATK ? t : a)); const i = fs.indexOf(top);
  use(u, '10536', '아무것도 느낄 수 없어!'); const hit = fs.filter(t => t.hp < t.maxHp); ok(hit.includes(top) && hit.every(t => Math.abs(fs.indexOf(t) - i) <= 1) && hit.length === [fs[i - 1], top, fs[i + 1]].filter(Boolean).length, '어린 최국선: 공격력 최고 + 양 옆만'); }
{ R = 0.5; const lowMor = pool.find(c => c.gender === 'FEMALE' && +c.MOR < 75 && c.HP > 0), male = pool.find(c => c.gender === 'MALE' && +c.MOR >= 75 && c.HP > 0);
  const { u, al } = fresh('10537', ['10538', lowMor.id, male.id]); use(u, '10537', '이정도는 가뿐하다고요!');
  ok(u.st.immune && al[0].st.immune && !al[1].st.immune && !al[2].st.immune, '어린 민지은: 품성 75 이상 아군 여성만 피해 면역'); }
{ R = 0.5; const { u, fs } = fresh('10535', [], [...foesM, ...foesF], 1); const cd0 = SK['10535'][2].cooldown; use(u, '10535', '이게 여러분의 선택인가요?'); ok(fs.every(t => t.hp <= 0) && u.cd['이게 여러분의 선택인가요?'] === Math.max(0, cd0 + 1 - fs.length) || u.cd['이게 여러분의 선택인가요?'] < cd0, '어린 임예리 3스킬: 처치 수만큼 쿨타임 감소'); }
// ---- 스토리 데이터 ----
globalThis.window = { STORY_DATA: { chapters: [] } };
for (const f of ['js/story-data.js', 'js/story-data-ch16.js', 'js/story-data-ch18.js', 'js/story-data-ch19.js']) eval(rd(f));
const D = window.STORY_DATA, c16 = D.chapters.find(c => c.id === 16), c18 = D.chapters.find(c => c.id === 18), c19 = D.chapters.find(c => c.id === 19);
const P = (ch, n) => ch.phases.find(p => p.no === n);
ok(rd('index.html').includes('js/story-data-ch18.js') && rd('index.html').includes('js/story-data-ch19.js'), 'index.html 에 CH18·19 스크립트');
ok(c18.phases.length === 16 && c18.subtitle === 'BITTERSWEET' && c18.hero === '10324' && c18.endingVideo === 'aqNDjoJVPk4', 'CH18 16페이즈 · BITTERSWEET · 임예리 · 엔딩');
ok(c19.phases.length === 13 && c19.subtitle === '한니발라이징' && c19.hero === '10118' && c19.endingVideo === 'YqHloiQZ-QM', 'CH19 13페이즈 · 한니발라이징 · 민홍기 · 엔딩');
ok(/자살/.test(c19.warning) && c18.warning, 'CH19 콘텐츠 주의 (19-8)');
ok([2, 10, 11, 14].every(n => P(c18, n).scene) && [2, 4, 6].every(n => P(c19, n).scene), '대사 전용 페이즈 (18-2·10·11·14 · 19-2·4·6)');
ok([...c18.phases, ...c19.phases].filter(p => !p.scene).every(p => p.enemies.ids.every(id => C(id))), '전투 적 카드 모두 존재');
ok(P(c18, 15).type === 'boss' && P(c18, 15).bossId === '10324' && P(c18, 15).enemies.ids.join() === '10324,10341,10117' && P(c18, 15).party.solo, '18-15 임예리 진영 보스 · 김성진 단독');
ok(P(c19, 13).type === 'boss' && P(c19, 13).enemies.ids.every(id => id === '10534') && P(c19, 13).enemies.ids.length === 4 && P(c19, 13).rules.revive[0].id === '10534' && P(c19, 13).rules.revive[0].delay === 2 && !P(c19, 13).rules.revive[0].times, '19-13 [상념] 민홍기 ×4 진영 보스 · 2턴 후 부활 (무제한)');
ok(P(c18, 3).party.forced[0] === '10535' && P(c18, 3).party.maxGrade === 'SUPER RARE' && P(c18, 3).party.exclude.join() === '10324,10341,10117', '18-3 어린 임예리(UR) 필수 · UR 이상 금지 · 임예리·장초롱·민지은 금지');
ok(P(c18, 5).rules.survive === 6 && !P(c18, 5).rules.maxTurns && P(c18, 5).party.mustLive.length === 0 && P(c18, 5).party.noMale, '18-5 6턴 생존 · 남성 금지');
ok(P(c18, 1).mana === 60 && P(c18, 3).mana === 150 && P(c19, 1).mana === 100 && P(c19, 13).mana === 60, '초기 마나 (전투정리2)');
ok(P(c19, 8).party.exclude.join() === '10115' && P(c19, 9).enemies.ids.join() === '10542,10539,10539,10539,10539', '19-8 민유연 금지 · 19-9 경호원D+A');
ok(P(c16, 1).party.forced.join() === '10536' && P(c16, 1).party.mustLive.join() === '10536' && P(c16, 2).party.forced.join() === '10406', '16-1(강두식전) 어린 최국선 필수 · 16-2부터 최국선');
// 필수 카드는 등급 금지 예외 (클라 partyOf · 서버 security_phase2)
ok(/필수 카드는 조건 예외/.test(rd('js/story.js')) && /not forced @> to_jsonb\(cid\)[\s\S]{0,1200}maxGrade/.test(rd('supabase/security_phase2_clears.sql')), '필수 출전 카드는 UR 이상 금지 예외 (클라·서버)');
// 초상화: 시트 화자·표정 → 파일
const pslug = (ch, nm) => D.chapterPortraits?.[ch]?.[nm] || D.portraits?.[nm];
const miss = new Set();
for (const ch of [c18, c19]) for (const L of [...ch.start, ...ch.phases.flatMap(p => [...(p.lines?.default || []), ...(p.after || [])])]) {
  const s = L.slug || pslug(ch.id, L.speaker); if (!s) continue;
  const ex = D.exprSlug[String(L.expr || '').trim()] || 'base';
  if (![`${s}_${ex}`, `${s}_${D.exprAlt?.[ex]}`, `${s}_base`].some(f => existsSync(new URL(`../img/story/portraits/${f}.webp`, import.meta.url)))) miss.add(`${L.speaker}:${ex}`);
}
ok(miss.size === 0, `CH18·19 화자 초상화 파일 (${[...miss].join(', ')})`);
ok(pslug(19, '아버지 민왕표') === 'min_wangpyo' && pslug(19, '어머니 이미연') === 'lee_miyeon' && pslug(7, '유연 아버지') === 'min_wangpyo' && pslug(18, '어린 임예리') === 'im_yeri_child', '민왕표·이미연 (CH7 유연 부모 포함) · 어린 임예리 챕터 전용');
ok(existsSync(new URL('../img/story/portraits/min_honggi_smile.webp', import.meta.url)) && D.exprSlug['부상'] === 'hurt', '민홍기 미소 · 부상→hurt');
// ---- staging SQL (PGlite) ----
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP SQL: @electric-sql/pglite 없음'); console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0); }
delete globalThis.window;   // PGlite 는 window 가 있으면 브라우저로 판단
const db = new PGlite();
const sql = rd('supabase/story_ch18_19_staging.sql'), chk = rd('supabase/story_ch18_19_check_staging.sql');
const pol = ['pvp_policy_v3', 'guildbattle_policy_v4', 'arcade_policy_v5', 'battle_replay_policy_v6', 'battle_replay_policy_v7'];
const old66 = rd('supabase/sheet_skills66_hash_check_staging.sql').match(/[0-9a-f]{64}/g);
await db.exec(`create table public.story_phase_config (chapter int, phase int, type text, points int, reward_grade text, enemy_count int, primary key (chapter, phase));
create table public.story_card_pool (id text primary key, grade text, name text, gacha boolean);
create table public.reward_card_catalog (card_id text primary key references public.story_card_pool(id));
create table public.pvp_card_meta (id text primary key, grade text, cost int);
create table public.battle_story_defs_v2 (chapter int, phase int, variant text default '', definition jsonb not null, primary key (chapter, phase, variant));
create table public.battle_card_meta_v2 (id text primary key, definition jsonb);
${pol.map((t, i) => `create table public.${t} (singleton boolean primary key default true, engine_hash text not null); insert into public.${t} values (true, '${old66[i]}');`).join('\n')}`);
try { await db.exec(sql); ok(false, '가드: 스테이징 아니면 거부'); } catch (e) { ok(/STOP: story ch18\/19/.test(String(e.message || e)), '가드: 스테이징 아니면 거부'); await db.exec('rollback'); }
const local = s => s.replaceAll("'7703759698107299042'", '(select system_identifier::text from pg_catalog.pg_control_system())');
await db.exec(local(sql)); await db.exec(local(sql));
ok((await db.query(local(chk))).rows[0].ok === true, '실행 2번 (멱등) 후 확인 SQL ok=true · 66번 해시 → 새 해시');
ok(/^select \($/m.test(chk) && !/^\s*(update|insert|delete) /im.test(chk), '확인 SQL은 단일 SELECT');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
