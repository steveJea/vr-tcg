-- ===== 장비 PR6: 증표 제작·강화 + 조각 획득처 =====
-- 선행: gear_v1.sql · gear_drops.sql (story_sweep · 토벌 트리거). 여러 번 실행해도 안전
-- · 제작 50 → +1 30 → +2 50 → +3 80 → +4 120 → +5 200 = 530 (sigil_cost, v4 Page)
-- · 획득처 (v4 Page "콘텐츠별 획득처"):
--   - 스토리 보스전 소탕: 그 인재 챕터 보스 페이즈 소탕 1회당 15%로 1개, 인재별 하루 최대 3개 (sigil_story_boss · sigil_drop_config)
--   - 조직 토벌 주간 순위 상자: 2~6개 선택 조각 (gear_raid_rewards.sigil_frags) → 우편, 받을 때 인재 선택 (raid_select 가능한 인재만)
--   - 범용 교환: 아무 조각 3개 → 원하는 인재 1개 (exchange 가능한 인재만)
--   - 조직 상점·PvP 상점·이벤트 조각은 상점 PR 에서
-- · 조절값 표는 다시 실행해도 덮어쓰지 않음

-- 1) 표 -----------------------------------------------------------------------
create table if not exists public.sigil_story_boss (     -- 인재 → 그 인재 챕터 (보스 페이즈 소탕에서 조각). 임시값
  card_id text primary key references public.sigil_defs(card_id), chapter int not null
);
insert into public.sigil_story_boss (card_id, chapter) values ('10325', 4), ('10118', 7), ('10415', 5) on conflict (card_id) do nothing;
create table if not exists public.sigil_drop_config (key text primary key, v numeric not null);
insert into public.sigil_drop_config (key, v) values ('story_boss_pct', 15), ('story_boss_daily', 3), ('exchange_rate', 3) on conflict (key) do nothing;
create table if not exists public.sigil_daily (
  user_id uuid not null references auth.users(id) on delete cascade, card_id text not null, day date not null, n int not null default 0,
  primary key (user_id, card_id, day)
);
do $$ declare t text; begin
  foreach t in array array['sigil_story_boss', 'sigil_drop_config'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;
alter table public.sigil_daily enable row level security;
revoke all on public.sigil_daily from public, anon, authenticated;
grant select on public.sigil_daily to authenticated;
drop policy if exists sigil_daily_own on public.sigil_daily;
create policy sigil_daily_own on public.sigil_daily for select to authenticated using (user_id = auth.uid());

-- 2) 내부 ---------------------------------------------------------------------
create or replace function public._sigil_add(p_uid uuid, p_card text, p_n int, p_source text) returns int
language plpgsql security definer set search_path = public as $$
declare f int;
begin
  if p_n is null or p_n <= 0 then return null; end if;
  insert into player_sigils (user_id, card_id, plus, frags) values (p_uid, p_card, null, p_n)
    on conflict (user_id, card_id) do update set frags = player_sigils.frags + p_n returning frags into f;
  insert into gear_drop_log (user_id, source, def_id, kind) select p_uid, p_source, p_card, 'sigil' from generate_series(1, least(p_n, 20));
  return f;
end $$;

