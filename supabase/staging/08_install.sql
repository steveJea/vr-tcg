-- ⚠ 테스트 전용 8/12. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
-- 대상 프로젝트: cuyqchmdcnsgzkwyclji; 운영 htarwisgkkphutxxnuak 금지.
-- 완료한 파일은 다시 실행해도 건너뜀. 중간 오류는 해당 파일만 되돌아감.
-- 실제 project_ref는 SQL Editor가 보장해서 제공하지 않음: DB 고유번호를 대조.
-- 지정 테스트 DB의 식별번호와 일치할 때만 허용. guard 삭제/SET 우회 금지.
-- docs/STAGING.md 및 supabase/staging/README.md 먼저 확인.

begin;
do $vr_project_guard$
declare
  confirmed_ref text := 'cuyqchmdcnsgzkwyclji';
  expected_db_id text := '7703759698107299042';
  actual_db_id text;
begin
  if confirmed_ref is distinct from 'cuyqchmdcnsgzkwyclji' or confirmed_ref = 'htarwisgkkphutxxnuak' then
    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';
  end if;
  if expected_db_id !~ '^[0-9]{16,20}$' then
    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';
  end if;
  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();
  if actual_db_id is distinct from expected_db_id then
    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';
  end if;
exception when insufficient_privilege or undefined_function then
  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';
end $vr_project_guard$;

-- 설치 기록은 API에서 접근할 수 없는 별도 스키마에 저장.
select pg_advisory_xact_lock(20261107, 490);
create schema if not exists vr_staging_install;
revoke all on schema vr_staging_install from public, anon, authenticated;
create table if not exists vr_staging_install.parts (
  part_no integer primary key, bundle_hash text not null, part_hash text not null,
  project_ref text not null, db_id text not null, applied_at timestamptz not null default now()
);
alter table vr_staging_install.parts enable row level security;
revoke all on vr_staging_install.parts from public, anon, authenticated;
set local check_function_bodies = off;

do $vr_install_part$
begin
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '410cdea919d7fef2dc1c1430be099965278672866ca01148fb8f0da2240951aa' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 8) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 8 and part_hash = '88b786d177f12a46ca801845bbeb154575ba785421933e5efbc0d107939c19ad') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '08_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 8) <> 7 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (08_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$alter table public.friend_battles enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.friend_battles from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._fb_daily_max() returns int language sql immutable as $$ select 20 $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_battle_start(p_friend uuid, p_mode text default '1v1') returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; used int; mine jsonb := '[]'::jsonb; osnap jsonb; d record; seed bigint; aid bigint; oname text;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_mode not in ('1v1','3v3') then raise exception 'bad mode'; end if;
  n := _pvp_ok('open', p_mode);
  if p_friend is null or not _is_friend(uid, p_friend) then raise exception 'not friends'; end if;
  perform pg_advisory_xact_lock(hashtext('fb:' || uid::text));
  select count(*) into used from friend_battles where user_id = uid and day = _pvp_day();
  if used >= _fb_daily_max() then raise exception 'no attempts left'; end if;
  if (select count(*) from pvp_decks where user_id = uid and league = 'open' and mode = p_mode) < n then raise exception 'deck required'; end if;
  if (select count(*) from pvp_decks where user_id = p_friend and league = 'open' and mode = p_mode and slot < n) < n then raise exception 'friend deck missing'; end if;
  for d in select * from pvp_decks where user_id = uid and league = 'open' and mode = p_mode and slot < n order by slot loop
    mine := mine || jsonb_build_array(_pvp_snap(uid, d.uids, 'open')->'cards');
  end loop;
  select coalesce(jsonb_agg(snap order by slot), '[]'::jsonb) into osnap from pvp_decks where user_id = p_friend and league = 'open' and mode = p_mode and slot < n;
  oname := coalesce((select nickname from profiles where id = p_friend), '플레이어');
  seed := floor(random() * 2147483647)::bigint;
  insert into friend_battles (user_id, opp_user, mode, day, seed, my_snap, opp_snap)
  values (uid, p_friend, p_mode, _pvp_day(), seed, mine, osnap) returning id into aid;
  return jsonb_build_object('id', aid, 'seed', seed, 'mode', p_mode, 'me', mine, 'opp', osnap, 'opp_name', oname, 'opp_user', p_friend,
    'left', _fb_daily_max() - used - 1);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.friend_battle_report(p_id bigint, p_wins int, p_losses int, p_actions jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a friend_battles; need int; v_win boolean; x jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from friend_battles where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if now() - a.created_at > interval '1 hour' then raise exception 'expired'; end if;
  need := case when a.mode = '3v3' then 2 else 1 end;
  if p_wins is null or p_losses is null or p_wins < 0 or p_losses < 0 or p_wins > need or p_losses > need
     or not (p_wins = need or p_losses = need) or (p_wins = need and p_losses = need) then raise exception 'bad result'; end if;
  if p_actions is not null and jsonb_typeof(p_actions) <> 'null' then
    if jsonb_typeof(p_actions) <> 'array' or jsonb_array_length(p_actions) > 3 or octet_length(p_actions::text) > 131072 then raise exception 'bad actions'; end if;
    for x in select value from jsonb_array_elements(p_actions) loop
      if not _battle_acts_ok(x, 20 * 6 + 5) then raise exception 'bad actions'; end if;
    end loop;
  else p_actions := null; end if;
  v_win := p_wins = need;
  update friend_battles set reported_at = now(), wins = p_wins, losses = p_losses, win = v_win, actions = p_actions, manual = p_actions is not null where id = a.id;
  return jsonb_build_object('ok', true, 'id', a.id, 'win', v_win, 'record', (
    select jsonb_build_object('w', count(*) filter (where (user_id = uid and win) or (opp_user = uid and not win)),
                              'l', count(*) filter (where (user_id = uid and not win) or (opp_user = uid and win)))
    from friend_battles where reported_at is not null and ((user_id = uid and opp_user = a.opp_user) or (user_id = a.opp_user and opp_user = uid))));
end $$;$vr_statement$;
  execute $vr_statement$-- 전적: p_friend 를 주면 그 친구와의 기록 (공격·방어 모두), 없으면 친구별 승패 요약
create or replace function public.friend_battle_history(p_friend uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  if p_friend is null then
    return jsonb_build_object('ok', true, 'left', greatest(0, _fb_daily_max() - (select count(*) from friend_battles where user_id = uid and day = _pvp_day())::int),
      'records', (select coalesce(jsonb_object_agg(o, jsonb_build_object('w', w, 'l', l)), '{}'::jsonb) from (
        select case when user_id = uid then opp_user else user_id end o,
               count(*) filter (where (user_id = uid and win) or (opp_user = uid and not win)) w,
               count(*) filter (where (user_id = uid and not win) or (opp_user = uid and win)) l
        from friend_battles where reported_at is not null and (user_id = uid or opp_user = uid) group by 1) t));
  end if;
  if not _is_friend(uid, p_friend) then raise exception 'not friends'; end if;
  return jsonb_build_object('ok', true, 'battles', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'attack', user_id = uid, 'mode', mode,
      'win', case when user_id = uid then win else not win end, 'wins', wins, 'losses', losses, 'manual', manual, 'at', created_at) order by id desc), '[]'::jsonb)
    from (select * from friend_battles where reported_at is not null and ((user_id = uid and opp_user = p_friend) or (user_id = p_friend and opp_user = uid))
          order by id desc limit 30) b));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.friend_battle_start(uuid, text), public.friend_battle_report(bigint, int, int, jsonb), public.friend_battle_history(uuid) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.friend_battle_start(uuid, text), public.friend_battle_report(bigint, int, int, jsonb), public.friend_battle_history(uuid) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: daily.sql =====
-- =====================================================================
-- 📅 일일 미션 + 출석 보상 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: phaseE_1.sql(_wallet_add) · gem.sql(_gem_add, _gem_day) · story_gacha.sql(소환권)
-- 초기화: 한국 시간 00:00 (_gem_day). 보상 지급은 전부 서버 (클라이언트는 미션 키만 보냄)
-- 진행 기록은 클라이언트가 전투 끝에 daily_track 으로 알림 → 서버가 목표치에서 잘라 저장 (1회 호출당 상한)
-- 공개 RPC: daily_status() · daily_track(kind, n) · daily_claim(key) · attend_claim()
-- 확인용: select public.daily_status();
-- =====================================================================

create table if not exists public.daily_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null,
  prog    jsonb not null default '{}'::jsonb,   -- { win: 2, skill: 7, ... }
  claimed jsonb not null default '[]'::jsonb,   -- ["win","all",...]
  primary key (user_id, day)
);$vr_statement$;
  execute $vr_statement$alter table public.daily_progress enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.daily_progress from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create table if not exists public.daily_attend (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  last_day date,
  step     int not null default 0,   -- 이번 주기에서 받은 날 수 (0~7)
  total    int not null default 0
);$vr_statement$;
  execute $vr_statement$alter table public.daily_attend enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.daily_attend from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 미션 정의 (한 곳에서 조정). per = daily_track 1회 호출로 올릴 수 있는 최대
create or replace function public._daily_defs() returns jsonb language sql immutable as $$ select '[
  {"key":"arcade","name":"아케이드 1판 플레이","goal":1,"per":1,"reward":{"gold":1000}},
  {"key":"win","name":"전투 3회 승리","goal":3,"per":1,"reward":{"gold":2000}},
  {"key":"story","name":"스토리 스테이지 2회 클리어","goal":2,"per":1,"reward":{"gold":2000,"gem":10}},
  {"key":"tower","name":"시련의 탑 1회 도전","goal":1,"per":1,"reward":{"gold":1500,"gem":10}},
  {"key":"skill","name":"고유기술 10회 사용","goal":10,"per":20,"reward":{"gold":1500}}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._daily_all_reward() returns jsonb language sql immutable as $$ select '{"gem":30}'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- 출석 7일 주기 (빠진 날이 있어도 끊기지 않고 다음 칸으로. 7일째 받으면 1일째부터 다시)
create or replace function public._attend_defs() returns jsonb language sql immutable as $$ select '[
  {"gold":3000},{"gem":20},{"gold":5000},{"gem":30},{"tickets":1},{"gold":10000},{"gem":100,"tickets":2}
]'::jsonb $$;$vr_statement$;
  execute $vr_statement$create or replace function public._daily_grant(p_uid uuid, p_rw jsonb, p_reason text, p_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb := '{}'::jsonb; t int;
begin
  if coalesce((p_rw->>'gold')::int, 0) > 0 then res := res || jsonb_build_object('wallet', _wallet_add(p_uid, jsonb_build_object('gold', (p_rw->>'gold')::int), p_reason)); end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 then perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, p_ref, jsonb_build_object('ref', p_ref)); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _gem_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid returning tickets into t;
    res := res || jsonb_build_object('tickets', t);
  end if;
  return res;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._daily_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare dp daily_progress; a daily_attend; today date := _gem_day(); done int;
begin
  select * into dp from daily_progress where user_id = p_uid and day = today;
  select * into a from daily_attend where user_id = p_uid;
  select count(*) into done from jsonb_array_elements(_daily_defs()) m where coalesce((dp.prog->>(m->>'key'))::int, 0) >= (m->>'goal')::int;
  return jsonb_build_object('ok', true, 'day', today,
    'next_reset', ((today + 1)::timestamp at time zone 'Asia/Seoul'),
    'missions', (select jsonb_agg(m || jsonb_build_object('prog', least((m->>'goal')::int, coalesce((dp.prog->>(m->>'key'))::int, 0)),
                   'claimed', coalesce(dp.claimed, '[]'::jsonb) ? (m->>'key'))) from jsonb_array_elements(_daily_defs()) m),
    'all', jsonb_build_object('reward', _daily_all_reward(), 'done', done, 'goal', jsonb_array_length(_daily_defs()), 'claimed', coalesce(dp.claimed, '[]'::jsonb) ? 'all'),
    'attend', jsonb_build_object('rewards', _attend_defs(), 'step', case when coalesce(a.step, 0) >= 7 and a.last_day < today then 0 else coalesce(a.step, 0) end,
                   'today', a.last_day = today, 'total', coalesce(a.total, 0)));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._daily_grant(uuid, jsonb, text, text), public._daily_json(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.daily_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return _daily_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.daily_track(p_kind text, p_n int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; today date := _gem_day(); cur int; nv int;
begin
  if uid is null then raise exception 'login required'; end if;
  select x into m from jsonb_array_elements(_daily_defs()) x where x->>'key' = p_kind;
  if m is null then raise exception 'invalid kind'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  insert into daily_progress (user_id, day) values (uid, today) on conflict do nothing;
  select coalesce((prog->>p_kind)::int, 0) into cur from daily_progress where user_id = uid and day = today;
  nv := least((m->>'goal')::int, cur + greatest(0, least(coalesce(p_n, 1), (m->>'per')::int)));
  if nv <> cur then update daily_progress set prog = prog || jsonb_build_object(p_kind, nv) where user_id = uid and day = today; end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'prog', nv, 'goal', (m->>'goal')::int);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.daily_claim(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m jsonb; today date := _gem_day(); dp daily_progress; rw jsonb; res jsonb; done int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into daily_progress (user_id, day) values (uid, today) on conflict do nothing;
  select * into dp from daily_progress where user_id = uid and day = today for update;
  if dp.claimed ? p_key then raise exception 'already claimed'; end if;
  if p_key = 'all' then
    select count(*) into done from jsonb_array_elements(_daily_defs()) x where coalesce((dp.prog->>(x->>'key'))::int, 0) >= (x->>'goal')::int;
    if done < jsonb_array_length(_daily_defs()) then raise exception 'not done'; end if;
    rw := _daily_all_reward();
  else
    select x into m from jsonb_array_elements(_daily_defs()) x where x->>'key' = p_key;
    if m is null then raise exception 'invalid key'; end if;
    if coalesce((dp.prog->>p_key)::int, 0) < (m->>'goal')::int then raise exception 'not done'; end if;
    rw := m->'reward';
  end if;
  update daily_progress set claimed = claimed || to_jsonb(p_key) where user_id = uid and day = today;
  res := _daily_grant(uid, rw, 'daily', 'daily:' || today || ':' || p_key);
  return _daily_json(uid) || res || jsonb_build_object('got', rw);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.attend_claim() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := _gem_day(); a daily_attend; st int; rw jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('daily:' || uid::text));
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  insert into daily_attend (user_id) values (uid) on conflict do nothing;
  select * into a from daily_attend where user_id = uid for update;
  if a.last_day = today then raise exception 'already claimed'; end if;
  st := case when a.step >= 7 then 1 else a.step + 1 end;
  rw := _attend_defs()->(st - 1);
  update daily_attend set last_day = today, step = st, total = total + 1 where user_id = uid;
  res := _daily_grant(uid, rw, 'attend', 'attend:' || today);
  return _daily_json(uid) || res || jsonb_build_object('got', rw, 'got_day', st);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.daily_status(), public.daily_track(text, int), public.daily_claim(text), public.attend_claim() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.daily_status(), public.daily_track(text, int), public.daily_claim(text), public.attend_claim() to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: dispatch.sql =====
-- 파견 (배척지 001~009 · 안전지대 B~SS). 선행: phaseE_1/2(지갑·플레이어 레벨) · gem.sql · gacha.sql(story_gacha.tickets) · trade_drink.sql(_item_add). 여러 번 실행해도 안전.
-- 규칙 요약
--  * 매일 0시(KST) 의뢰 6개(배척지 4 · 안전지대 2) 무작위. 새로고침: 하루 3번 무료 → 심연석 20/30/40/50(이후 50)
--  * 필수 = 등급만(보낸 카드 중 1장 이상이 그 등급 이상). 속성·클래스 맞는 카드 1장당 +15%(속성·클래스 따로, 최대 +60%), 필수보다 높은 등급 카드 있으면 +10%
--  * 보너스 최대(+60%)면 10% 확률 대성공(보상 2배). 보상·확률·종료 시각은 출발할 때 서버가 정해 둠
--  * 시간 1/4/8/12시간 = 1시간 보상 × 1 / 3.5 / 6 / 8.5
--  * 동시 진행 슬롯: 플레이어 Lv1~29 = 3, 30~59 = 4, 60~ = 5. 하루 출발 최대 12번
--  * 한 카드(uid)는 진행 중인 파견 하나에만. 덱·스토리·PvP 사용은 막지 않음. MR·LR 카드는 아직 파견 불가

-- 1) 카드 정보 (등급 0=N 1=R 2=HR 3=SR 4=UR 5=MR 6=LR · 속성 · 클래스). data/cards.csv · npc_cards.csv 에서 생성
create table if not exists public.dispatch_card_meta (id text primary key, grade int not null, el text not null, cls text not null);$vr_statement$;
  execute $vr_statement$alter table public.dispatch_card_meta enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists dispatch_card_meta_read on public.dispatch_card_meta;$vr_statement$;
  execute $vr_statement$create policy dispatch_card_meta_read on public.dispatch_card_meta for select using (true);$vr_statement$;
  execute $vr_statement$insert into public.dispatch_card_meta (id, grade, el, cls) values
