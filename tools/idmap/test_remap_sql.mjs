// supabase/card_id_remap.sql 검증 (PGlite): 옛 ID 상태 DB(origin/main 의 SQL) → 변경 → 옛 ID 0개 · 데이터·함수·세력전 성별 확인
// 실행: node tools/idmap/test_remap_sql.mjs   (PGlite 는 tools/node_modules)
import { readFileSync } from 'fs';
import { execSync } from 'child_process';
import { createRequire } from 'module';
const require = createRequire(new URL('../package.json', import.meta.url));
let PGlite; try { ({ PGlite } = require('@electric-sql/pglite')); } catch { console.log('SKIP: @electric-sql/pglite 없음'); process.exit(0); }
const db = new PGlite();
const U = '00000000-0000-0000-0000-000000000002', ADMIN = '00000000-0000-0000-0000-000000000001';
await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz, created_at timestamptz default now(), last_sign_in_at timestamptz, raw_user_meta_data jsonb default '{}');
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
grant usage on schema auth to anon, authenticated; grant execute on all functions in schema auth to anon, authenticated; grant usage on schema public to anon, authenticated;
create table public.profiles (id uuid primary key, nickname text);
create table public.matches (id bigint generated always as identity primary key, user_id uuid, result text, reason text, turns int, damage int, mvp_name text, created_at timestamptz default now());
create table public.gallery (user_id uuid, card_id text, count int, mvp_count int);
insert into auth.users (id, email, email_confirmed_at) values ('${U}','u@x.com',now()),('${ADMIN}','stevejean77@gmail.com',now());`);
const REF = process.env.OLD_REF || 'origin/main';   // 옛 ID 상태의 SQL
const old = f => execSync(`git show ${REF}:supabase/${f}`, { cwd: new URL('../..', import.meta.url).pathname, maxBuffer: 1 << 26 }).toString();
// 실제 DB 와 같게: 외래키(sigil_sources → sigil_defs 등)·트리거가 있는 전체 SQL 묶음
const files = ['story.sql', 'gacha.sql', 'story_server.sql', 'story_gacha.sql', 'story_levels.sql', 'story_merge.sql', 'story_ch2.sql', 'story_cards_1022.sql', 'story_leader_lock.sql', 'story_level_stats.sql', 'story_min_battle.sql', 'admin.sql', 'phaseE_1.sql', 'phaseE_2.sql', 'quest.sql', 'quest_sweep.sql', 'phaseE_3.sql', 'phaseE_4.sql', 'phaseE_5.sql', 'story_ch1_reward.sql', 'story_ch0.sql', 'story_ch3.sql', 'story_ch4.sql', 'pvp.sql', 'pvp_tier.sql', 'gem.sql', 'guild.sql', 'guild2.sql', 'guild3.sql', 'guild4.sql', 'guild4_ui.sql', 'tower_v2.sql', 'gear_v1.sql', 'gear_drops.sql', 'gear_craft.sql', 'gear_sigil.sql', 'gear_sigil_story_off.sql', 'gear_shop.sql', 'trade_origin.sql', 'trade_origin_v2.sql', 'trade_drink.sql', 'trade_board.sql', 'trade_admin.sql'];
let skipped = 0;
for (const f of files) { try { await db.exec(old(f)); } catch (e) { skipped++; console.log('setup skip', f, e.message.slice(0, 80)); } }
let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
// 옛 ID 데이터 심기: 저장(owned·starter·routes·키), 도감, 함수(세력전 NPC 덱 — 옛 정의)
await db.exec(`insert into public.story_progress (user_id, data) values ('${U}', '{"starter":"2000600126","owned":[{"uid":"a","id":"2000100001","level":3},{"uid":"b","id":"2001800345"}],"routes":{"2":"1000600122"},"seen":{"2000100001_0":true},"n":2000100003,"keep":"x12000100001"}'::jsonb)
  on conflict (user_id) do update set data = excluded.data;