-- 스토리 보스 소탕 1회: 그 챕터 인재마다 확률 굴림, 하루 상한
create or replace function public._sigil_story_roll(p_uid uuid, p_chapter int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b record; pct numeric := (select v from sigil_drop_config where key = 'story_boss_pct'); cap int := (select v from sigil_drop_config where key = 'story_boss_daily');
  dday date := (now() at time zone 'Asia/Seoul')::date; n int; got jsonb := '[]'::jsonb;
begin
  for b in select s.card_id from sigil_story_boss s join sigil_sources src on src.card_id = s.card_id and src.source = 'story_boss' where s.chapter = p_chapter loop
    select coalesce((select d.n from sigil_daily d where d.user_id = p_uid and d.card_id = b.card_id and d.day = dday), 0) into n;
    if n >= cap or random() * 100 >= pct then continue; end if;
    insert into sigil_daily (user_id, card_id, day, n) values (p_uid, b.card_id, dday, 1) on conflict (user_id, card_id, day) do update set n = sigil_daily.n + 1;
    perform _sigil_add(p_uid, b.card_id, 1, 'story_boss');
    got := got || to_jsonb(b.card_id);
  end loop;
  return got;
end $$;

-- 토벌 처치·순위 트리거 (gear_drops.sql 것 + 순위 상자의 증표 조각)
create or replace function public._gear_raid_claim_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare rw gear_raid_rewards; st int; rk int; mid bigint;
begin
  if new.ref like 'raidst:%' then
    st := split_part(new.ref, ':', 3)::int;
    select * into rw from gear_raid_rewards where kind = 'clear_box' and st between stage_from and stage_to order by stage_from desc limit 1;
    if rw.id is not null then perform _gear_box_mail(new.user_id, rw, 'raid_clear'); end if;
  elsif new.ref like 'raidrk:%' then
    rk := nullif(new.reward->>'rank', '')::int;
    if rk is null then return new; end if;
    select * into rw from gear_raid_rewards where kind = 'rank_box' and rk between rank_from and rank_to order by rank_from desc limit 1;
    if rw.id is not null then
      perform _gear_box_mail(new.user_id, rw, 'raid_rank');
      if rw.sigil_frags > 0 then
        insert into player_mail (user_id, kind, payload, reason, expires_at)
          values (new.user_id, 'sigil_frag', jsonb_build_object('n', rw.sigil_frags, 'pick', 'raid_select'), 'raid_rank', now() + interval '14 days') returning id into mid;
        insert into gear_drop_log (user_id, source, def_id, mail_id, kind) values (new.user_id, 'raid_rank', 'sigilpick', mid, 'sigil');
      end if;
    end if;
  end if;
  return new;
end $$;

revoke all on function public._sigil_add(uuid, text, int, text), public._sigil_story_roll(uuid, int), public._gear_raid_claim_trg() from public, anon, authenticated;

-- 3) 스토리 소탕: gear_drops.sql 의 story_sweep 그대로 + 보스 페이즈면 증표 조각 ------------------
create or replace function public.story_sweep(p_chapter int, p_phase int, p_runs int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; cost int; xp int; up jsonb; dr jsonb;
  tot jsonb := '{"gold":0,"blood":0,"shard":0,"soul":0}'::jsonb; runs jsonb := '[]'::jsonb; k text; w jsonb; gear jsonb := '[]'::jsonb; g jsonb; sig jsonb := '[]'::jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_runs is null or p_runs not in (1, 5, 10) then raise exception 'invalid runs'; end if;
  if not _player_unlocked(uid, 'sweep') then raise exception 'sweep locked (player Lv%)', _player_unlock_level('sweep'); end if;
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if not found then raise exception 'unknown phase'; end if;
  select data into d from story_progress where user_id = uid for update;
  if not (coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase)) then raise exception 'not cleared'; end if;
  if _gear_bag_full(uid) then raise exception 'bag full'; end if;   -- 장비 PR4: 가방이 꽉 차면 소탕 불가
  cost := _stamina_cost(p_chapter, p_phase);
  perform _player_stamina_add(uid, -cost * p_runs);   -- 부족하면 'not enough stamina' (전체 롤백)
  for i in 1..p_runs loop
    dr := _story_drop_calc(p_chapter, coalesce(cfg.type, 'normal'), false, cost, random()::numeric, random()::numeric);
    runs := runs || dr;
    g := _gear_try_drop(uid, p_chapter, null, 'story_sweep'); if g is not null then gear := gear || jsonb_build_array(g); end if;
    if cfg.type = 'boss' then sig := sig || _sigil_story_roll(uid, p_chapter); end if;   -- 장비 PR6: 증표 조각
    foreach k in array array['gold','blood','shard','soul'] loop
      tot := jsonb_set(tot, array[k], to_jsonb((tot->>k)::int + coalesce((dr->>k)::int, 0)));
    end loop;
  end loop;
  w := _wallet_add(uid, tot, 'story_sweep');
  xp := cost * p_runs * _player_xp_per_stamina();
  up := _player_add_xp(uid, xp, true);
  -- 조직 의뢰 진행 (guild2.sql): 소탕 1회 = 페이즈 1 · 행동력 · 보스
  if to_regprocedure('public._guild_event(uuid,text,integer)') is not null then
    perform _guild_event(uid, 'phase', p_runs); perform _guild_event(uid, 'stamina', cost * p_runs);
    if cfg.type = 'boss' then perform _guild_event(uid, 'boss', p_runs); end if;
  end if;
  return jsonb_build_object('ok', true, 'chapter', p_chapter, 'phase', p_phase, 'runs', p_runs, 'stamina', cost * p_runs,
    'drops', tot, 'per_run', runs, 'wallet', w, 'gear', gear, 'sigil', sig,
    'player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'));