('10001',0,'WIND','CHARGE'),
('10002',0,'WIND','CHARGE'),
('10003',0,'FIRE','CHARGE'),
('10004',0,'WIND','DEFENSE'),
('10005',0,'WIND','DEFENSE'),
('10006',0,'FIRE','SUPPORT'),
('10007',1,'WIND','DEFENSE'),
('10008',0,'WIND','CHARGE'),
('10009',0,'WIND','CHARGE'),
('10010',0,'FIRE','CHARGE'),
('10011',0,'WIND','CHARGE'),
('10012',0,'WIND','CHARGE'),
('10013',3,'FIRE','CHARGE'),
('10014',0,'FIRE','CHARGE'),
('10015',2,'ICE','CRUSH'),
('10016',1,'WIND','CHARGE'),
('10017',2,'FIRE','CHARGE'),
('10018',1,'WIND','CHARGE'),
('10019',1,'FIRE','CRUSH'),
('10020',1,'FIRE','CHARGE'),
('10021',1,'WIND','CHARGE'),
('10022',0,'FIRE','DEFENSE'),
('10023',0,'WIND','DEFENSE'),
('10024',3,'ICE','DEFENSE'),
('10025',3,'FIRE','DISTURB'),
('10026',0,'FIRE','CHARGE'),
('10027',0,'ICE','CHARGE'),
('10028',0,'WIND','CHARGE'),
('10029',1,'FIRE','CHARGE'),
('10030',0,'WIND','CHARGE'),
('10031',0,'ICE','DEFENSE'),
('10032',0,'WIND','CHARGE'),
('10033',0,'FIRE','CHARGE'),
('10034',0,'WIND','CHARGE'),
('10035',2,'ICE','CHARGE'),
('10036',2,'WIND','CRUSH'),
('10037',0,'FIRE','CHARGE'),
('10038',0,'WIND','CHARGE'),
('10039',0,'WIND','FASCINATION'),
('10040',0,'FIRE','DEFENSE'),
('10041',2,'WIND','CRUSH'),
('10042',1,'WIND','CRUSH'),
('10043',2,'WIND','CRUSH'),
('10044',1,'WIND','CHARGE'),
('10045',3,'ICE','CHARGE'),
('10046',1,'WIND','CRUSH'),
('10047',2,'WIND','CRUSH'),
('10048',0,'WIND','CHARGE'),
('10049',0,'ICE','DEFENSE'),
('10050',0,'FIRE','DEFENSE'),
('10051',4,'FIRE','CHARGE'),
('10052',3,'DARK','DISTURB'),
('10053',4,'DARK','OVERWHELMING'),
('10054',4,'DARK','OVERWHELMING'),
('10055',0,'WIND','CHARGE'),
('10056',0,'WIND','DEFENSE'),
('10057',0,'WIND','CHARGE'),
('10058',4,'FIRE','CRUSH'),
('10059',1,'DARK','DISTURB'),
('10060',5,'ABYSS','FURIOUS'),
('10061',3,'ICE','CRUSH'),
('10062',5,'ABYSS','PHENOMENAL'),
('10063',0,'ICE','DEFENSE'),
('10064',0,'WIND','DEFENSE'),
('10065',2,'ICE','CHARGE'),
('10066',0,'WIND','CHARGE'),
('10067',3,'FIRE','CRUSH'),
('10068',3,'DARK','CRUSH'),
('10069',0,'ICE','CHARGE'),
('10070',3,'ICE','CHARGE'),
('10071',0,'WIND','CHARGE'),
('10072',2,'DARK','DISTURB'),
('10073',2,'LIGHT','SUPPORT'),
('10074',0,'WIND','DEFENSE'),
('10075',0,'WIND','CHARGE'),
('10076',0,'ICE','CHARGE'),
('10077',2,'ICE','CRUSH'),
('10078',2,'FIRE','FASCINATION'),
('10079',0,'FIRE','DEFENSE'),
('10080',0,'WIND','DEFENSE'),
('10081',2,'WIND','DISTURB'),
('10082',2,'WIND','DEFENSE'),
('10083',0,'WIND','CHARGE'),
('10084',0,'FIRE','CHARGE'),
('10085',0,'FIRE','CHARGE'),
('10086',0,'WIND','CHARGE'),
('10087',2,'ICE','CRUSH'),
('10088',0,'FIRE','CHARGE'),
('10089',1,'WIND','CHARGE'),
('10090',1,'ICE','FASCINATION'),
('10091',1,'DARK','DISTURB'),
('10092',1,'WIND','CHARGE'),
('10093',0,'WIND','CHARGE'),
('10094',0,'WIND','CHARGE'),
('10095',1,'FIRE','CRUSH'),
('10096',2,'ICE','CRUSH'),
('10097',1,'WIND','DEFENSE'),
('10098',1,'FIRE','CHARGE'),
('10099',0,'WIND','CHARGE'),
('10100',0,'FIRE','CHARGE'),
('10101',0,'WIND','CHARGE'),
('10102',2,'WIND','DISTURB'),
('10103',1,'DARK','SUPPORT'),
('10104',1,'WIND','CRUSH'),
('10105',1,'FIRE','CHARGE'),
('10106',0,'ICE','CHARGE'),
('10107',0,'WIND','CHARGE'),
('10108',3,'LIGHT','SUPPORT'),
('10109',3,'FIRE','CHARGE'),
('10110',2,'FIRE','CRUSH'),
('10111',1,'FIRE','SUPPORT'),
('10112',3,'FIRE','CHARGE'),
('10113',0,'ICE','DEFENSE'),
('10114',0,'WIND','CHARGE'),
('10115',1,'WIND','SUPPORT'),
('10116',3,'FIRE','CRUSH'),
('10117',3,'FIRE','CHARGE'),
('10118',3,'FIRE','CHARGE'),
('10119',0,'ICE','DEFENSE'),
('10120',0,'FIRE','CHARGE'),
('10121',1,'WIND','DISTURB'),
('10122',0,'ICE','CHARGE'),
('10123',2,'FIRE','DEFENSE'),
('10124',1,'WIND','CHARGE'),
('10125',0,'FIRE','CHARGE'),
('10126',2,'WIND','CRUSH'),
('10127',3,'LIGHT','CHARGE'),
('10128',0,'FIRE','CHARGE'),
('10129',1,'WIND','SUPPORT'),
('10130',0,'WIND','DEFENSE'),
('10131',2,'DARK','DISTURB'),
('10132',1,'WIND','FASCINATION'),
('10133',1,'WIND','CHARGE'),
('10134',1,'WIND','CHARGE'),
('10135',1,'DARK','SUPPORT'),
('10136',2,'ICE','CHARGE'),
('10137',2,'ICE','CHARGE'),
('10138',2,'WIND','DISTURB'),
('10139',0,'WIND','CHARGE'),
('10140',0,'WIND','CHARGE'),
('10141',1,'WIND','CRUSH'),
('10142',0,'ICE','CHARGE'),
('10143',0,'FIRE','CHARGE'),
('10144',0,'WIND','CHARGE'),
('10145',0,'ICE','CHARGE'),
('10146',0,'FIRE','DEFENSE'),
('10147',0,'WIND','DEFENSE'),
('10148',1,'ICE','DEFENSE'),
('10149',1,'FIRE','DEFENSE'),
('10150',1,'WIND','CRUSH'),
('10151',2,'ICE','CRUSH'),
('10152',2,'FIRE','CRUSH'),
('10153',0,'WIND','CHARGE'),
('10154',0,'ICE','CHARGE'),
('10155',0,'FIRE','DEFENSE'),
('10156',0,'WIND','DEFENSE'),
('10157',0,'ICE','DEFENSE'),
('10158',0,'FIRE','DEFENSE'),
('10159',1,'WIND','CRUSH'),
('10160',1,'ICE','CRUSH'),
('10161',1,'FIRE','CRUSH'),
('10162',1,'WIND','CHARGE'),
('10163',2,'ICE','CHARGE'),
('10164',2,'FIRE','DEFENSE'),
('10165',2,'WIND','DEFENSE'),
('10166',2,'DARK','SUPPORT'),
('10167',2,'DARK','SUPPORT'),
('10168',2,'DARK','DISTURB'),
('10169',0,'WIND','DEFENSE'),
('10170',0,'FIRE','CHARGE'),
('10171',0,'FIRE','CHARGE'),
('10172',0,'FIRE','CHARGE'),
('10173',0,'WIND','CHARGE'),
('10174',0,'WIND','CHARGE'),
('10175',1,'WIND','CHARGE'),
('10176',4,'LIGHT','SUPPORT'),
('10177',0,'WIND','CHARGE'),
('10178',0,'ICE','CHARGE'),
('10179',0,'WIND','CHARGE'),
('10180',1,'ICE','DEFENSE'),
('10181',3,'WIND','CRUSH'),
('10182',1,'DARK','DISTURB'),
('10183',3,'ICE','CRUSH'),
('10184',0,'WIND','DEFENSE'),
('10185',0,'FIRE','CHARGE'),
('10186',3,'ICE','DISTURB'),
('10187',1,'FIRE','DEFENSE'),
('10188',2,'WIND','CHARGE'),
('10189',3,'FIRE','DEFENSE'),
('10190',0,'FIRE','FASCINATION'),
('10191',0,'ICE','DEFENSE'),
('10192',0,'FIRE','CHARGE'),
('10193',0,'ICE','DEFENSE'),
('10194',1,'WIND','CRUSH'),
('10195',1,'ICE','CRUSH'),
('10196',0,'WIND','CHARGE'),
('10197',0,'WIND','CHARGE'),
('10198',0,'WIND','CHARGE'),
('10199',1,'WIND','CHARGE'),
('10200',3,'DARK','CRUSH'),
('10201',0,'WIND','DEFENSE'),
('10202',1,'FIRE','CHARGE'),
('10203',2,'LIGHT','SUPPORT'),
('10204',1,'WIND','CHARGE'),
('10205',2,'ICE','CRUSH'),
('10206',0,'ICE','DEFENSE'),
('10207',2,'ICE','DISTURB'),
('10208',2,'DARK','CRUSH'),
('10209',0,'ICE','CHARGE'),
('10210',2,'WIND','CHARGE'),
('10211',0,'WIND','DEFENSE'),
('10212',0,'WIND','DEFENSE'),
('10213',3,'FIRE','DISTURB'),
('10214',2,'FIRE','CHARGE'),
('10215',0,'FIRE','DEFENSE'),
('10216',3,'DARK','FASCINATION'),
('10217',3,'DARK','DISTURB'),
('10218',0,'FIRE','CHARGE'),
('10219',0,'DARK','DEFENSE'),
('10220',0,'FIRE','CHARGE'),
('10221',0,'FIRE','CHARGE'),
('10222',1,'WIND','CHARGE'),
('10223',0,'WIND','DEFENSE'),
('10224',1,'WIND','CRUSH'),
('10225',1,'FIRE','CHARGE'),
('10226',1,'WIND','SUPPORT'),
('10227',1,'WIND','CHARGE'),
('10228',1,'FIRE','DEFENSE'),
('10229',2,'FIRE','CHARGE'),
('10230',1,'WIND','CRUSH'),
('10231',2,'LIGHT','DISTURB'),
('10232',0,'WIND','DEFENSE'),
('10233',0,'FIRE','CHARGE'),
('10234',1,'FIRE','CHARGE'),
('10235',0,'ICE','CHARGE'),
('10236',3,'FIRE','CRUSH'),
('10237',1,'ICE','CHARGE'),
('10238',0,'WIND','DEFENSE'),
('10239',2,'WIND','CHARGE'),
('10240',2,'WIND','CHARGE'),
('10241',1,'WIND','SUPPORT'),
('10242',1,'WIND','DISTURB'),
('10243',0,'ICE','CHARGE'),
('10244',0,'FIRE','CHARGE'),
('10245',0,'WIND','DEFENSE'),
('10246',1,'WIND','CHARGE'),
('10247',0,'ICE','DEFENSE'),
('10248',0,'WIND','DEFENSE'),
('10249',0,'FIRE','CHARGE'),
('10250',0,'WIND','CHARGE'),
('10251',0,'FIRE','CHARGE'),
('10252',0,'ICE','CHARGE'),
('10253',0,'FIRE','CHARGE'),
('10254',1,'WIND','CHARGE'),
('10255',3,'ICE','CRUSH'),
('10256',1,'DARK','SUPPORT'),
('10257',2,'ICE','SUPPORT'),
('10258',1,'WIND','SUPPORT'),
('10259',1,'ICE','CHARGE'),
('10260',0,'ICE','CHARGE'),
('10261',1,'WIND','SUPPORT'),
('10262',0,'WIND','DEFENSE'),
('10263',0,'FIRE','CHARGE'),
('10264',0,'ICE','CHARGE'),
('10265',1,'WIND','CHARGE'),
('10266',1,'WIND','SUPPORT'),
('10267',2,'ICE','DEFENSE'),
('10268',2,'WIND','DEFENSE'),
('10269',3,'WIND','CRUSH'),
('10270',1,'FIRE','CRUSH'),
('10271',0,'WIND','CHARGE'),
('10272',0,'WIND','CHARGE'),
('10273',0,'WIND','CHARGE'),
('10274',0,'WIND','CHARGE'),
('10275',0,'ICE','CHARGE'),
('10276',1,'WIND','CHARGE'),
('10277',0,'WIND','CHARGE'),
('10278',1,'WIND','CHARGE'),
('10279',0,'WIND','CHARGE'),
('10280',0,'ICE','CHARGE'),
('10281',3,'WIND','CRUSH'),
('10282',0,'ICE','CHARGE'),
('10283',0,'FIRE','CHARGE'),
('10284',1,'FIRE','CHARGE'),
('10285',1,'WIND','DEFENSE'),
('10286',0,'WIND','DEFENSE'),
('10287',1,'FIRE','CRUSH'),
('10288',2,'FIRE','CHARGE'),
('10289',0,'WIND','CHARGE'),
('10290',1,'LIGHT','SUPPORT'),
('10291',4,'DARK','CHARGE'),
('10292',2,'WIND','CHARGE'),
('10293',1,'FIRE','CHARGE'),
('10294',0,'WIND','CHARGE'),
('10295',0,'WIND','CHARGE'),
('10296',1,'WIND','CHARGE'),
('10297',1,'WIND','SUPPORT'),
('10298',2,'FIRE','CRUSH'),
('10299',2,'ICE','DEFENSE'),
('10300',1,'DARK','SUPPORT'),
('10301',3,'DARK','CRUSH'),
('10302',1,'WIND','DISTURB'),
('10303',0,'WIND','DEFENSE'),
('10304',4,'DARK','CRUSH'),
('10305',0,'FIRE','CHARGE'),
('10306',1,'WIND','SUPPORT'),
('10307',1,'ICE','CHARGE'),
('10308',2,'ICE','SUPPORT'),
('10309',2,'FIRE','CRUSH'),
('10310',0,'WIND','SUPPORT'),
('10311',5,'ABYSS','EXTERMINATE'),
('10312',4,'DARK','DISTURB'),
('10313',0,'WIND','DEFENSE'),
('10314',0,'WIND','CHARGE'),
('10315',0,'FIRE','DEFENSE'),
('10316',0,'WIND','DEFENSE'),
('10317',3,'ICE','FASCINATION'),
('10318',0,'WIND','CHARGE'),
('10319',1,'FIRE','CRUSH'),
('10320',0,'FIRE','CHARGE'),
('10321',3,'DARK','CRUSH'),
('10322',4,'ICE','CRUSH'),
('10323',4,'FIRE','CRUSH'),
('10324',4,'DARK','DISTURB'),
('10325',4,'DARK','FASCINATION'),
('10326',5,'DARK','FASCINATION'),
('10327',0,'ICE','DEFENSE'),
('10328',0,'FIRE','CHARGE'),
('10329',3,'WIND','CHARGE'),
('10330',0,'ICE','DEFENSE'),
('10331',4,'LIGHT','SUPPORT'),
('10332',0,'ICE','CHARGE'),
('10333',3,'FIRE','CHARGE'),
('10334',6,'VOID','UNLIMITED'),
('10335',5,'ABYSS','BALANCE'),
('10336',2,'WIND','CHARGE'),
('10337',0,'ICE','CHARGE'),
('10338',2,'WIND','CRUSH'),
('10339',0,'ICE','CHARGE'),
('10340',0,'FIRE','CHARGE'),
('10341',3,'ICE','CRUSH'),
('10342',0,'WIND','CHARGE'),
('10343',2,'FIRE','DISTURB'),
('10344',0,'ICE','CHARGE'),
('10345',1,'FIRE','CHARGE'),
('10346',0,'WIND','CHARGE'),
('10347',1,'ICE','CRUSH'),
('10348',0,'ICE','CHARGE'),
('10349',1,'FIRE','CHARGE'),
('10350',2,'FIRE','DEFENSE'),
('10351',0,'WIND','CHARGE'),
('10352',0,'WIND','DEFENSE'),
('10353',0,'WIND','CHARGE'),
('10354',3,'ICE','CRUSH'),
('10355',0,'ICE','CHARGE'),
('10356',0,'ICE','CHARGE'),
('10357',1,'FIRE','CRUSH'),
('10358',4,'WIND','DISTURB'),
('10359',4,'ICE','CRUSH'),
('10360',0,'WIND','CHARGE'),
('10361',2,'WIND','FASCINATION'),
('10362',2,'DARK','FASCINATION'),
('10363',0,'WIND','DEFENSE'),
('10364',0,'ICE','CHARGE'),
('10365',0,'WIND','DEFENSE'),
('10366',0,'WIND','CHARGE'),
('10367',1,'ICE','SUPPORT'),
('10368',1,'WIND','CHARGE'),
('10369',3,'ICE','DISTURB'),
('10370',1,'ICE','CHARGE'),
('10371',2,'FIRE','CRUSH'),
('10372',1,'ICE','CHARGE'),
('10373',3,'WIND','CRUSH'),
('10374',2,'WIND','CHARGE'),
('10375',0,'FIRE','DEFENSE'),
('10376',0,'WIND','CHARGE'),
('10377',0,'WIND','DEFENSE'),
('10378',1,'ICE','CHARGE'),
('10379',0,'WIND','CHARGE'),
('10380',1,'ICE','DEFENSE'),
('10381',0,'FIRE','DEFENSE'),
('10382',0,'WIND','CHARGE'),
('10383',3,'DARK','DISTURB'),
('10384',1,'WIND','SUPPORT'),
('10385',1,'ICE','DEFENSE'),
('10386',1,'WIND','CHARGE'),
('10387',0,'WIND','DEFENSE'),
('10388',0,'WIND','CHARGE'),
('10389',0,'WIND','DEFENSE'),
('10390',0,'WIND','CHARGE'),
('10391',1,'WIND','FASCINATION'),
('10392',3,'WIND','SUPPORT'),
('10393',2,'ICE','SUPPORT'),
('10394',2,'LIGHT','SUPPORT'),
('10395',0,'WIND','CHARGE'),
('10396',0,'ICE','CHARGE'),
('10397',1,'ICE','CRUSH'),
('10398',1,'ICE','CRUSH'),
('10399',3,'WIND','CRUSH'),
('10400',2,'ICE','DISTURB'),
('10401',0,'FIRE','CHARGE'),
('10402',0,'WIND','DEFENSE'),
('10403',0,'ICE','DEFENSE'),
('10404',0,'WIND','DEFENSE'),
('10405',1,'LIGHT','SUPPORT'),
('10406',2,'ICE','CHARGE'),
('10407',1,'ICE','DEFENSE'),
('10408',1,'WIND','CHARGE'),
('10409',0,'FIRE','CHARGE'),
('10410',0,'WIND','CHARGE'),
('10411',0,'ICE','DEFENSE'),
('10412',0,'ICE','CHARGE'),
('10413',2,'WIND','SUPPORT'),
('10414',2,'ICE','SUPPORT'),
('10415',3,'DARK','FASCINATION'),
('10416',0,'WIND','CHARGE'),
('10417',1,'ICE','DEFENSE'),
('10418',3,'ICE','DISTURB'),
('10419',2,'WIND','CRUSH'),
('10420',1,'WIND','CHARGE'),
('10421',0,'WIND','CHARGE'),
('10422',0,'WIND','CHARGE'),
('10423',0,'FIRE','CHARGE'),
('10424',1,'WIND','CHARGE'),
('10425',2,'WIND','CRUSH'),
('10426',1,'FIRE','FASCINATION'),
('10427',0,'FIRE','CHARGE'),
('10428',0,'WIND','DEFENSE'),
('10429',1,'WIND','CRUSH'),
('10430',0,'WIND','CHARGE'),
('10431',0,'WIND','DEFENSE'),
('10432',1,'WIND','SUPPORT'),
('10433',2,'WIND','CHARGE'),
('10434',0,'FIRE','DEFENSE'),
('10435',4,'FIRE','DISTURB'),
('10436',0,'FIRE','CHARGE'),
('10437',1,'DARK','FASCINATION'),
('10438',0,'ICE','CHARGE'),
('10439',3,'WIND','DEFENSE'),
('10440',4,'WIND','DEFENSE'),
('10441',0,'FIRE','CHARGE'),
('10442',2,'ICE','CRUSH'),
('10443',0,'ICE','DEFENSE'),
('10444',0,'FIRE','CHARGE'),
('10445',0,'WIND','CHARGE'),
('10446',0,'FIRE','CHARGE'),
('10447',1,'WIND','CHARGE'),
('10448',0,'FIRE','DEFENSE'),
('10449',0,'WIND','DEFENSE'),
('10450',0,'ICE','CHARGE'),
('10451',0,'ICE','CHARGE'),
('10452',2,'ICE','SUPPORT'),
('10453',0,'WIND','CHARGE'),
('10454',1,'ICE','CRUSH'),
('10455',1,'FIRE','CHARGE'),
('10456',0,'ICE','CHARGE'),
('10457',2,'WIND','SUPPORT'),
('10458',1,'FIRE','CHARGE'),
('10459',0,'WIND','CHARGE'),
('10460',0,'WIND','CHARGE'),
('10461',1,'FIRE','CHARGE'),
('10462',1,'WIND','CRUSH'),
('10463',2,'WIND','CRUSH'),
('10464',1,'FIRE','CHARGE'),
('10465',3,'WIND','CHARGE'),
('10466',1,'WIND','SUPPORT'),
('10467',0,'LIGHT','SUPPORT'),
('10468',0,'WIND','SUPPORT'),
('10469',0,'FIRE','CHARGE'),
('10470',1,'FIRE','CHARGE'),
('10471',0,'FIRE','CHARGE'),
('10472',0,'WIND','CHARGE'),
('10473',2,'WIND','CHARGE'),
('10474',0,'WIND','CHARGE'),
('10475',3,'DARK','CRUSH'),
('10476',0,'WIND','CHARGE'),
('10477',0,'WIND','DEFENSE'),
('10478',1,'WIND','DEFENSE'),
('10479',1,'ICE','CHARGE'),
('10480',2,'ICE','DEFENSE'),
('10481',2,'ICE','DISTURB'),
('10482',2,'FIRE','CHARGE'),
('10483',2,'FIRE','CHARGE'),
('10484',2,'FIRE','CRUSH'),
('10485',1,'FIRE','DEFENSE'),
('10486',1,'FIRE','SUPPORT'),
('10487',0,'WIND','CHARGE'),
('10488',3,'ICE','CHARGE'),
('10489',2,'FIRE','DEFENSE'),
('10490',3,'WIND','SUPPORT'),
('10491',3,'ICE','DISTURB'),
('10492',0,'LIGHT','CHARGE'),
('10493',2,'LIGHT','SUPPORT'),
('10494',0,'WIND','CHARGE'),
('10495',1,'ICE','CHARGE'),
('10496',2,'FIRE','CHARGE'),
('10497',0,'WIND','CHARGE'),
('10498',1,'ICE','CHARGE'),
('10499',2,'FIRE','CHARGE'),
('10500',1,'DARK','DISTURB'),
('10501',2,'DARK','DISTURB'),
('10502',3,'DARK','CRUSH'),
('10503',4,'DARK','DISTURB'),
('10504',4,'LIGHT','SUPPORT'),
('10505',2,'ICE','CRUSH'),
('10506',2,'ICE','CHARGE'),
('10507',2,'ICE','CRUSH'),
('10508',3,'FIRE','DISTURB'),
('10509',2,'WIND','CHARGE'),
('10510',2,'FIRE','CHARGE')
on conflict (id) do update set grade = excluded.grade, el = excluded.el, cls = excluded.cls;$vr_statement$;
  execute $vr_statement$-- 1-b) 새 카드 자동 반영: 새 카드 SQL은 늘 pvp_card_meta · story_card_pool 에 등급을 넣으므로,
