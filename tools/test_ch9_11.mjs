// supabase/story_ch9_11.sql 검증 + 챕터 9~11 데이터 검사 (PGlite, 실제 스토리·퀘스트 SQL 위에서). 실행: NODE_PATH=<pglite 설치 경로> node tools/test_ch9_11.mjs
import { readFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const U = '00000000-0000-0000-0000-000000000002', M = '00000000-0000-0000-0000-000000000004';
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${M}','m@x.com',now());`);
const run = f => db.exec(readFileSync(new URL('../supabase/' + f, import.meta.url), 'utf8'));
for (const f of ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_level_stats.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_min_battle.sql', 'quest.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'phaseE_3.sql']) await run(f);
await run('phaseE_4.sql'); await run('phaseE_5.sql'); await run('story_ch3.sql'); await run('story_ch4.sql'); await run('story_ch6.sql'); await run('story_ch7.sql'); await run('story_ch8.sql'); await run('story_ch9_11.sql'); await run('story_ch9_11.sql'); await run('story_ch10_rev.sql'); await run('story_ch11_wings.sql'); await run('story_ch11_p1_5.sql');
async function as(role, claims, sql) {
  await db.exec(`reset role; select set_config('request.jwt.claims', '${JSON.stringify(claims || {})}', false); set role ${role};`);
  try { return { rows: (await db.query(sql)).rows }; } catch (e) { return { err: e.message }; } finally { await db.exec('reset role'); }
}
// --- 데이터 ---
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
globalThis.window = { STORY_DATA: { chapters: [] } };
for (const c of [3, 9, 10, 11]) eval(readFileSync(new URL(`../js/story-data-ch${c}.js`, import.meta.url), 'utf8'));
const CH = Object.fromEntries(window.STORY_DATA.chapters.map(c => [c.id, c]));
const csv = f => Object.fromEntries(readFileSync(new URL('../data/' + f, import.meta.url), 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).slice(1).map(l => l.split(',')).map(v => [v[0], v]));
const cards = { ...csv('npc_cards.csv'), ...csv('cards.csv') }, nm = id => cards[id]?.[1];
const N = { 9: 18, 10: 17, 11: 16 }, SUBT = { 9: '기도', 10: '마지막 랠리', 11: '사라지지 않는 약속' };
for (const c of [9, 10, 11]) { const ch = CH[c];
  ok(ch && ch.phases.length === N[c] && ch.subtitle === SUBT[c] && ch.single && ch.phases.every((p, i) => p.no === i + 1) && ch.phases.at(-1).type === 'boss' && ch.phases.filter(p => p.type === 'boss').length === 1, `CH${c} · ${N[c]} 페이즈 · 마지막 보스`);
  ok(ch.phases.every(p => p.enemies.ids.length >= 1 && p.enemies.ids.length <= 5 && p.enemies.ids.every(nm) && Object.values(p.enemies.boost).every(b => b.HP > 0 && b.storyLv >= 40)), `CH${c} 적 카드·레벨`);
  const all = [...ch.start, ...ch.phases.flatMap(p => [...p.lines.default, ...(p.after || [])])];
  ok(all.length > 200 && all.every(l => l.speaker && !/^(NA|아빠|불량배[A-Z])$/.test(l.speaker)), `CH${c} 화자 (${all.length}줄)`);
}
const yh = (c, n) => [...(CH[c].phases[n - 1].lines.default), ...(CH[c].phases[n - 1].after || [])].filter(l => l.speaker === '최윤희').map(l => l.slug);
ok(CH[9].start.filter(l => l.speaker === '최윤희').every(l => l.slug === 'choi_yunhee_school') && yh(9, 4).every(s => s === 'choi_yunhee_home') && yh(9, 3).every(s => s === 'choi_yunhee_casual') && yh(10, 1).every(s => s === 'choi_yunhee_kid') && yh(11, 7).every(s => s === 'choi_yunhee_casual'), '최윤희 복장 (교복·홈웨어·일상복·딩초)');
ok(CH[11].loan?.join() === '10491' && CH[11].phases[4].party.levels['10491'] === 74, 'CH11 [염원] 최윤정 대여 (페이즈 레벨)');
ok(CH[11].phases[14].party.forced.join() === '10415' && CH[11].phases[14].party.maxGrade === 'RARE' && CH[11].phases[14].joinAlly?.id === '10311' && CH[11].phases[14].joinAlly.storyLevel === 100, 'CH11 P15 최윤희 · HR 이상 불가 · 1턴 후 이지영 Lv100 난입');
ok(CH[11].phases[15].party.solo && CH[11].phases[15].party.forced.join() === '10311' && CH[11].phases[12].enemies.ids.join() === '10504' && CH[11].phases[13].enemies.ids.join() === '10503', 'CH11 P16 이지영 단독 · P13 왼쪽 날개 · P14 오른쪽 날개');
ok(CH[9].phases[2].party.exclude.join() === '10415' && CH[10].phases[3].party.exclude.join() === '10413' && CH[9].phases[0].party.noMale, '출전 금지 · 남성 불가');
ok(CH[9].endingVideo === 'SZOOuvc5nak' && CH[10].endingVideo === '1egJLy6rkPw' && CH[11].endingVideo === 'w7kJ9vfJSgo', '엔딩 영상 9~11');
ok(CH[3].loan?.sort().join() === '10383,10384', 'CH3 조윤하·조윤이 대여');
const sk = JSON.parse(readFileSync(new URL('../data/skills.json', import.meta.url), 'utf8'));
ok(sk['10490'].some(s => s.name === '지켜주고 싶어' && s.mode === 'passive') && ['너무너무 사랑해', '절대 무너지지 마'].every(n => sk['10491'].some(s => s.name === n && s.mode === 'passive')), '패시브 3종 데이터');
const me = { sub: U, email: 'u@x.com' }, q = s => as('authenticated', me, s);
const cfg = (await db.query(`select chapter, count(*)::int n, sum((type = 'boss')::int)::int b from public.story_phase_config where chapter between 9 and 11 group by chapter order by chapter`)).rows;
ok(cfg.map(r => `${r.chapter}:${r.n}:${r.b}`).join() === '9:18:1,10:17:1,11:16:1', `페이즈 설정 (멱등) ${JSON.stringify(cfg)}`);
await q(`select public.story_choose_starter('10111')`); await q('select public.player_status()');
await db.exec(`update public.player_state set stamina = 999, level = 10 where user_id='${U}'`);
ok(/phase locked/.test((await q('select public.story_start_phase(9, 1)')).err || ''), '챕터 8 미완료 시 9장 잠김');
await db.exec(`update public.story_progress set data = jsonb_set(data, '{cleared}', (select jsonb_object_agg(chapter::text, ps) from (select chapter, jsonb_agg(phase) ps from public.story_phase_config where chapter < 9 group by chapter) x)) where user_id='${U}'`);
let t0 = (await q('select public.story_tickets() r')).rows?.[0]?.r?.tickets | 0;
for (const c of [9, 10, 11]) {
  if (c < 11) ok(/phase locked/.test((await q(`select public.story_start_phase(${c + 1}, 1)`)).err || ''), `${c}장 미완료 시 ${c + 1}장 잠김`);
  let good = true;
  for (let n = 1; n <= N[c]; n++) {
    await db.exec(`update public.player_state set stamina = 999 where user_id='${U}'`);
    let r = await q(`select public.story_start_phase(${c}, ${n}) r`); if (r.err) { ok(false, `${c}-${n} 시작 (${r.err})`); good = false; break; }
    await db.exec(`update public.story_progress set data = jsonb_set(data, '{battle,at}', to_jsonb((extract(epoch from now()) - 600)::bigint)) where user_id='${U}'`);
    r = await q(`select public.story_complete_phase(${c}, ${n}, '[]'::jsonb) r`); if (!r.rows?.[0]?.r?.first) { ok(false, `${c}-${n} 클리어 (${r.err || ''})`); good = false; break; }
  }
  const t = (await q('select public.story_tickets() r')).rows?.[0]?.r;
  ok(good && (t.tickets | 0) - t0 === 10, `${c}장 ${N[c]}페이즈 클리어 → 소환권 +10`); t0 = t.tickets | 0;
}
ok(/permission denied/.test((await as('anon', {}, 'select public.story_start_phase(9, 1)')).err || ''), 'anon 불가');
console.log(fails ? `${fails} FAIL` : 'ALL OK'); process.exit(fails ? 1 : 0);