insert into public.gallery values ('${U}','2000100001',1,0);
create table public.t_arr (a text[]); insert into public.t_arr values (array['2000000038','zzz']);
create or replace function public._war_npc_deck(p_seed text, p_scale numeric) returns jsonb language plpgsql stable as $f$
declare hr text[] := array['1000000031','1000000032','2000000033','2000000034','2000000035','2000000036','2000000037','2000000038'];
        r text[] := array['1000000028','1000000029','1000000030','2000000029','2000000030','2000000031','2000000032'];
        a text[]; b text[]; ids text[]; alt text; out jsonb := '[]'::jsonb; i int;
begin
  select array_agg(x order by md5(p_seed || ':h:' || x)) into a from unnest(hr) x;
  select array_agg(x order by md5(p_seed || ':r:' || x)) into b from unnest(r) x;
  ids := a[1:2] || b[1:3];
  if (select count(distinct left(x, 1)) from unnest(ids) x) < 2 then
    select x into alt from unnest(b[4:7]) x where left(x, 1) <> left(ids[1], 1) limit 1; ids[5] := alt; end if;
  for i in 1..5 loop out := out || jsonb_build_object('uid', 'n' || i, 'id', ids[i], 'level', 10, 'scale', p_scale); end loop;
  return out;
end $f$;
create or replace function public._war_numbers() returns jsonb language sql as $f$ select '{"npc_level":10}'::jsonb $f$;`);
// 실제 DB 가 다를 경우 대비: 증표 카드 ID 를 bigint 로 바꾼 상태로도 확인 (외래키·열 종류 무관하게 처리되는지)
if (process.env.SIGIL_BIGINT !== '0') await db.exec(`
  alter table public.sigil_sources drop constraint sigil_sources_card_id_fkey; alter table public.player_sigils drop constraint player_sigils_card_id_fkey; alter table public.sigil_story_boss drop constraint sigil_story_boss_card_id_fkey;
  alter table public.sigil_defs alter column card_id type bigint using card_id::bigint; alter table public.sigil_sources alter column card_id type bigint using card_id::bigint;
  alter table public.player_sigils alter column card_id type bigint using card_id::bigint; alter table public.sigil_story_boss alter column card_id type bigint using card_id::bigint;
  alter table public.sigil_sources add constraint sigil_sources_card_id_fkey foreign key (card_id) references public.sigil_defs(card_id);
  alter table public.player_sigils add constraint player_sigils_card_id_fkey foreign key (card_id) references public.sigil_defs(card_id);
  alter table public.sigil_story_boss add constraint sigil_story_boss_card_id_fkey foreign key (card_id) references public.sigil_defs(card_id);`);
const fks = (await db.query(`select conname from pg_constraint where contype = 'f' and confrelid = 'public.sigil_defs'::regclass`)).rows.map(r => r.conname);
ok(fks.length > 0, `sigil_defs 를 가리키는 외래키 ${fks.length}개 (${fks})`);
const sig0 = (await db.query(`select count(*)::int n from public.sigil_sources`)).rows[0].n;
ok(sig0 > 0, `sigil_sources ${sig0}줄 (옛 ID)`);
const fkAll = async () => (await db.query(`select conrelid::regclass::text || '.' || conname || ' ' || pg_get_constraintdef(oid) d from pg_constraint where contype = 'f' order by 1`)).rows.map(r => r.d).join('\n');
const trgOn = async () => (await db.query(`select count(*)::int n from pg_trigger where not tgisinternal and tgenabled <> 'D'`)).rows[0].n;
const fk0 = await fkAll(), trg0 = await trgOn();
const before = (await db.query(`select reward_card from public.story_phase_config where chapter = 0 order by phase`)).rows.map(r => r.reward_card);
ok(before.join() === '2000100006,2000100004,2000900206', `변경 전 챕터0 보상 = 옛 ID (${before})`);
await db.exec(readFileSync(new URL('../../supabase/card_id_remap.sql', import.meta.url), 'utf8'));
await db.exec(readFileSync(new URL('../../supabase/card_id_remap.sql', import.meta.url), 'utf8'));   // 같은 세션 다시 실행해도 안전 (바뀔 것 없음)
const MIG = readFileSync(new URL('../../supabase/card_id_remap.sql', import.meta.url), 'utf8');
ok((await fkAll()) === fk0, '외래키 전부 원래 정의 그대로 다시 생김');
ok((await trgOn()) === trg0 && trg0 > 0, `사용자 트리거 ${trg0}개 다시 켜짐`);
const sig = (await db.query(`select count(*)::int n, count(*) filter (where card_id::text ~ '^1[0-9]{4}$')::int ok from public.sigil_sources`)).rows[0];
ok(sig.n === sig0 && sig.ok === sig0, `sigil_sources ${sig.ok}/${sig.n} 새 ID`);
const d = (await db.query(`select data from public.story_progress where user_id='${U}'`)).rows[0].data;
ok(d.starter === '10426' || /^1\d{4}$/.test(d.starter), `starter → ${d.starter}`);
ok(d.owned[0].id === '10325' && d.owned[1].id === '10231', `owned → ${d.owned.map(o => o.id)}`);
ok(d.routes['2'] && /^1\d{4}$/.test(d.routes['2']), `routes → ${JSON.stringify(d.routes)}`);
ok(d.seen['10325_0'] === true, 'JSON 키 안의 옛 ID (2000100001_0 → 10325_0)');
ok(d.n === 10300, `숫자 값 → ${d.n}`);
ok(d.keep === 'x12000100001', '더 긴 숫자 안은 그대로');
ok((await db.query(`select card_id from public.gallery`)).rows[0].card_id === '10325', '도감 card_id');
ok((await db.query(`select a from public.t_arr`)).rows[0].a.join() === '10168,zzz', '글자 배열');
const after = (await db.query(`select reward_card from public.story_phase_config where chapter = 0 order by phase`)).rows.map(r => r.reward_card);
ok(after.join() === '10328,10333,10206' || after.every(x => /^1\d{4}$/.test(x)), `챕터0 보상 → ${after}`);
const fsrc = (await db.query(`select prosrc from pg_proc where proname = '_war_npc_deck'`)).rows[0].prosrc;
ok(!/\d{10}/.test(fsrc) && /male/.test(fsrc), '세력전 NPC 덱: 새 ID + 성별 목록');
const male = new Set(['10148', '10149', '10150', '10151', '10152']);
let mixed = true; for (let s = 0; s < 40; s++) { const deck = (await db.query(`select public._war_npc_deck('s${s}', 1) d`)).rows[0].d.map(x => x.id); if (new Set(deck.map(x => male.has(x))).size < 2) mixed = false; }
ok(mixed, '세력전 NPC 덱 40개 모두 남녀 섞임');
const left = (await db.query(`select count(distinct p.oid)::int n from pg_proc p join pg_namespace n on n.oid = p.pronamespace join public.card_id_alias a on p.prosrc ~ ('(^|[^0-9])' || a.old_id || '([^0-9]|$)') where n.nspname = 'public'`)).rows[0].n;
ok(left === 0, `옛 ID 남은 함수 ${left}개`);
const rep = (await db.query(`select * from idremap_result order by kind, name`)).rows; console.log(rep.length, '항목 보고:', rep.slice(0, 8).map(r => `${r.kind} ${r.name} ${r.before_n}→${r.after_n}`).join(' | '));
ok((await db.query(`select count(*)::int n from public.card_id_alias`)).rows[0].n === 474, '대응표 474');
ok(rep.filter(r => r.kind === 'column').length === 0, '두 번째 실행: 바뀐 열 0 (이미 새 ID)');
console.log(fails ? `${fails} FAILED` : 'ALL PASS'); process.exit(fails ? 1 : 0);