--      거기 들어오는 순간 파견 표에도 등급이 들어감 (dispatch.sql 다시 실행 필요 없음).
--      속성·클래스는 그 표들에 없어서 '-' 로 들어감 → 파견은 가능, 속성·클래스 보너스만 없음 (다음 dispatch.sql 실행 때 채워짐)
create or replace function public._dsp_grade(g text) returns int language sql immutable as $$
  select array_position(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'], g) - 1 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_meta_sync() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if _dsp_grade(new.grade) is not null then
    insert into dispatch_card_meta (id, grade, el, cls) values (new.id, _dsp_grade(new.grade), '-', '-')
      on conflict (id) do update set grade = excluded.grade;
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists dsp_meta_sync on public.pvp_card_meta;$vr_statement$;
  execute $vr_statement$create trigger dsp_meta_sync after insert or update of grade on public.pvp_card_meta for each row execute function public._dsp_meta_sync();$vr_statement$;
  execute $vr_statement$drop trigger if exists dsp_meta_sync on public.story_card_pool;$vr_statement$;
  execute $vr_statement$create trigger dsp_meta_sync after insert or update of grade on public.story_card_pool for each row execute function public._dsp_meta_sync();$vr_statement$;
  execute $vr_statement$-- 지금 있는 카드 중 위 목록에 없는 것도 채움
insert into public.dispatch_card_meta (id, grade, el, cls)
select id, public._dsp_grade(grade), '-', '-' from public.pvp_card_meta where public._dsp_grade(grade) is not null
union select id, public._dsp_grade(grade), '-', '-' from public.story_card_pool where public._dsp_grade(grade) is not null
on conflict (id) do nothing;$vr_statement$;
  execute $vr_statement$-- 2) 파견지. rw = 1시간 기본 보상 (소수점은 그 확률로 1개 더: 0.3 → 30% 확률로 1)
create table if not exists public.dispatch_zones (
  id text primary key, grp text not null check (grp in ('exile', 'safe')), name text not null, ord int not null,
  min_grade int not null check (min_grade between 0 and 4), size int not null check (size between 1 and 4), rw jsonb not null);$vr_statement$;
  execute $vr_statement$alter table public.dispatch_zones enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists dispatch_zones_read on public.dispatch_zones;$vr_statement$;
  execute $vr_statement$create policy dispatch_zones_read on public.dispatch_zones for select using (true);$vr_statement$;
  execute $vr_statement$insert into public.dispatch_zones (id, grp, name, ord, min_grade, size, rw) values
  ('x001', 'exile', '배척지 001', 1, 0, 1, '{"shard":5,"blood":3}'),
  ('x002', 'exile', '배척지 002', 2, 0, 2, '{"shard":7,"blood":5}'),
  ('x003', 'exile', '배척지 003', 3, 1, 2, '{"shard":10,"blood":8,"soul":0.3}'),
  ('x004', 'exile', '배척지 004', 4, 1, 2, '{"shard":12,"blood":9,"soul":0.4}'),
  ('x005', 'exile', '배척지 005', 5, 2, 3, '{"shard":14,"blood":10,"soul":0.8}'),
  ('x006', 'exile', '배척지 006', 6, 2, 3, '{"shard":16,"blood":12,"soul":1}'),
  ('x007', 'exile', '배척지 007', 7, 3, 3, '{"shard":18,"blood":14,"soul":1.5,"gem":0.2}'),
  ('x008', 'exile', '배척지 008', 8, 3, 4, '{"shard":20,"blood":16,"soul":2.2,"gem":0.6}'),
  ('x009', 'exile', '배척지 009', 9, 4, 4, '{"shard":24,"blood":20,"soul":3.3,"gem":1.6}'),
  ('sB',   'safe',  '안전지대 B급', 11, 0, 1, '{"gold":500}'),
  ('sA',   'safe',  '안전지대 A급', 12, 1, 2, '{"gold":1000,"drink":0.15}'),
  ('sS',   'safe',  '안전지대 S급', 13, 2, 3, '{"gold":2000,"tickets":0.05}'),
  ('sSS',  'safe',  '안전지대 SS급', 14, 3, 4, '{"gold":3300,"tickets":0.17,"gem":0.8}')