end $$;

revoke all on function public.story_sweep(int, int, int) from public, anon;
grant execute on function public.story_sweep(int, int, int) to authenticated;

-- 4) 공개 RPC -----------------------------------------------------------------
-- 제작 (+0): 그 인재를 가지고 있어야 함
create or replace function public.sigil_craft(p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s player_sigils; need int := (select frags from sigil_cost where plus = 0);
begin
  if uid is null then raise exception 'login required'; end if;
  if not exists (select 1 from sigil_defs where card_id = p_card) then return jsonb_build_object('ok', false, 'reason', 'no sigil'); end if;
  if not exists (select 1 from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o
                 where sp.user_id = uid and o->>'id' = p_card) then return jsonb_build_object('ok', false, 'reason', 'card not owned'); end if;
  select * into s from player_sigils where user_id = uid and card_id = p_card for update;
  if s.plus is not null then return jsonb_build_object('ok', false, 'reason', 'already crafted'); end if;
  if coalesce(s.frags, 0) < need then return jsonb_build_object('ok', false, 'reason', 'not enough frags', 'need', need, 'have', coalesce(s.frags, 0)); end if;
  update player_sigils set plus = 0, frags = frags - need where user_id = uid and card_id = p_card;
  return jsonb_build_object('ok', true, 'card', p_card, 'plus', 0, 'frags', s.frags - need);
end $$;

-- 강화 (+1 씩)
create or replace function public.sigil_enhance(p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s player_sigils; need int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into s from player_sigils where user_id = uid and card_id = p_card for update;
  if s.plus is null then return jsonb_build_object('ok', false, 'reason', 'not crafted'); end if;
  if s.plus >= 5 then return jsonb_build_object('ok', false, 'reason', 'max plus'); end if;
  need := (select frags from sigil_cost where plus = s.plus + 1);
  if s.frags < need then return jsonb_build_object('ok', false, 'reason', 'not enough frags', 'need', need, 'have', s.frags); end if;
  update player_sigils set plus = plus + 1, frags = frags - need where user_id = uid and card_id = p_card;
  return jsonb_build_object('ok', true, 'card', p_card, 'plus', s.plus + 1, 'frags', s.frags - need);
end $$;

-- 범용 교환: p_from 조각 (rate × p_n) → p_to 조각 p_n
create or replace function public.sigil_exchange(p_from text, p_to text, p_n int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rate int := (select v from sigil_drop_config where key = 'exchange_rate'); f int;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_n is null or p_n < 1 or p_n > 200 or p_from = p_to then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  if not exists (select 1 from sigil_sources where card_id = p_to and source = 'exchange') then return jsonb_build_object('ok', false, 'reason', 'no exchange'); end if;
  update player_sigils set frags = frags - rate * p_n where user_id = uid and card_id = p_from and frags >= rate * p_n returning frags into f;
  if f is null then return jsonb_build_object('ok', false, 'reason', 'not enough frags', 'need', rate * p_n); end if;
  insert into player_sigils (user_id, card_id, plus, frags) values (uid, p_to, null, p_n)
    on conflict (user_id, card_id) do update set frags = player_sigils.frags + p_n;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'n', p_n, 'spent', rate * p_n);
end $$;

-- 선택 조각 우편 받기 (토벌 순위): 고를 수 있는 인재만
create or replace function public.sigil_mail_claim(p_id bigint, p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; n int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() and kind = 'sigil_frag' for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if not exists (select 1 from sigil_sources where card_id = p_card and source = coalesce(ml.payload->>'pick', 'raid_select')) then return jsonb_build_object('ok', false, 'reason', 'not selectable'); end if;
  n := (ml.payload->>'n')::int;
  insert into player_sigils (user_id, card_id, plus, frags) values (uid, p_card, null, n)
    on conflict (user_id, card_id) do update set frags = player_sigils.frags + n;
  update player_mail set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'card', p_card, 'n', n);
end $$;

revoke all on function public.sigil_craft(text), public.sigil_enhance(text), public.sigil_exchange(text, text, int), public.sigil_mail_claim(bigint, text) from public, anon;
grant execute on function public.sigil_craft(text), public.sigil_enhance(text), public.sigil_exchange(text, text, int), public.sigil_mail_claim(bigint, text) to authenticated;