on conflict (id) do update set grp = excluded.grp, name = excluded.name, ord = excluded.ord, min_grade = excluded.min_grade, size = excluded.size, rw = excluded.rw;$vr_statement$;
  execute $vr_statement$delete from public.dispatch_zones where id not in ('x001','x002','x003','x004','x005','x006','x007','x008','x009','sB','sA','sS','sSS');$vr_statement$;
  execute $vr_statement$-- 3) 의뢰 게시판 · 진행 · 하루 기록 (직접 읽기만, 쓰기는 함수로만)
create table if not exists public.dispatch_offers (
  user_id uuid not null references auth.users(id) on delete cascade, slot int not null check (slot between 1 and 6),
  day date not null, zone text not null references public.dispatch_zones(id), el text not null, cls text not null,
  taken boolean not null default false, primary key (user_id, slot));$vr_statement$;
  execute $vr_statement$create table if not exists public.dispatch_runs (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  zone text not null references public.dispatch_zones(id), el text not null, cls text not null, hours int not null check (hours in (1, 4, 8, 12)),
  uids text[] not null, bonus int not null default 0, great boolean not null default false, reward jsonb not null,
  started_at timestamptz not null default now(), ends_at timestamptz not null,
  claimed_at timestamptz, recalled boolean not null default false);$vr_statement$;
  execute $vr_statement$create index if not exists dispatch_runs_open on public.dispatch_runs (user_id) where claimed_at is null;$vr_statement$;
  execute $vr_statement$create table if not exists public.dispatch_daily (
  user_id uuid not null references auth.users(id) on delete cascade, day date not null,
  refreshes int not null default 0, starts int not null default 0, primary key (user_id, day));$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['dispatch_offers', 'dispatch_runs', 'dispatch_daily'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_own', t);
    execute format('create policy %I on public.%I for select using (user_id = auth.uid())', t || '_own', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop; end $$;$vr_statement$;
  execute $vr_statement$-- 4) 도우미
create or replace function public._dsp_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_mult(h int) returns numeric language sql immutable as $$ select case h when 1 then 1 when 4 then 3.5 when 8 then 6 when 12 then 8.5 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_slots(lv int) returns int language sql immutable as $$ select case when lv >= 60 then 5 when lv >= 30 then 4 else 3 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_cap() returns int language sql immutable as $$ select 12 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_free() returns int language sql immutable as $$ select 3 $$;$vr_statement$;
  execute $vr_statement$-- n = 오늘 이미 한 새로고침 수 → 이번 새로고침 비용
create or replace function public._dsp_cost(n int) returns int language sql immutable as $$ select case when n < 3 then 0 else least(20 + 10 * (n - 3), 50) end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_level(p_uid uuid) returns int language plpgsql security definer set search_path = public as $$
declare lv int; begin begin select (_player_sync(p_uid)).level into lv; exception when others then lv := 1; end; return coalesce(lv, 1); end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_owned(p_uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select case when jsonb_typeof(data->'owned') = 'array' then data->'owned' end from story_progress where user_id = p_uid), '[]'::jsonb) $$;$vr_statement$;
  execute $vr_statement$-- 게시판 채우기 (p_all: 전부 새로 / 아니면 아직 안 보낸 의뢰만). 가진 카드 중 최고 등급(UR까지)으로 갈 수 있는 곳만
create or replace function public._dsp_fill(p_uid uuid, p_all boolean) returns void language plpgsql security definer set search_path = public as $$
declare best int; s int; z text; els text[] := array['WIND','FIRE','ICE','DARK','LIGHT']; cl text[] := array['CHARGE','CRUSH','DEFENSE','SUPPORT','DISTURB','FASCINATION'];
begin
  select coalesce(max(m.grade), 0) into best from jsonb_array_elements(_dsp_owned(p_uid)) o join dispatch_card_meta m on m.id = o->>'id' where m.grade <= 4;
  if p_all then delete from dispatch_offers where user_id = p_uid; end if;
  for s in 1..6 loop
    if not p_all and exists (select 1 from dispatch_offers where user_id = p_uid and slot = s and taken) then continue; end if;
    -- 높은 단계일수록 조금 더 자주 (ord 가중치)
    select id into z from dispatch_zones where grp = case when s <= 4 then 'exile' else 'safe' end and min_grade <= best
      order by -ln(greatest(random(), 1e-9)) / (1 + min_grade) limit 1;
    insert into dispatch_offers (user_id, slot, day, zone, el, cls, taken) values (p_uid, s, _dsp_day(), z, els[1 + floor(random() * 5)::int], cl[1 + floor(random() * 6)::int], false)
      on conflict (user_id, slot) do update set day = excluded.day, zone = excluded.zone, el = excluded.el, cls = excluded.cls, taken = false;
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._dsp_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare d dispatch_daily; lv int := _dsp_level(p_uid);
begin
  select * into d from dispatch_daily where user_id = p_uid and day = _dsp_day();
  return jsonb_build_object('ok', true, 'now', now(), 'day', _dsp_day(),
    'next_reset', ((_dsp_day() + 1)::timestamp at time zone 'Asia/Seoul'),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('slot', o.slot, 'zone', o.zone, 'el', o.el, 'cls', o.cls, 'taken', o.taken) order by o.slot) from dispatch_offers o where o.user_id = p_uid), '[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'zone', r.zone, 'el', r.el, 'cls', r.cls, 'hours', r.hours, 'uids', r.uids, 'bonus', r.bonus,
              'started_at', r.started_at, 'ends_at', r.ends_at, 'done', r.ends_at <= now(), 'reward', case when r.ends_at <= now() then r.reward end, 'great', case when r.ends_at <= now() then r.great end) order by r.ends_at)
              from dispatch_runs r where r.user_id = p_uid and r.claimed_at is null), '[]'::jsonb),
    'zones', (select jsonb_agg(jsonb_build_object('id', id, 'grp', grp, 'name', name, 'min_grade', min_grade, 'size', size, 'rw', rw) order by ord) from dispatch_zones),
    'mult', jsonb_build_object('1', 1, '4', 3.5, '8', 6, '12', 8.5),
    'slots', _dsp_slots(lv), 'level', lv, 'cap', _dsp_cap(), 'starts', coalesce(d.starts, 0),
    'refreshes', coalesce(d.refreshes, 0), 'free', _dsp_free(), 'refresh_cost', _dsp_cost(coalesce(d.refreshes, 0)));
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 공개 함수
create or replace function public.dispatch_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  if not exists (select 1 from dispatch_offers where user_id = uid and day = _dsp_day()) then perform _dsp_fill(uid, true); end if;
  return _dsp_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.dispatch_refresh() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; c int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  insert into dispatch_daily (user_id, day) values (uid, _dsp_day()) on conflict do nothing;
  select refreshes into n from dispatch_daily where user_id = uid and day = _dsp_day() for update;
  c := _dsp_cost(n);
  if c > 0 then
    begin perform _gem_spend(uid, c, 'dispatch_refresh', jsonb_build_object('n', n + 1));
    exception when others then if sqlerrm ~ 'not enough' then raise exception 'not enough gem'; else raise; end if; end;
  end if;
  update dispatch_daily set refreshes = refreshes + 1 where user_id = uid and day = _dsp_day();
  if not exists (select 1 from dispatch_offers where user_id = uid and day = _dsp_day()) then perform _dsp_fill(uid, true); else perform _dsp_fill(uid, false); end if;
  return _dsp_json(uid) || jsonb_build_object('spent', c);
end $$;$vr_statement$;
  execute $vr_statement$-- 보내기. 오류: bad hours · no offer · taken · slots full · daily cap · bad cards · not owned · busy · banned grade · need grade
create or replace function public.dispatch_start(p_slot int, p_uids text[], p_hours int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); o dispatch_offers; z dispatch_zones; owned jsonb; n int; mx int; bon int := 0; ne int; nc int; over boolean; k text; v numeric; rw jsonb := '{}'::jsonb; f numeric; great boolean := false; cnt int; d dispatch_daily;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_hours not in (1, 4, 8, 12) then raise exception 'bad hours'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  select * into o from dispatch_offers where user_id = uid and slot = p_slot for update;
  if o.user_id is null or o.day <> _dsp_day() then raise exception 'no offer'; end if;
  if o.taken then raise exception 'taken'; end if;
  select * into z from dispatch_zones where id = o.zone;
  if (select count(*) from dispatch_runs where user_id = uid and claimed_at is null) >= _dsp_slots(_dsp_level(uid)) then raise exception 'slots full'; end if;
  select * into d from dispatch_daily where user_id = uid and day = _dsp_day();
  if coalesce(d.starts, 0) >= _dsp_cap() then raise exception 'daily cap'; end if;
  n := coalesce(array_length(p_uids, 1), 0);
  if n < 1 or n > z.size or (select count(distinct u) from unnest(p_uids) u) <> n then raise exception 'bad cards'; end if;
  owned := _dsp_owned(uid);
  -- 가진 카드인지 + 카드 정보
  create temp table if not exists _dsp_pick (uid text, grade int, el text, cls text) on commit drop; delete from _dsp_pick;
  insert into _dsp_pick select u, m.grade, m.el, m.cls from unnest(p_uids) u
    join lateral (select x from jsonb_array_elements(owned) x where x->>'uid' = u limit 1) ox on true
    join dispatch_card_meta m on m.id = ox.x->>'id';
  if (select count(*) from _dsp_pick) <> n then raise exception 'not owned'; end if;
  if exists (select 1 from dispatch_runs r where r.user_id = uid and r.claimed_at is null and r.uids && p_uids) then raise exception 'busy'; end if;
  if exists (select 1 from _dsp_pick where grade >= 5) then raise exception 'banned grade'; end if;
  select max(grade) into mx from _dsp_pick;
  if mx < z.min_grade then raise exception 'need grade'; end if;
  select count(*) filter (where el = o.el), count(*) filter (where cls = o.cls) into ne, nc from _dsp_pick;
  bon := least(60, 15 * (ne + nc)) + case when mx > z.min_grade then 10 else 0 end;
  great := least(60, 15 * (ne + nc)) >= 60 and random() < 0.10;
  f := _dsp_mult(p_hours) * (1 + bon / 100.0) * case when great then 2 else 1 end;
  for k, v in select key, value::numeric from jsonb_each_text(z.rw) loop
    v := v * f; cnt := floor(v)::int + case when random() < v - floor(v) then 1 else 0 end;
    if cnt > 0 then rw := rw || jsonb_build_object(k, cnt); end if;
  end loop;
  update dispatch_offers set taken = true where user_id = uid and slot = p_slot;
  insert into dispatch_daily (user_id, day, starts) values (uid, _dsp_day(), 1) on conflict (user_id, day) do update set starts = dispatch_daily.starts + 1;
  insert into dispatch_runs (user_id, zone, el, cls, hours, uids, bonus, great, reward, ends_at)
    values (uid, z.id, o.el, o.cls, p_hours, p_uids, bon, great, rw, now() + make_interval(hours => p_hours));
  return _dsp_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$-- 일찍 부르기 (보상 없음, 카드 바로 풀림, 의뢰도 다시 쓸 수 없음)
create or replace function public.dispatch_recall(p_run bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  update dispatch_runs set claimed_at = now(), recalled = true where id = p_run and user_id = uid and claimed_at is null and ends_at > now();
  if not found then raise exception 'no run'; end if;
  return _dsp_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$-- 받기 (p_run = null 이면 끝난 것 모두)
create or replace function public.dispatch_claim(p_run bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r dispatch_runs; tot jsonb := '{}'::jsonb; k text; v int; cur jsonb; got int := 0; w jsonb; t int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  for r in select * from dispatch_runs where user_id = uid and claimed_at is null and ends_at <= now() and (p_run is null or id = p_run) for update loop
    update dispatch_runs set claimed_at = now() where id = r.id;
    got := got + 1;
    for k, v in select key, value::int from jsonb_each_text(r.reward) loop
      tot := jsonb_set(tot, array[k], to_jsonb(coalesce((tot->>k)::int, 0) + v));
    end loop;
    if (r.reward->>'gem') is not null then perform _gem_add(uid, (r.reward->>'gem')::int, 0, 'dispatch', 'dispatch:' || r.id, jsonb_build_object('zone', r.zone)); end if;
    if (r.reward->>'drink') is not null then perform _item_add(uid, 'drink', 0, (r.reward->>'drink')::int, 'dispatch', 'dispatch:' || r.id, jsonb_build_object('zone', r.zone)); end if;
  end loop;
  if got = 0 then raise exception 'nothing to claim'; end if;
  cur := '{}'::jsonb;
  foreach k in array array['gold', 'blood', 'shard', 'soul'] loop if tot ? k then cur := cur || jsonb_build_object(k, (tot->>k)::int); end if; end loop;
  if cur <> '{}'::jsonb then w := _wallet_add(uid, cur, 'dispatch'); end if;
  if coalesce((tot->>'tickets')::int, 0) > 0 then
    update story_gacha set tickets = tickets + (tot->>'tickets')::int, updated_at = now() where user_id = uid returning tickets into t;
    if t is null then insert into story_gacha (user_id, last_draw, tickets) values (uid, _dsp_day() - 1, (tot->>'tickets')::int); end if;
  end if;
  return _dsp_json(uid) || jsonb_build_object('got', tot, 'claimed', got, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._dsp_fill(uuid, boolean), public._dsp_json(uuid), public._dsp_level(uuid), public._dsp_owned(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.dispatch_status(), public.dispatch_refresh(), public.dispatch_start(int, text[], int), public.dispatch_recall(bigint), public.dispatch_claim(bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.dispatch_status(), public.dispatch_refresh(), public.dispatch_start(int, text[], int), public.dispatch_recall(bigint), public.dispatch_claim(bigint) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: dispatch_safeupdate.sql =====
-- 파견 일괄 보내기 'DELETE requires a WHERE clause' 수정 (2026-11-04). dispatch.sql 뒤에 실행. create or replace 만 (데이터 변경 없음)
-- 원인: dispatch_start 안 임시표 비우기 'delete from _dsp_pick;' 에 WHERE 가 없어 pg_safeupdate 가 막음 → 'where true' 추가 (동작 같음)
create or replace function public.dispatch_start(p_slot int, p_uids text[], p_hours int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); o dispatch_offers; z dispatch_zones; owned jsonb; n int; mx int; bon int := 0; ne int; nc int; over boolean; k text; v numeric; rw jsonb := '{}'::jsonb; f numeric; great boolean := false; cnt int; d dispatch_daily;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_hours not in (1, 4, 8, 12) then raise exception 'bad hours'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  select * into o from dispatch_offers where user_id = uid and slot = p_slot for update;
  if o.user_id is null or o.day <> _dsp_day() then raise exception 'no offer'; end if;
  if o.taken then raise exception 'taken'; end if;
  select * into z from dispatch_zones where id = o.zone;
  if (select count(*) from dispatch_runs where user_id = uid and claimed_at is null) >= _dsp_slots(_dsp_level(uid)) then raise exception 'slots full'; end if;
  select * into d from dispatch_daily where user_id = uid and day = _dsp_day();
  if coalesce(d.starts, 0) >= _dsp_cap() then raise exception 'daily cap'; end if;
  n := coalesce(array_length(p_uids, 1), 0);
  if n < 1 or n > z.size or (select count(distinct u) from unnest(p_uids) u) <> n then raise exception 'bad cards'; end if;
  owned := _dsp_owned(uid);
  -- 가진 카드인지 + 카드 정보
  create temp table if not exists _dsp_pick (uid text, grade int, el text, cls text) on commit drop; delete from _dsp_pick where true;
  insert into _dsp_pick select u, m.grade, m.el, m.cls from unnest(p_uids) u
    join lateral (select x from jsonb_array_elements(owned) x where x->>'uid' = u limit 1) ox on true
    join dispatch_card_meta m on m.id = ox.x->>'id';
  if (select count(*) from _dsp_pick) <> n then raise exception 'not owned'; end if;
  if exists (select 1 from dispatch_runs r where r.user_id = uid and r.claimed_at is null and r.uids && p_uids) then raise exception 'busy'; end if;
  if exists (select 1 from _dsp_pick where grade >= 5) then raise exception 'banned grade'; end if;
  select max(grade) into mx from _dsp_pick;
  if mx < z.min_grade then raise exception 'need grade'; end if;
  select count(*) filter (where el = o.el), count(*) filter (where cls = o.cls) into ne, nc from _dsp_pick;
  bon := least(60, 15 * (ne + nc)) + case when mx > z.min_grade then 10 else 0 end;
  great := least(60, 15 * (ne + nc)) >= 60 and random() < 0.10;
  f := _dsp_mult(p_hours) * (1 + bon / 100.0) * case when great then 2 else 1 end;
  for k, v in select key, value::numeric from jsonb_each_text(z.rw) loop
    v := v * f; cnt := floor(v)::int + case when random() < v - floor(v) then 1 else 0 end;
    if cnt > 0 then rw := rw || jsonb_build_object(k, cnt); end if;
  end loop;
  update dispatch_offers set taken = true where user_id = uid and slot = p_slot;
  insert into dispatch_daily (user_id, day, starts) values (uid, _dsp_day(), 1) on conflict (user_id, day) do update set starts = dispatch_daily.starts + 1;
  insert into dispatch_runs (user_id, zone, el, cls, hours, uids, bonus, great, reward, ends_at)
    values (uid, z.id, o.el, o.cls, p_hours, p_uids, bon, great, rw, now() + make_interval(hours => p_hours));
  return _dsp_json(uid);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.dispatch_start(int, text[], int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.dispatch_start(int, text[], int) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild_lend_cap.sql =====
-- 조직 인재 대여: 원주인 보상 하루 3번 · 빌리는 사람 조직 가입 24시간 + 계정 Lv10 — 선행: guild_lend.sql (+ guild_lend_notice.sql)
-- 여러 번 실행해도 안전 (열 추가·함수 다시 정의만, 데이터 삭제 없음). guild_lend_borrow 를 이 파일 것으로 바꿈
alter table public.guild_loans add column if not exists reward int;$vr_statement$;
  execute $vr_statement$-- 이 대여로 원주인이 받은 충성 (예전 기록은 null = 기본 보상으로 봄)
create or replace function public._lend_reward_daily() returns int language sql immutable as $$ select 3 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lend_join_hours() returns int language sql immutable as $$ select 24 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lend_min_level() returns int language sql immutable as $$ select 10 $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._lend_reward_daily(), public._lend_join_hours(), public._lend_min_level() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.guild_lend_borrow(p_owner uuid, p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); gid bigint; jt timestamptz; plv int; rw int; nrw int; s guild_lend_slots; o jsonb; snap jsonb; lid bigint; ex timestamptz;
begin
  if me is null then raise exception 'login required'; end if;
  if p_owner = me then raise exception 'own card'; end if;
  select guild_id, joined_at into gid, jt from guild_members where user_id = me;
  if gid is null then raise exception 'not in guild'; end if;
  if jt > now() - make_interval(hours => _lend_join_hours()) then raise exception 'joined too recently'; end if;   -- 조직 가입 24시간 뒤부터
  select level into plv from player_state where user_id = me;
  if coalesce(plv, 1) < _lend_min_level() then raise exception 'level too low'; end if;   -- 계정 Lv10 부터
  if not exists (select 1 from guild_members where user_id = p_owner and guild_id = gid) then raise exception 'not guildmate'; end if;
  perform pg_advisory_xact_lock(hashtext('guild_lend:' || me::text));
  if exists (select 1 from guild_loans where borrower = me and day = _guild_day()) then raise exception 'already borrowed today'; end if;
  select * into s from guild_lend_slots where user_id = p_owner and uid = p_uid;
  if s.user_id is null then raise exception 'not lendable'; end if;
  o := _lend_owned(p_owner, p_uid);
  if o is null then raise exception 'not lendable'; end if;
  if exists (select 1 from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
             where sp.user_id = me and x->>'id' = s.card_id) then raise exception 'already own card'; end if;
  snap := jsonb_strip_nulls(jsonb_build_object('id', o->'id', 'level', o->'level', 'boost', o->'boost', 'ex', o->'ex', 'exb', o->'exb', 'skillLv', o->'skillLv'));
  ex := now() + make_interval(hours => _lend_hours());
  perform pg_advisory_xact_lock(hashtext('guild_lend_reward:' || p_owner::text));
  select count(*) into nrw from guild_loans where lender = p_owner and day = _guild_day() and coalesce(reward, 0) > 0;
  rw := case when nrw < _lend_reward_daily() then _lend_reward() else 0 end;   -- 원주인 보상: 하루(KST) 3번까지 (그 뒤로도 빌려줄 수는 있음, 보상만 없음)
  insert into guild_loans (borrower, lender, guild_id, card_id, src_uid, snap, day, expires_at, reward) values (me, p_owner, gid, s.card_id, p_uid, snap, _guild_day(), ex, rw) returning id into lid;
  if rw > 0 then perform _loyalty_add(p_owner, rw, 'lend', 'lend:' || lid, jsonb_build_object('borrower', me, 'card', s.card_id)); end if;
  perform _guild_log(gid, me, 'lend', p_owner, jsonb_build_object('card', s.card_id));
  return jsonb_build_object('ok', true, 'id', lid, 'card_id', s.card_id, 'snap', snap, 'expires_at', ex, 'lender_reward', rw);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_lend_borrow(uuid, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_lend_borrow(uuid, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 알림: 실제로 받은 보상(0 이면 0)을 보여 줌
create or replace function public.guild_lend_notices() returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r jsonb;
begin
  if me is null then raise exception 'login required'; end if;
  with x as (
    select l.id from guild_loans l where l.lender = me and not l.lender_seen and l.borrowed_at > now() - interval '7 days' order by l.borrowed_at desc limit 30),
  u as (update guild_loans l set lender_seen = true from x where l.id = x.id returning l.*)
  select coalesce(jsonb_agg(jsonb_build_object('borrower_name', coalesce(p.nickname, '조직원'), 'card_id', u.card_id, 'reward', coalesce(u.reward, _lend_reward()), 'at', u.borrowed_at) order by u.borrowed_at desc), '[]'::jsonb) into r
    from u left join profiles p on p.id = u.borrower;
  update guild_loans set lender_seen = true where lender = me and not lender_seen;   -- 7일 지난 것도 정리
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_lend_notices() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_lend_notices() to authenticated;$vr_statement$;
  execute $vr_statement$select 'guild_lend_cap ok' as result;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild_quest_draw.sql =====
-- 조직 일일 의뢰 '페이즈 정리 5' → '인재 소환 1회' (보상 그대로: 세력 10 · 골드 800 · 충성 15)
-- 진행도 = 소환 기록(story_gacha_log) 1줄마다 +1 → 무료·소환권·10연 모두 셈 (guild2.sql _guild_trg_draw)
-- 같은 종류 중복 방지: 예전 '소환'(d_draw) 의뢰는 새로 뽑히지 않게 끔 (오늘 이미 받은 d_draw 는 그대로 진행·받기 가능)
-- 여러 번 돌려도 안전. 받은 의뢰·다른 의뢰·3개 완료 보너스는 건드리지 않음
-- 설치본의 단일 트랜잭션에 포함
update public.guild_quest_pool
   set event = 'draw', goal = 1, label = '인재 소환 1회', icon = '🎴',
       reward = '{"loyalty":15,"gold":800,"exp":10}'::jsonb
 where key = 'd_phase';$vr_statement$;
  execute $vr_statement$update public.guild_quest_pool set active = false where key = 'd_draw';$vr_statement$;
  execute $vr_statement$-- 오늘(이후) 아직 안 받은 '페이즈 정리' 의뢰: 목표 5 → 1. 진행도가 1 이상이었으면 바로 받기 가능, 0 이면 다음 소환부터
update public.guild_daily_quests
   set goal = 1, progress = least(1, progress)
 where qkey = 'd_phase' and claimed_at is null and day >= public._guild_day() and goal <> 1;$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함
-- 확인: select key, event, goal, label, reward, active from public.guild_quest_pool where key in ('d_phase', 'd_draw');


-- ===== SOURCE: guild_quest_raid.sql =====
-- 조직 일일 의뢰 '보스 처치' → '균열 토벌' (레이드 보스). 진행도 = 균열 토벌 전투 1회마다 +1 (guild3.sql raid_finish 가 _guild_event(uid,'raid',1) 호출)
-- 여러 번 돌려도 안전. 오늘 이미 받은 의뢰도 다음 토벌부터 바로 반영 (진행도는 qkey → pool.event 로 셈)
update public.guild_quest_pool set event = 'raid', label = '균열 토벌', icon = '🐉' where key = 'd_boss';$vr_statement$;
  execute $vr_statement$-- 확인: select key, kind, event, label from public.guild_quest_pool where key = 'd_boss';


-- ===== SOURCE: mail_v2.sql =====
-- =====================================================================
-- 우편 v2: 관리자 선물·메시지 우편 (개인 / 전체)  — SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: admin.sql, gem.sql, phaseE_1.sql, gear_v1.sql, gear_drops.sql
-- 기존 player_mail(장비·상자·증표 조각) 데이터는 건드리지 않음 (컬럼 추가 + kind 'msg' 허용만)
--
-- 구조
--  * 개인 우편: player_mail 에 kind='msg' 한 줄
--  * 전체 우편: mail_broadcast 에 한 줄만 저장. 유저가 우편함/뱃지를 열 때 _mail_sync 가
--    자기 몫을 player_mail 로 복사 (unique(user_id, broadcast_id) → 중복 지급 불가)
--    → 유저 수만큼 insert 하지 않음. 보낸 뒤 가입한 유저도 만료 전이면 받음
--  * 첨부(payload): { gem, tickets, cur:{gold,blood,shard,soul}, gear:"def_id" }
--  * 받기: 행 잠금(for update) + claimed_at 한 번만 → 원자적·중복 불가
-- =====================================================================

alter table public.admin_log add column if not exists meta jsonb;$vr_statement$;
  execute $vr_statement$alter table public.player_mail add column if not exists title text;$vr_statement$;
  execute $vr_statement$alter table public.player_mail add column if not exists body text;$vr_statement$;
  execute $vr_statement$alter table public.player_mail add column if not exists broadcast_id bigint;$vr_statement$;
  execute $vr_statement$alter table public.player_mail add column if not exists read_at timestamptz;$vr_statement$;
  execute $vr_statement$alter table public.player_mail drop constraint if exists player_mail_kind_check;$vr_statement$;
  execute $vr_statement$alter table public.player_mail add constraint player_mail_kind_check check (kind in ('gear', 'box', 'sigil_frag', 'gold', 'gem', 'msg'));$vr_statement$;
  execute $vr_statement$create unique index if not exists player_mail_bc_uniq on public.player_mail (user_id, broadcast_id) where broadcast_id is not null;$vr_statement$;
  execute $vr_statement$create table if not exists public.mail_broadcast (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 60),
  body text check (char_length(body) <= 1000),
  payload jsonb not null default '{}'::jsonb,
  created_by text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);$vr_statement$;
  execute $vr_statement$alter table public.mail_broadcast enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.mail_broadcast from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 첨부 검증 (내부)
create or replace function public._mail_clean_payload(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb := '{}'::jsonb; c jsonb := '{}'::jsonb; k text; v int; g text;
begin
  p := coalesce(p, '{}'::jsonb);
  v := coalesce((p->>'gem')::int, 0);
  if v < 0 or v > 1000000 then raise exception 'gem must be 0..1000000'; end if;
  if v > 0 then r := r || jsonb_build_object('gem', v); end if;
  v := coalesce((p->>'tickets')::int, 0);
  if v < 0 or v > 1000 then raise exception 'tickets must be 0..1000'; end if;
  if v > 0 then r := r || jsonb_build_object('tickets', v); end if;
  for k in select jsonb_object_keys(coalesce(p->'cur', '{}'::jsonb)) loop
    if k not in ('gold', 'blood', 'shard', 'soul') then raise exception 'invalid currency: %', k; end if;
    v := coalesce((p->'cur'->>k)::int, 0);
    if v < 0 or v > 1000000 then raise exception 'currency must be 0..1000000'; end if;
    if v > 0 then c := c || jsonb_build_object(k, v); end if;
  end loop;
  if c <> '{}'::jsonb then r := r || jsonb_build_object('cur', c); end if;
  g := nullif(btrim(coalesce(p->>'gear', '')), '');
  if g is not null then
    if not exists (select 1 from gear_defs where id = g and tier <= 5 and not coalesce(event_only, false)) then raise exception 'invalid gear (영웅 이하·일반 장비만)'; end if;
    r := r || jsonb_build_object('gear', g);
  end if;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._mail_clean_payload(jsonb) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 전체 우편 → 내 우편함으로 복사 (내부)
create or replace function public._mail_sync(p_uid uuid) returns void language sql security definer set search_path = public as $$
  insert into player_mail (user_id, kind, payload, reason, title, body, broadcast_id, created_at, expires_at)
  select p_uid, 'msg', b.payload, 'admin_broadcast', b.title, b.body, b.id, b.created_at, b.expires_at
    from mail_broadcast b where b.expires_at > now()
  on conflict (user_id, broadcast_id) where broadcast_id is not null do nothing $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._mail_sync(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 관리자: 한 명에게
create or replace function public.admin_mail_send(p_user uuid, p_title text, p_body text, p_payload jsonb, p_days int default 7) returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare pl jsonb; mid bigint;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_title), '') = '' or char_length(p_title) > 60 then raise exception 'title 1..60'; end if;
  if char_length(coalesce(p_body, '')) > 1000 then raise exception 'body too long'; end if;
  if p_days is null or p_days < 1 or p_days > 30 then raise exception 'days must be 1..30'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  pl := public._mail_clean_payload(p_payload);
  insert into public.player_mail (user_id, kind, payload, reason, title, body, expires_at)
    values (p_user, 'msg', pl, 'admin', btrim(p_title), nullif(btrim(coalesce(p_body, '')), ''), now() + make_interval(days => p_days)) returning id into mid;
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, meta)
    values (auth.uid(), auth.jwt()->>'email', 'mail_send', p_user, p_days, left(btrim(p_title), 200), pl || jsonb_build_object('mail_id', mid));
  return jsonb_build_object('ok', true, 'mail_id', mid);
end $$;$vr_statement$;
  execute $vr_statement$-- 관리자: 전체
create or replace function public.admin_mail_broadcast(p_title text, p_body text, p_payload jsonb, p_days int default 7) returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare pl jsonb; bid bigint;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_title), '') = '' or char_length(p_title) > 60 then raise exception 'title 1..60'; end if;
  if char_length(coalesce(p_body, '')) > 1000 then raise exception 'body too long'; end if;
  if p_days is null or p_days < 1 or p_days > 30 then raise exception 'days must be 1..30'; end if;
  pl := public._mail_clean_payload(p_payload);
  insert into public.mail_broadcast (title, body, payload, created_by, expires_at)
    values (btrim(p_title), nullif(btrim(coalesce(p_body, '')), ''), pl, auth.jwt()->>'email', now() + make_interval(days => p_days)) returning id into bid;
  insert into public.admin_log (admin_id, admin_email, action, amount, reason, meta)
    values (auth.uid(), auth.jwt()->>'email', 'mail_broadcast', p_days, left(btrim(p_title), 200), pl || jsonb_build_object('broadcast_id', bid));
  return jsonb_build_object('ok', true, 'broadcast_id', bid);
end $$;$vr_statement$;
  execute $vr_statement$-- 관리자: 보낸 전체 우편 목록 (+받은 수)
create or replace function public.admin_mail_broadcasts(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'payload', b.payload, 'created_at', b.created_at, 'expires_at', b.expires_at,
      'claimed', (select count(*) from player_mail m where m.broadcast_id = b.id and m.claimed_at is not null)) order by b.id desc)
    from (select * from mail_broadcast order by id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) b), '[]'::jsonb);
end $$;$vr_statement$;
  execute $vr_statement$-- 우편 목록 (기존 mail_list 대체: 전체 우편 동기화 + 제목/본문/읽음 포함, 기존 필드 유지)
create or replace function public.mail_list() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform _mail_sync(uid);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'payload', payload, 'reason', reason, 'expires_at', expires_at,
      'title', title, 'body', body, 'read', read_at is not null, 'created_at', created_at) order by (kind = 'msg') desc, id desc)
    from player_mail where user_id = uid and claimed_at is null and expires_at > now()), '[]'::jsonb);
end $$;$vr_statement$;
  execute $vr_statement$-- 뱃지용: 안 받은 우편 수 (메시지는 안 읽은 것만 = 읽었어도 첨부 남았으면 셈)
create or replace function public.mail_unread() returns int
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return 0; end if;
  perform _mail_sync(uid);
  return (select count(*) from player_mail where user_id = uid and claimed_at is null and expires_at > now()
    and (kind <> 'msg' or read_at is null or payload <> '{}'::jsonb))::int;
end $$;$vr_statement$;
  execute $vr_statement$-- 메시지 우편 받기/확인: 첨부 전부 한 번에 (원자적). 첨부 없으면 확인 = 삭제
create or replace function public.mail_msg_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; p jsonb; k text; gid bigint; d gear_defs; w jsonb; got jsonb := '{}'::jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found or ml.kind <> 'msg' then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  p := coalesce(ml.payload, '{}'::jsonb);
  if p ? 'gear' and _gear_bag_full(uid) then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  if coalesce((p->>'gem')::int, 0) > 0 then
    perform _gem_add(uid, (p->>'gem')::int, 0, 'mail', 'mail:' || ml.id, jsonb_build_object('mail_id', ml.id, 'broadcast_id', ml.broadcast_id));
    got := got || jsonb_build_object('gem', (p->>'gem')::int);
  end if;
  if coalesce((p->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p->>'tickets')::int, updated_at = now() where user_id = uid;
    got := got || jsonb_build_object('tickets', (p->>'tickets')::int);
  end if;
  if p ? 'cur' and p->'cur' <> '{}'::jsonb then
    w := _wallet_add(uid, p->'cur', 'mail');
    got := got || jsonb_build_object('cur', p->'cur');
  end if;
  if p ? 'gear' then
    select * into d from gear_defs where id = p->>'gear';
    if found then
      insert into player_gear (user_id, def_id, opts, source, locked) values (uid, d.id, _gear_roll_opts(d.id), 'mail:admin', false) returning id into gid;
      got := got || jsonb_build_object('gear_id', gid, 'def_id', d.id);
    end if;
  end if;
  update player_mail set claimed_at = now(), read_at = coalesce(read_at, now()) where id = ml.id;
  return jsonb_build_object('ok', true, 'got', got, 'wallet', w);
end $$;$vr_statement$;
  execute $vr_statement$-- 읽음 표시 (열어봤을 때)
create or replace function public.mail_read(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  update player_mail set read_at = now() where id = p_id and user_id = auth.uid() and kind = 'msg' and read_at is null;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_mail_send(uuid, text, text, jsonb, int), public.admin_mail_broadcast(text, text, jsonb, int), public.admin_mail_broadcasts(int),
  public.mail_list(), public.mail_unread(), public.mail_msg_claim(bigint), public.mail_read(bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_mail_send(uuid, text, text, jsonb, int), public.admin_mail_broadcast(text, text, jsonb, int), public.admin_mail_broadcasts(int),
  public.mail_list(), public.mail_unread(), public.mail_msg_claim(bigint), public.mail_read(bigint) to authenticated;$vr_statement$;
  execute $vr_statement$-- 확인: select public.mail_unread();  /  select id, title, expires_at from public.mail_broadcast order by id desc;


-- ===== SOURCE: arcade_tut.sql =====
-- =====================================================================
-- 📖 유리의 특강 (아케이드 튜토리얼) 첫 클리어 보상 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_gacha.sql (소환권 = 영입권, story_gacha.tickets) · gem.sql (_gem_day)
-- 보상: 초급 영입권 10 · 중급 100 · 상급 300 (계정당 단계별 1회, 앞 단계를 받아야 다음 단계)
-- 공개 RPC: arcade_tut_status() · arcade_tut_claim(stage)
-- 확인용: select public.arcade_tut_status();
-- =====================================================================

create table if not exists public.arcade_tut_claims (
  user_id    uuid not null references auth.users(id) on delete cascade,
  stage      int  not null check (stage between 1 and 3),
  tickets    int  not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, stage)
);$vr_statement$;
  execute $vr_statement$alter table public.arcade_tut_claims enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.arcade_tut_claims from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._arcade_tut_reward(p_stage int) returns int language sql immutable as $$
  select case p_stage when 1 then 10 when 2 then 100 when 3 then 300 end
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public._arcade_tut_reward(int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true,
    'claimed', coalesce((select jsonb_agg(stage order by stage) from arcade_tut_claims where user_id = uid), '[]'::jsonb),
    'rewards', jsonb_build_object('1', _arcade_tut_reward(1), '2', _arcade_tut_reward(2), '3', _arcade_tut_reward(3)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_claim(p_stage int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); amt int := _arcade_tut_reward(p_stage); n int; t int;
begin
  if uid is null then raise exception 'login required'; end if;
  if amt is null then raise exception 'bad stage'; end if;
  if p_stage > 1 and not exists (select 1 from arcade_tut_claims where user_id = uid and stage = p_stage - 1) then raise exception 'previous stage first'; end if;
  insert into arcade_tut_claims (user_id, stage, tickets) values (uid, p_stage, amt) on conflict (user_id, stage) do nothing;
  get diagnostics n = row_count;
  if n = 0 then
    select tickets into t from story_gacha where user_id = uid;
    return jsonb_build_object('ok', true, 'already', true, 'stage', p_stage, 'tickets', coalesce(t, 0));
  end if;
  insert into story_gacha (user_id, last_draw) values (uid, _gem_day() - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = tickets + amt, updated_at = now() where user_id = uid returning tickets into t;
  return jsonb_build_object('ok', true, 'stage', p_stage, 'gave', amt, 'tickets', t);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.arcade_tut_status(), public.arcade_tut_claim(int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.arcade_tut_status(), public.arcade_tut_claim(int) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: arcade_tut_gem.sql =====
-- =====================================================================
-- 📖 유리의 특강 첫 클리어 보상 변경 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: arcade_tut.sql · gem.sql (_gem_add, player_wallet.gem_free) · story_gacha.sql (영입권 = story_gacha.tickets)
-- 보상: 초급 영입권 10 · 중급 심연석 100 · 상급 심연석 300 (무료 심연석) — 계정당 단계별 1회, 앞 단계를 받아야 다음 단계
-- 이미 받은 단계는 다시 지급하지 않음 (예전 보상으로 받은 기록도 그대로 '받음')
-- =====================================================================

alter table public.arcade_tut_claims add column if not exists kind text not null default 'tickets';$vr_statement$;
  execute $vr_statement$-- tickets | gem

create or replace function public._arcade_tut_rw(p_stage int) returns jsonb language sql immutable as $$
  select case p_stage when 1 then '{"kind":"tickets","n":10}'::jsonb
                      when 2 then '{"kind":"gem","n":100}'::jsonb
                      when 3 then '{"kind":"gem","n":300}'::jsonb end
$$;$vr_statement$;
  execute $vr_statement$revoke all on function public._arcade_tut_rw(int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true,
    'claimed', coalesce((select jsonb_agg(stage order by stage) from arcade_tut_claims where user_id = uid), '[]'::jsonb),
    'rewards', jsonb_build_object('1', _arcade_tut_rw(1), '2', _arcade_tut_rw(2), '3', _arcade_tut_rw(3)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_tut_claim(p_stage int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rw jsonb := _arcade_tut_rw(p_stage); amt int; k text; n int; t int; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if rw is null then raise exception 'bad stage'; end if;
  if p_stage > 1 and not exists (select 1 from arcade_tut_claims where user_id = uid and stage = p_stage - 1) then raise exception 'previous stage first'; end if;
  amt := (rw->>'n')::int; k := rw->>'kind';
  insert into arcade_tut_claims (user_id, stage, tickets, kind) values (uid, p_stage, amt, k) on conflict (user_id, stage) do nothing;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', true, 'already', true, 'stage', p_stage, 'kind', k); end if;
  if k = 'gem' then
    g := _gem_add(uid, amt, 0, 'arcade_tut', 'arcade_tut:' || p_stage, jsonb_build_object('stage', p_stage));
    return jsonb_build_object('ok', true, 'stage', p_stage, 'kind', 'gem', 'gave', amt, 'gem', g->'gem');
  end if;
  insert into story_gacha (user_id, last_draw) values (uid, _gem_day() - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = tickets + amt, updated_at = now() where user_id = uid returning tickets into t;
  return jsonb_build_object('ok', true, 'stage', p_stage, 'kind', 'tickets', 'gave', amt, 'tickets', t);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.arcade_tut_status(), public.arcade_tut_claim(int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.arcade_tut_status(), public.arcade_tut_claim(int) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: pvp_boss_deck2.sql =====
-- =====================================================================
-- PvP 보스리그 덱 = 리더 1장(수비대장 · HR 이하) + 멤버 1~5장 (총 2~6장). 여러 번 실행해도 안전. 삭제 없음.
-- 필요: pvp.sql · gem.sql · gear_snap.sql · pvp_boss_league.sql 다음에 실행
-- 바뀌는 것: _pvp_snap_mode(새) · 보스 덱 트리거 · pvp_set_deck · pvp_start (보스 덱 스냅샷만 _pvp_snap_mode 로, 1v1·3v3 은 그대로 _pvp_snap)
--   ※ 나중에 gem.sql 을 다시 실행하면 pvp_start 가 예전 것으로 돌아가니 이 파일도 다시 실행
-- =====================================================================

-- 1) 덱 스냅샷 (모드별): boss = 리더 1장 + 멤버 1~5장 → _pvp_snap 을 두 번 불러 이어 붙임 (장비·증표 규칙 그대로)
create or replace function public._pvp_snap_mode(p_user uuid, p_uids jsonb, p_league text, p_mode text) returns jsonb language plpgsql stable set search_path = public as $$
declare a jsonb; b jsonb; n int; cost int;
begin
  if p_mode is distinct from 'boss' then return _pvp_snap(p_user, p_uids, p_league); end if;
  if jsonb_typeof(p_uids) <> 'array' then raise exception 'deck size'; end if;
  n := jsonb_array_length(p_uids);
  if n < 2 then raise exception 'boss members'; end if;   -- 멤버 1장 이상
  if n > 6 then raise exception 'deck size'; end if;      -- 멤버 최대 5장
  a := _pvp_snap(p_user, jsonb_build_array(p_uids->0), p_league);
  b := _pvp_snap(p_user, (select jsonb_agg(x order by i) from jsonb_array_elements(p_uids) with ordinality t(x, i) where i > 1), p_league);
  if exists (select 1 from jsonb_array_elements(b->'cards') x where x->>'id' = a->'cards'->0->>'id') then raise exception 'duplicate card'; end if;
  cost := (a->>'cost')::int + (b->>'cost')::int;
  if p_league = 'hr' and cost > 150 then raise exception 'cost over 150'; end if;
  return jsonb_build_object('cards', (a->'cards') || (b->'cards'), 'cost', cost);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_snap_mode(uuid, jsonb, text, text) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 보스리그 덱 트리거: 첫 장(리더) HR 이하 + 멤버 1~5장
create or replace function public._pvp_boss_deck_chk() returns trigger language plpgsql security definer set search_path = public as $$
declare g text; n int;
begin
  if new.mode <> 'boss' then return new; end if;
  select grade into g from pvp_card_meta where id = new.snap->0->>'id';
  if g is null or g not in ('NORMAL','RARE','HIGH RARE') then raise exception 'guard grade'; end if;
  n := jsonb_array_length(coalesce(new.snap, '[]'::jsonb));
  if n < 2 then raise exception 'boss members'; end if;
  if n > 6 then raise exception 'deck size'; end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._pvp_boss_deck_chk() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$drop trigger if exists pvp_boss_deck_chk on public.pvp_decks;$vr_statement$;
  execute $vr_statement$create trigger pvp_boss_deck_chk before insert or update on public.pvp_decks for each row execute function public._pvp_boss_deck_chk();$vr_statement$;
  execute $vr_statement$-- 3) 덱 등록 (pvp.sql 과 같음 · 스냅샷만 모드별)
create or replace function public.pvp_set_deck(p_league text, p_mode text, p_slot int, p_uids jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); s jsonb; other text[];
begin
  if uid is null then raise exception 'login required'; end if;
  if p_slot is null or p_slot < 0 or p_slot >= n then raise exception 'bad slot'; end if;
  if p_uids is null or jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) = 0 then
    delete from pvp_decks where user_id = uid and league = p_league and mode = p_mode and slot = p_slot;
    return jsonb_build_object('ok', true, 'slot', p_slot, 'cards', '[]'::jsonb);
  end if;
  s := _pvp_snap_mode(uid, p_uids, p_league, p_mode);
  -- 3v3: 같은 카드는 세 덱 중 한 곳에만
  select coalesce(array_agg(x->>'id'), '{}') into other from pvp_decks d, jsonb_array_elements(d.snap) x
    where d.user_id = uid and d.league = p_league and d.mode = p_mode and d.slot <> p_slot;
  if exists (select 1 from jsonb_array_elements(s->'cards') x where x->>'id' = any(other)) then raise exception 'card used in another deck'; end if;
  insert into pvp_decks (user_id, league, mode, slot, uids, snap, cost, updated_at)
  values (uid, p_league, p_mode, p_slot, p_uids, s->'cards', (s->>'cost')::int, now())
  on conflict (user_id, league, mode, slot) do update set uids = excluded.uids, snap = excluded.snap, cost = excluded.cost, updated_at = now();
  return jsonb_build_object('ok', true, 'slot', p_slot, 'cards', s->'cards', 'cost', (s->>'cost')::int);
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 매칭 시작 (gem.sql 과 같음 · 내 덱 다시 읽기만 모드별)
create or replace function public.pvp_start(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; me pvp_ratings; mine jsonb := '[]'::jsonb; d record;
        opp uuid; oname text; orat int; osnap jsonb := '[]'::jsonb; seed bigint; ex numeric; dw int; dl int; aid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('pvp:' || uid::text));
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  if used >= 10 + _pvp_extra(uid, p_league, p_mode) then raise exception 'no attempts left'; end if;
  if (select count(*) from pvp_decks where user_id = uid and league = p_league and mode = p_mode) < n then raise exception 'deck required'; end if;
  for d in select * from pvp_decks where user_id = uid and league = p_league and mode = p_mode order by slot loop
    mine := mine || jsonb_build_array(_pvp_snap_mode(uid, d.uids, p_league, p_mode)->'cards');
  end loop;
  me := _pvp_rating(uid, p_league, p_mode);
  -- 상대: 덱을 다 등록한 다른 유저 중 레이팅이 가까운 쪽 (약간의 무작위)
  select x.user_id, coalesce(r.rating, 1000) into opp, orat from (
      select user_id from pvp_decks where league = p_league and mode = p_mode and user_id <> uid group by user_id having count(*) >= n) x
    left join pvp_ratings r on r.user_id = x.user_id and r.league = p_league and r.mode = p_mode and r.season = _pvp_season()
    order by abs(coalesce(r.rating, 1000) - me.rating) + random() * 60 limit 1;
  if opp is not null then
    select coalesce(jsonb_agg(snap order by slot), '[]'::jsonb) into osnap from pvp_decks where user_id = opp and league = p_league and mode = p_mode and slot < n;
    select coalesce(nickname, '플레이어') into oname from profiles where id = opp;
    oname := coalesce(oname, '플레이어');
  else
    -- 상대 없음: 내 덱 거울 봇 (레벨 -10%)
    select coalesce(jsonb_agg((select coalesce(jsonb_agg(c || jsonb_build_object('level', greatest(1, round(coalesce((c->>'level')::int, 1) * 0.9)::int), 'boost', '{}'::jsonb)), '[]'::jsonb)
                               from jsonb_array_elements(dk) c)), '[]'::jsonb) into osnap from jsonb_array_elements(mine) dk;
    oname := '봇'; orat := me.rating;
  end if;
  ex := 1 / (1 + power(10, (orat - me.rating) / 400.0));
  dw := greatest(1, round(32 * (1 - ex))::int); dl := greatest(1, round(32 * ex)::int);
  if opp is null then dw := greatest(1, dw / 2); dl := greatest(1, dl / 2); end if;   -- 봇전은 절반
  seed := floor(random() * 2147483647)::bigint;
  insert into pvp_attempts (user_id, league, mode, season, day, opp_user, opp_name, seed, my_snap, opp_snap, my_rating, opp_rating, dw, dl)
  values (uid, p_league, p_mode, _pvp_season(), _pvp_day(), opp, oname, seed, mine, osnap, me.rating, orat, dw, dl) returning id into aid;
  update pvp_ratings set rating = rating - dl, losses = losses + 1, updated_at = now() where user_id = uid and league = p_league and mode = p_mode and season = _pvp_season();
  if opp is not null then perform _pvp_rating(opp, p_league, p_mode);
    update pvp_ratings set rating = rating + dl / 2, def_wins = def_wins + 1, updated_at = now() where user_id = opp and league = p_league and mode = p_mode and season = _pvp_season(); end if;
  return jsonb_build_object('id', aid, 'seed', seed, 'me', mine, 'opp', osnap, 'opp_name', oname, 'opp_rating', orat, 'rating', me.rating, 'dw', dw, 'dl', dl, 'left', 9 + _pvp_extra(uid, p_league, p_mode) - used, 'bot', opp is null);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_start(text, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_start(text, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 확인: 보스리그 덱 저장 — HR 1장만이면 'boss members', HR 리더 + 멤버 1~5장이면 저장


-- ===== SOURCE: story_ch10_rev.sql =====
-- =====================================================================
-- 챕터10 「마지막 랠리」 시트 개정 (10/30): 페이즈 18 → 17 (시트에 P17 없음 → 시트 P18 보스 = 게임 P17)
--   P16(떨리는 손) [염원] 최윤아 3명 → enemy_count 3 · P17 보스 [염원] 최윤아 1명 → enemy_count 1
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 주의: 챕터10 페이즈 18 설정 행 삭제 (없어진 페이즈라 남아 있으면 챕터 전체 클리어가 안 될 수 있음)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (10,1,'normal',3,null,5), (10,2,'normal',3,null,5), (10,3,'normal',3,null,5), (10,4,'normal',3,null,5), (10,5,'normal',3,null,5), (10,6,'normal',3,null,5), (10,7,'normal',3,null,5), (10,8,'normal',3,null,5), (10,9,'normal',3,null,5), (10,10,'normal',3,null,5), (10,11,'normal',3,null,5), (10,12,'normal',3,null,5), (10,13,'normal',3,null,5), (10,14,'normal',3,null,5), (10,15,'normal',3,null,5), (10,16,'normal',3,null,3), (10,17,'boss',5,null,1)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$delete from public.story_phase_config where chapter = 10 and phase > 17;$vr_statement$;
  execute $vr_statement$-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 10 order by phase;  → 17행 · 16 | normal | 3 | 3 · 17 | boss | 5 | 1


-- ===== SOURCE: story_ch11_wings.sql =====
-- =====================================================================
-- 챕터11 「사라지지 않는 약속」 시트 반영 (10/31): 날개 적 배치
--   P13 창밖 = [왼쪽 날개] 1명 → enemy_count 1 · P14 두 언니의 부탁 = [오른쪽 날개] 1명 → enemy_count 1
--   (P10~12 불량배 5명 · 나머지 페이즈는 그대로)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음. service_role 키 필요 없음.
-- =====================================================================
update public.story_phase_config set enemy_count = 1 where chapter = 11 and phase in (13, 14) and enemy_count is distinct from 1;$vr_statement$;
  execute $vr_statement$-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 11 order by phase;  → 16행 · 13·14 만 enemy_count 1


-- ===== SOURCE: story_ch11_p1_5.sql =====
-- =====================================================================
-- 챕터11 시트 개정 (10/31 오후): P1~P5 적 구성 변경
--   P5 유리 너머 = [염원] 최윤정 · [염원] 최윤아 2명 → enemy_count 2 (P1~P4 는 5명 그대로)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음.
-- =====================================================================
update public.story_phase_config set enemy_count = 2 where chapter = 11 and phase = 5 and enemy_count is distinct from 2;$vr_statement$;
  execute $vr_statement$-- 확인: select phase, enemy_count from public.story_phase_config where chapter = 11 order by phase;  → 5 = 2 · 13·14 = 1 · 나머지 5


-- ===== SOURCE: story_ch12.sql =====
-- =====================================================================
-- 스토리 챕터 12 「위대한 개츠비」(21 페이즈) 페이즈 설정 + 입장 레벨 22
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict · create or replace). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch9_11.sql · story_level_gate.sql 적용된 상태
-- 규칙은 챕터 9~11과 같음: 스탯 포인트 일반 3, 마지막 페이즈 5. P21 「첫눈」 = 일반 전투(적 전멸)라 type normal
-- enemy_count: 시트 적 수 (P17 4 · P20 3 · P21 3, 나머지 5)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (12,1,'normal',3,null,5), (12,2,'normal',3,null,5), (12,3,'normal',3,null,5), (12,4,'normal',3,null,5), (12,5,'normal',3,null,5), (12,6,'normal',3,null,5), (12,7,'normal',3,null,5), (12,8,'normal',3,null,5), (12,9,'normal',3,null,5), (12,10,'normal',3,null,5), (12,11,'normal',3,null,5), (12,12,'normal',3,null,5), (12,13,'normal',3,null,5), (12,14,'normal',3,null,5), (12,15,'normal',3,null,5), (12,16,'normal',3,null,5), (12,17,'normal',3,null,4), (12,18,'normal',3,null,5), (12,19,'normal',3,null,5), (12,20,'normal',3,null,1), (12,21,'normal',5,null,3)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- 입장 레벨: story_level_gate.sql 과 같은 함수에 chapter_12 = 22 만 추가
create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23
    else null end $$;$vr_statement$;
  execute $vr_statement$-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 12 order by phase;  → 21행


-- ===== SOURCE: story_ch12_p18_20.sql =====
-- CH12 P20: [염원] 이민채 3 → 1 (적 수 = 처치 보상 상한). P18·P19 는 생존 조건만 바뀌어 서버 변경 없음. 여러 번 실행해도 안전
update public.story_phase_config set enemy_count = 1 where chapter = 12 and phase = 20;$vr_statement$;
  execute $vr_statement$-- 확인용: 3행 (18·19 = 5, 20 = 1)
select phase, enemy_count from public.story_phase_config where chapter = 12 and phase in (18, 19, 20) order by phase;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch12_p14.sql =====
-- CH12 P14 「하얀 핸드랩」 시트 개정 (11/02): 안지수(필수) vs 임유리 1명 → enemy_count 5 → 1 (처치 EXP 상한)
-- 페이즈 수(21)·포인트·타입은 그대로. '져도 클리어(별 3개)' 는 게임 코드(js/story.js loseClears)라 서버 변경 없음
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전.
update public.story_phase_config set enemy_count = 1 where chapter = 12 and phase = 14;$vr_statement$;
  execute $vr_statement$-- 확인: 1행 · 14 | normal | 3 | 1
select phase, type, points, enemy_count from public.story_phase_config where chapter = 12 and phase = 14;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch13.sql =====
-- =====================================================================
-- 스토리 챕터 13 「예전의 너로」(15 페이즈) 페이즈 설정 + 입장 레벨 23
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict · create or replace). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch12.sql 적용된 상태
-- 스탯 포인트 일반 3, 마지막 페이즈 5. P15 「벌레」 = 일반 전투(1턴 생존)라 type normal. enemy_count = 시트 적 수
-- 보유 마나·별점·출전 조건·대본(P14)은 클라이언트(js/story-data-ch13.js)에만 있음
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (13,1,'normal',3,null,3), (13,2,'normal',3,null,3), (13,3,'normal',3,null,3), (13,4,'normal',3,null,5), (13,5,'normal',3,null,5), (13,6,'normal',3,null,1), (13,7,'normal',3,null,3), (13,8,'normal',3,null,3), (13,9,'normal',3,null,3), (13,10,'normal',3,null,3), (13,11,'normal',3,null,3), (13,12,'normal',3,null,5), (13,13,'normal',3,null,5), (13,14,'normal',3,null,1), (13,15,'normal',5,null,1)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24
    else null end $$;$vr_statement$;
  execute $vr_statement$-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 13 order by phase;  → 15행


-- ===== SOURCE: story_ch14.sql =====
-- =====================================================================
-- 스토리 챕터 14 「작은 아씨들」(18 페이즈) 페이즈 설정 + 입장 레벨 24
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict · create or replace). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch13.sql 적용된 상태
-- 스탯 포인트 일반 3, 마지막 페이즈 5. enemy_count = 시트 적 수 (P13 날개 2)
-- 보유 마나·별점·출전 조건은 클라이언트(js/story-data-ch14.js)에만 있음
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (14,1,'normal',3,null,5), (14,2,'normal',3,null,5), (14,3,'normal',3,null,5), (14,4,'normal',3,null,5), (14,5,'normal',3,null,5), (14,6,'normal',3,null,5), (14,7,'normal',3,null,5), (14,8,'normal',3,null,5), (14,9,'normal',3,null,5), (14,10,'normal',3,null,5), (14,11,'normal',3,null,5), (14,12,'normal',3,null,5), (14,13,'normal',3,null,2), (14,14,'normal',3,null,5), (14,15,'normal',3,null,5), (14,16,'normal',3,null,5), (14,17,'normal',3,null,5), (14,18,'normal',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24 when 'chapter_15' then 25
    else null end $$;$vr_statement$;
  execute $vr_statement$-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 14 order by phase;  → 18행


-- ===== SOURCE: story_ch15.sql =====
-- =====================================================================
-- 스토리 챕터 15 「검은 늪」(16 페이즈) 페이즈 설정 + 입장 레벨 25
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict · create or replace). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch14.sql 적용된 상태
-- 스탯 포인트 일반 3, 마지막 페이즈 5. enemy_count = 시트 적 수 (P6 2 · P14 1)
-- 보유 마나·별점·출전 조건은 클라이언트(js/story-data-ch15.js)에만 있음
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (15,1,'normal',3,null,5), (15,2,'normal',3,null,5), (15,3,'normal',3,null,5), (15,4,'normal',3,null,5), (15,5,'normal',3,null,5), (15,6,'normal',3,null,2), (15,7,'normal',3,null,5), (15,8,'normal',3,null,5), (15,9,'normal',3,null,5), (15,10,'normal',3,null,5), (15,11,'normal',3,null,5), (15,12,'normal',3,null,5), (15,13,'normal',3,null,5), (15,14,'normal',3,null,1), (15,15,'normal',3,null,5), (15,16,'normal',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
  select case p_key when 'sweep' then 5 when 'skill' then 10 when 'equip' then 15 when 'equip_merge' then 20
    when 'chapter_2' then 7 when 'chapter_3' then 9 when 'chapter_4' then 11 when 'chapter_5' then 12 when 'chapter_6' then 14
    when 'chapter_7' then 15 when 'chapter_8' then 16 when 'chapter_9' then 18 when 'chapter_10' then 20 when 'chapter_11' then 21 when 'chapter_12' then 22 when 'chapter_13' then 23 when 'chapter_14' then 24 when 'chapter_15' then 25
    else null end $$;$vr_statement$;
  execute $vr_statement$-- 확인: select phase, type, points, enemy_count from public.story_phase_config where chapter = 15 order by phase;  → 16행


-- ===== SOURCE: card_10509.sql =====
-- =====================================================================
-- 2026-10-31 신규 카드 강보람(10509, HIGH RARE, 코스트 33): 뽑기 풀 · 스킬 해금 레벨 · PVP 덱 검증
-- 사용법: SQL Editor에 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음. service_role 키 필요 없음.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10509','HIGH RARE','강보람',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;$vr_statement$;
  execute $vr_statement$insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10509',1,2),
  ('10509',2,5)
on conflict (card_id, idx) do update set unlock = excluded.unlock;$vr_statement$;
  execute $vr_statement$insert into public.pvp_card_meta (id, grade, cost) values
  ('10509','HIGH RARE',33)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;$vr_statement$;
  execute $vr_statement$-- 확인용: 4행
select 'pool' k, id, grade, name, gacha::text from public.story_card_pool where id = '10509'
union all select 'skill', card_id, idx::text, unlock::text, null from public.story_skill_meta where card_id = '10509'
union all select 'pvp', id, grade, cost::text, null from public.pvp_card_meta where id = '10509';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: gacha_premium_ur.sql =====
-- =====================================================================
-- 고급 소환(소환권 뽑기) UR 고정 목록. 새 UR 카드는 자동으로 들어가지 않음 (이 표에 넣어야 나옴)
-- 제외(2026-11-01 형님 결정): [각성] 윤진아 10291 · 이성호 10304 · 임규리 10322 · 하승진 10435 · 하지혜 10440 · 정아람 10359
-- 하루 1회 무료 뽑기 UR도 같은 목록 사용 (확률은 그대로). story_daily_draw 도 교체.
-- story_ticket_draw 교체 (story_ch0_jieun.sql 최신본 + UR 목록). 여러 번 실행해도 안전
-- =====================================================================
create table if not exists public.story_premium_ur (id text primary key, name text);$vr_statement$;
  execute $vr_statement$alter table public.story_premium_ur enable row level security;$vr_statement$;
  execute $vr_statement$drop policy if exists premium_ur_read on public.story_premium_ur;$vr_statement$;
  execute $vr_statement$create policy premium_ur_read on public.story_premium_ur for select using (true);$vr_statement$;
  execute $vr_statement$delete from public.story_premium_ur where id in ('10291','10304','10322','10435','10440','10359');$vr_statement$;
  execute $vr_statement$insert into public.story_premium_ur (id, name) values
  ('10051','김기림'),('10053','김대욱'),('10054','김동욱'),('10058','김백중'),('10176','서성민'),('10312','이진경'),
  ('10323','임나리'),('10324','임예리'),('10325','임유리'),('10331','임혜리'),('10358','정석윤')
on conflict (id) do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public.story_ticket_draw(p_count int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s jsonb; t int; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; out jsonb := '[]'::jsonb; i int; hr boolean := false;
  jslot int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_count is null or p_count not in (1, 10) then raise exception 'invalid count'; end if;
  s := _story_ticket_sync(uid);   -- story_gacha 행 잠금 포함
  t := (s->>'tickets')::int;
  if t < p_count then return jsonb_build_object('ok', false, 'reason', 'tickets', 'tickets', t, 'added', (s->>'added')::int); end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  if p_count = 10 and coalesce((d->>'ch0Pull')::boolean, false) = false and coalesce((d->>'ch0Jieun')::boolean, false) = false then
    jslot := 1 + floor(random() * 10)::int;   -- 강제 영입: 하지은 자리
    d := jsonb_set(d, '{ch0Jieun}', 'true'::jsonb);
  end if;
  for i in 1..p_count loop
    if i = jslot then
      cid := '10439'; g := 'SUPER RARE';
    else
      r := random();
      if p_count = 10 and i = 10 and not hr then   -- 10회 보장: 앞 9장이 모두 R 이하면 마지막 장은 HR 이상 (HR:SR:UR = 16:3.2:0.8)
        r := 0.80 + random() * 0.20;
      end if;
      g := case when r < 0.50 then 'NORMAL' when r < 0.80 then 'RARE' when r < 0.96 then 'HIGH RARE' when r < 0.992 then 'SUPER RARE' else 'ULTRA RARE' end;
      cid := null;
      if g = 'ULTRA RARE' then   -- 고급 소환 UR: 정해진 목록(story_premium_ur)에서만. 새 UR은 목록에 넣어야 나옴
        select p.id into cid from story_card_pool p join story_premium_ur w on w.id = p.id where p.grade = g order by random() limit 1;
      else
        select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
      end if;
      if cid is null then raise exception 'empty pool for %', g; end if;
    end if;
    if g in ('HIGH RARE', 'SUPER RARE', 'ULTRA RARE') then hr := true; end if;
    e := _story_new_card(cid);
    owned := owned || jsonb_build_array(e);
    out := out || jsonb_build_array(jsonb_build_object('card_id', cid, 'uid', e->>'uid', 'grade', g));
    insert into story_gacha_log (user_id, card_id, grade, kind) values (uid, cid, g, 'ticket');
  end loop;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  update story_gacha set tickets = tickets - p_count, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'cards', out, 'tickets', t - p_count, 'added', (s->>'added')::int);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_ticket_draw(int) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_ticket_draw(int) to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.story_daily_draw() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := (now() at time zone 'Asia/Seoul')::date; last date; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; cnt int;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_gacha (user_id, last_draw) values (uid, today - 1) on conflict (user_id) do nothing;
  select last_draw into last from story_gacha where user_id = uid for update;
  if last >= today then return jsonb_build_object('ok', false, 'reason', 'already', 'day', today); end if;
  r := random();
  g := case when r < 0.70 then 'NORMAL' when r < 0.90 then 'RARE' when r < 0.965 then 'HIGH RARE' when r < 0.995 then 'SUPER RARE' else 'ULTRA RARE' end;
  if g = 'ULTRA RARE' then   -- 무료 뽑기 UR도 고급 소환과 같은 목록(story_premium_ur)에서만
    select p.id into cid from story_card_pool p join story_premium_ur w on w.id = p.id where p.grade = g order by random() limit 1;
  else
    select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
  end if;
  if cid is null then raise exception 'empty pool for %', g; end if;
  d := _story_lock(uid);
  e := _story_new_card(cid);
  owned := _story_owned(d) || jsonb_build_array(e);
  select count(*) into cnt from jsonb_array_elements(owned) o where o->>'id' = cid;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{gachaLast}', to_jsonb(today::text));
  d := _story_save(uid, d);
  update story_gacha set last_draw = today, updated_at = now() where user_id = uid;
  insert into story_gacha_log (user_id, card_id, grade) values (uid, cid, g);
  return jsonb_build_object('ok', true, 'card_id', cid, 'uid', e->>'uid', 'grade', g, 'count', cnt, 'day', today);
end $$;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_daily_draw() to authenticated;$vr_statement$;
  execute $vr_statement$-- 확인용: 고급 소환에서 나올 수 있는 UR (11명)
select w.id, w.name, p.grade from public.story_premium_ur w left join public.story_card_pool p on p.id = w.id order by w.id;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_star_rewards.sql =====
-- 스토리 별 보상 (챕터별 ★9 · ★18 · 전부) — 선행: story_stars.sql. 여러 번 실행해도 안전 (함수만, 데이터 삭제 없음)
-- 마나 전투 페이즈만 셈: 챕터 1~ 전부 · 챕터 0 은 P4 만. 최대 = 3 × 그 페이즈 수
-- 별은 story_progress.data.stars 의 최고 별 중 실제로 클리어한(data.cleared) 페이즈만 합산
-- 받은 기록: data.starClaims = { "<챕터>": ["9", "18", "all"] } · 보상: 소환권(story_gacha.tickets) + 골드(_wallet_add)
create or replace function public._star_milestones() returns jsonb language sql immutable as $$
  select '[{"key":"9","need":9,"tickets":1,"gold":3000},{"key":"18","need":18,"tickets":1,"gold":5000},{"key":"all","need":null,"tickets":2,"gold":10000}]'::jsonb $$;$vr_statement$;
  execute $vr_statement$-- 챕터 별 현황: { total, max, milestones:[{key, need, tickets, gold, claimed, ready}] }
create or replace function public._star_chapter(d jsonb, p_chapter int) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare mx int; tot int; cl jsonb := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb); got jsonb := coalesce(d->'starClaims'->(p_chapter::text), '[]'::jsonb); ms jsonb := '[]'::jsonb; m jsonb; need int;
begin
  select 3 * count(*) into mx from story_phase_config where chapter = p_chapter and (p_chapter >= 1 or phase = 4);
  select coalesce(sum(least(3, greatest(0, (s.value)::int))), 0) into tot
    from jsonb_each_text(case when jsonb_typeof(d->'stars'->(p_chapter::text)) = 'object' then d->'stars'->(p_chapter::text) else '{}'::jsonb end) s
    where s.key ~ '^\d+$' and cl @> to_jsonb(s.key::int)
      and exists (select 1 from story_phase_config c where c.chapter = p_chapter and c.phase = s.key::int and (p_chapter >= 1 or c.phase = 4));
  tot := least(tot, mx);
  for m in select * from jsonb_array_elements(_star_milestones()) loop
    need := coalesce((m->>'need')::int, mx);
    if mx = 0 or need > mx or (m->>'key' <> 'all' and need >= mx) then continue; end if;   -- 최대보다 크거나 '전부'와 같으면 생략
    ms := ms || (m || jsonb_build_object('need', need, 'claimed', got @> to_jsonb(m->>'key'), 'ready', tot >= need));
  end loop;
  return jsonb_build_object('chapter', p_chapter, 'total', tot, 'max', mx, 'milestones', ms);
end $$;$vr_statement$;
  execute $vr_statement$-- 전체 챕터 현황 (지도 표시용)
create or replace function public.story_star_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); d jsonb; r jsonb := '[]'::jsonb; c int;
begin
  if me is null then raise exception 'login required'; end if;
  select data into d from story_progress where user_id = me; d := coalesce(d, '{}'::jsonb);
  for c in select distinct chapter from story_phase_config order by 1 loop r := r || _star_chapter(d, c); end loop;
  return r;
end $$;$vr_statement$;
  execute $vr_statement$-- 받기: 서버가 별을 다시 합산 · 한 번만
create or replace function public.story_star_claim(p_chapter int, p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); d jsonb; st jsonb; m jsonb; got jsonb; t int; w jsonb;
begin
  if me is null then raise exception 'login required'; end if;
  d := _story_lock(me);
  st := _star_chapter(d, p_chapter);
  select x into m from jsonb_array_elements(st->'milestones') x where x->>'key' = p_key;
  if m is null then raise exception 'invalid milestone'; end if;
  if (m->>'claimed')::boolean then raise exception 'already claimed'; end if;
  if not (m->>'ready')::boolean then raise exception 'not enough stars'; end if;
  got := coalesce(d->'starClaims'->(p_chapter::text), '[]'::jsonb) || to_jsonb(p_key);
  if jsonb_typeof(d->'starClaims') is distinct from 'object' then d := jsonb_set(d, '{starClaims}', '{}'::jsonb); end if;
  d := _story_save(me, jsonb_set(d, array['starClaims', p_chapter::text], got));
  insert into story_gacha (user_id, last_draw) values (me, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = tickets + (m->>'tickets')::int, updated_at = now() where user_id = me returning tickets into t;
  w := _wallet_add(me, jsonb_build_object('gold', (m->>'gold')::int), 'star_reward');
  return jsonb_build_object('ok', true, 'tickets', t, 'wallet', w, 'gave', jsonb_build_object('tickets', (m->>'tickets')::int, 'gold', (m->>'gold')::int), 'status', _star_chapter(d, p_chapter));
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._star_milestones(), public._star_chapter(jsonb, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_star_status(), public.story_star_claim(int, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_star_status(), public.story_star_claim(int, text) to authenticated;$vr_statement$;
  execute $vr_statement$select 'story_star_rewards ok' as result;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: camp.sql =====
-- ===== 훈련소 1단계 (인재를 넣어 두면 시간이 지나며 EXP 가 쌓임) =====
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (테이블·데이터 삭제 없음)
-- 선행: phaseE_1.sql(_wallet_add) · phaseE_2.sql(_player_sync) · gem.sql(_gem_spend) · story_levels.sql / story_merge.sql(_story_gain · _story_cap · 인재 uid)
-- 규칙
--  * 칸 5개: 1칸 플레이어 Lv10 무료 · 2칸 Lv20 골드 2만 · 3칸 Lv35 골드 5만 · 4칸 Lv50 심연석 300 · 5칸 Lv70 심연석 800
--  * EXP: 칸 하나에 시간당 20 + 플레이어 레벨 × 1.5 (받을 때 레벨 기준). 마지막으로 받은 뒤 최대 24시간까지만 쌓임
--  * 레벨 상한: min(등급 최대 레벨(EX 포함), 플레이어 레벨 − 5). 상한에 닿으면 더 안 쌓임
--  * 시간은 서버 now() 만 사용. 훈련 중인 인재도 덱·스토리·PvP 사용 가능
--  * 훈련 중인 인재는 거래 등록·분해·합성 재료로 못 씀 (story_progress 에서 빠지려 하면 거부하는 트리거)

-- 1) 테이블 (행이 있으면 그 칸은 열린 것)
create table if not exists public.camp_slots (
  user_id  uuid not null references auth.users(id) on delete cascade,
  slot     int  not null check (slot between 1 and 5),
  card_uid text,
  last_at  timestamptz,
  opened_at timestamptz not null default now(),
  primary key (user_id, slot));$vr_statement$;
  execute $vr_statement$create unique index if not exists camp_slots_card on public.camp_slots (user_id, card_uid) where card_uid is not null;$vr_statement$;
  execute $vr_statement$alter table public.camp_slots enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.camp_slots from anon, authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists camp_slots_own on public.camp_slots;$vr_statement$;
  execute $vr_statement$create policy camp_slots_own on public.camp_slots for select using (user_id = auth.uid());$vr_statement$;
  execute $vr_statement$grant select on public.camp_slots to authenticated;$vr_statement$;
  execute $vr_statement$-- 2) 수치
create or replace function public._camp_need_level(s int) returns int language sql immutable as $$ select case s when 1 then 10 when 2 then 20 when 3 then 35 when 4 then 50 when 5 then 70 end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_cost(s int) returns jsonb language sql immutable as $$
  select case s when 1 then '{}'::jsonb when 2 then '{"gold":20000}'::jsonb when 3 then '{"gold":50000}'::jsonb when 4 then '{"gem":300}'::jsonb when 5 then '{"gem":800}'::jsonb end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_rate(plv int) returns numeric language sql immutable as $$ select 20 + 1.5 * greatest(plv, 1) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_max_hours() returns int language sql immutable as $$ select 24 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_cap(g text, ex int, plv int) returns int language sql immutable as $$ select least(_story_cap(g, ex), plv - 5) $$;$vr_statement$;
  execute $vr_statement$-- 3) 도우미
create or replace function public._camp_plv(p_uid uuid) returns int language plpgsql security definer set search_path = public as $$
declare lv int; begin select (_player_sync(p_uid)).level into lv; return coalesce(lv, 1); end $$;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (8, '410cdea919d7fef2dc1c1430be099965278672866ca01148fb8f0da2240951aa', '88b786d177f12a46ca801845bbeb154575ba785421933e5efbc0d107939c19ad', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '08_install.sql: 완료 또는 이미 완료 (8/12)' as result;
