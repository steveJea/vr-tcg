-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _gear_raid_claim_trg, mail_claim, story_sweep 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 장비 PR4: 드롭 (소탕·탑·조직 토벌) + 토벌 상자 + 우편함 =====
-- 선행: gear_v1.sql · guild2.sql · guild3.sql · tower_v2.sql · phaseE_5.sql. 여러 번 실행해도 안전
-- · 등급: gear_tier_gate (챕터·층 대역, 희귀는 챕터 11부터 2%, 일반 콘텐츠 최대 5 영웅). 전설·심연은 _gear_grant 가 이벤트 외 거부
-- · 확률: gear_drop_rate (조절값, 다시 실행해도 덮어쓰지 않음)
-- · 가방이 꽉 차면: 스토리 소탕·탑 시작을 막음('bag full'). 토벌 드롭·상자는 우편함으로
-- · 부옵션은 드롭 순간에 굴림 (우편으로 가도 그 값 그대로)
-- · 획득 기록 gear_drop_log → 결과 화면이 gear_drops_take() 로 가져가 보여줌

-- 1) 표 -----------------------------------------------------------------------
create table if not exists public.gear_drop_rate (
  source text primary key check (source in ('story_sweep', 'tower', 'raid')),
  pct numeric not null check (pct between 0 and 100)
);
insert into public.gear_drop_rate (source, pct) values ('story_sweep', 30), ('tower', 35), ('raid', 100) on conflict (source) do nothing;

create table if not exists public.gear_drop_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null, def_id text not null, gear_id bigint, mail_id bigint, kind text not null default 'gear',
  created_at timestamptz not null default now(), seen boolean not null default false
);
create index if not exists gear_drop_log_unseen on public.gear_drop_log (user_id) where not seen;

alter table public.gear_drop_rate enable row level security;
revoke all on public.gear_drop_rate from public, anon, authenticated;
grant select on public.gear_drop_rate to authenticated;
drop policy if exists gear_drop_rate_read on public.gear_drop_rate;
create policy gear_drop_rate_read on public.gear_drop_rate for select to authenticated using (true);
alter table public.gear_drop_log enable row level security;
revoke all on public.gear_drop_log from public, anon, authenticated;
grant select on public.gear_drop_log to authenticated;
drop policy if exists gear_drop_log_own on public.gear_drop_log;
create policy gear_drop_log_own on public.gear_drop_log for select to authenticated using (user_id = auth.uid());

-- 우편 종류에 'box'(토벌 상자) 추가
alter table public.player_mail drop constraint if exists player_mail_kind_check;
alter table public.player_mail add constraint player_mail_kind_check check (kind in ('gear', 'box', 'sigil_frag', 'gold', 'gem'));

-- 2) 지급 (부옵션은 지금 굴림. 꽉 차면 p_to_mail 이면 우편, 아니면 'bag full') -------------
create or replace function public._gear_grant(p_uid uuid, p_def text, p_source text, p_to_mail boolean default false, p_event text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d gear_defs; m player_gear_meta; n int; gid bigint; mid bigint; o jsonb;
begin
  if p_uid is null then raise exception 'login required'; end if;
  select * into d from gear_defs where id = p_def;
  if not found then raise exception 'unknown gear'; end if;
  if d.tier > 5 or d.event_only then
    if p_source <> 'event' or p_event is null or not exists (
      select 1 from gear_event_grants e where e.event_key = p_event and e.def_id = p_def and now() between e.starts_at and e.ends_at)
    then raise exception 'tier above hero is event only'; end if;
  end if;
  o := _gear_roll_opts(p_def);
  m := _gear_meta(p_uid);
  select count(*) into n from player_gear where user_id = p_uid;
  if n >= m.slots then
    if not p_to_mail then raise exception 'bag full'; end if;
    insert into player_mail (user_id, kind, payload, reason) values (p_uid, 'gear', jsonb_build_object('def_id', p_def, 'source', p_source, 'event', p_event, 'opts', o), p_source)
      returning id into mid;
    return jsonb_build_object('ok', true, 'mail', true, 'mail_id', mid, 'def_id', p_def);
  end if;
  insert into player_gear (user_id, def_id, opts, source, locked) values (p_uid, p_def, o, p_source, d.tier >= 6) returning id into gid;
  return jsonb_build_object('ok', true, 'gear_id', gid, 'def_id', p_def);
end $$;

-- 등급 하나 → 장비 하나 (슬롯 지정 가능) + 기록. 영웅(5) 초과는 거부
create or replace function public._gear_give_tier(p_uid uuid, p_tier int, p_slot text, p_source text, p_to_mail boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare did text; r jsonb;
begin
  if p_tier is null or p_tier < 1 or p_tier > 5 then raise exception 'drop tier out of range'; end if;
  select id into did from gear_defs where tier = p_tier and not event_only and (p_slot is null or slot = p_slot) order by random() limit 1;
  if did is null then return null; end if;
  r := _gear_grant(p_uid, did, p_source, p_to_mail, null);
  insert into gear_drop_log (user_id, source, def_id, gear_id, mail_id) values (p_uid, p_source, did, (r->>'gear_id')::bigint, (r->>'mail_id')::bigint);
  return r;
end $$;

-- 소탕·탑: 확률 굴림 후 챕터/층 대역 등급으로 1개 (가방이 중간에 차면 우편)
create or replace function public._gear_try_drop(p_uid uuid, p_chapter int, p_floor int, p_source text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pct numeric;
begin
  select r.pct into pct from gear_drop_rate r where r.source = p_source;
  if random() * 100 >= coalesce(pct, 0) then return null; end if;
  return _gear_give_tier(p_uid, _gear_roll_tier(p_chapter, p_floor, 'normal'), null, p_source, true);
end $$;

create or replace function public._gear_bag_full(p_uid uuid) returns boolean language sql security definer set search_path = public as $$
  select (select count(*) from player_gear where user_id = p_uid) >= (_gear_meta(p_uid)).slots $$;

-- 토벌 상자 → 우편 (열 때 슬롯 선택)
create or replace function public._gear_box_mail(p_uid uuid, rw gear_raid_rewards, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare mid bigint;
begin
  for i in 1 .. greatest(rw.qty, 1) loop
    insert into player_mail (user_id, kind, payload, reason, expires_at)
      values (p_uid, 'box', jsonb_build_object('tier', rw.tier, 'up_tier', rw.up_tier, 'up_pct', rw.up_pct), p_reason, now() + interval '14 days') returning id into mid;
    insert into gear_drop_log (user_id, source, def_id, mail_id, kind) values (p_uid, p_reason, 'box_' || rw.tier, mid, 'box');
  end loop;
end $$;

revoke all on function public._gear_grant(uuid, text, text, boolean, text), public._gear_give_tier(uuid, int, text, text, boolean),
  public._gear_try_drop(uuid, int, int, text), public._gear_bag_full(uuid), public._gear_box_mail(uuid, gear_raid_rewards, text) from public, anon, authenticated;

-- 3) 탑: 시작 막기 + 층 클리어마다 드롭 (tower_progress 트리거, 기존 함수는 그대로) ----------
create or replace function public._gear_tower_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare n int; fl int;
begin
  if new.battle is not null and old.battle is null and _gear_bag_full(new.user_id) then raise exception 'bag full'; end if;
  n := new.clears - old.clears;
  if n > 0 and n <= 50 then
    fl := greatest(new.best_floor, coalesce((old.battle->>'floor')::int, 0), 1);
    for i in 1 .. n loop perform _gear_try_drop(new.user_id, null, fl, 'tower'); end loop;
  end if;
  return new;
end $$;
revoke all on function public._gear_tower_trg() from public, anon, authenticated;
drop trigger if exists gear_tower_drop on public.tower_progress;
create trigger gear_tower_drop before update on public.tower_progress for each row execute function public._gear_tower_trg();

-- 4) 조직 토벌: 도전(직접·소탕) 끝날 때 드롭, 처치·순위 보상 받을 때 상자 -------------------
create or replace function public._gear_raid_attempt_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare rw gear_raid_rewards; t int;
begin
  if old.finished_at is null and new.finished_at is not null and coalesce(new.damage, 0) > 0 and not coalesce(new.voided, false) then
    if random() * 100 >= coalesce((select pct from gear_drop_rate where source = 'raid'), 0) then return new; end if;
    select * into rw from gear_raid_rewards where kind = 'drop' and new.stage between stage_from and stage_to order by stage_from desc limit 1;
    if rw.id is null then return new; end if;
    t := rw.tier; if rw.up_tier is not null and random() * 100 < rw.up_pct then t := rw.up_tier; end if;
    perform _gear_give_tier(new.user_id, least(t, 5), null, 'raid', true);
  end if;
  return new;
end $$;
revoke all on function public._gear_raid_attempt_trg() from public, anon, authenticated;
drop trigger if exists gear_raid_drop on public.guild_raid_attempts;
create trigger gear_raid_drop after update on public.guild_raid_attempts for each row execute function public._gear_raid_attempt_trg();

create or replace function public._gear_raid_claim_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare rw gear_raid_rewards; st int; rk int;
begin
  if new.ref like 'raidst:%' then
    st := split_part(new.ref, ':', 3)::int;
    select * into rw from gear_raid_rewards where kind = 'clear_box' and st between stage_from and stage_to order by stage_from desc limit 1;
    if rw.id is not null then perform _gear_box_mail(new.user_id, rw, 'raid_clear'); end if;
  elsif new.ref like 'raidrk:%' then
    rk := nullif(new.reward->>'rank', '')::int;
    if rk is null then return new; end if;
    select * into rw from gear_raid_rewards where kind = 'rank_box' and rk between rank_from and rank_to order by rank_from desc limit 1;
    if rw.id is not null then perform _gear_box_mail(new.user_id, rw, 'raid_rank'); end if;
  end if;
  return new;
end $$;
revoke all on function public._gear_raid_claim_trg() from public, anon, authenticated;
drop trigger if exists gear_raid_box on public.guild_claims;
create trigger gear_raid_box after insert on public.guild_claims for each row execute function public._gear_raid_claim_trg();

-- 5) 스토리 소탕: guild2.sql 의 story_sweep 그대로 + 가방 검사(행동력 쓰기 전) + 회차마다 드롭 ---------
create or replace function public.story_sweep(p_chapter int, p_phase int, p_runs int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; cost int; xp int; up jsonb; dr jsonb;
  tot jsonb := '{"gold":0,"blood":0,"shard":0,"soul":0}'::jsonb; runs jsonb := '[]'::jsonb; k text; w jsonb; gear jsonb := '[]'::jsonb; g jsonb;
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
    'drops', tot, 'per_run', runs, 'wallet', w, 'gear', gear,
    'player', _player_json(uid) || jsonb_build_object('gained_xp', xp, 'levelups', up->'levelups', 'levelup_gold', up->'gold'));
end $$;

revoke all on function public.story_sweep(int, int, int) from public, anon;
grant execute on function public.story_sweep(int, int, int) to authenticated;

-- 6) 공개 RPC ------------------------------------------------------------------
-- 결과 화면용: 아직 안 본 획득 기록 가져오기 (가져가면 본 것으로)
create or replace function public.gear_drops_take() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  with x as (update gear_drop_log set seen = true where user_id = uid and not seen and created_at > now() - interval '1 day' returning *)
  select coalesce(jsonb_agg(jsonb_build_object('source', x.source, 'def_id', x.def_id, 'gear_id', x.gear_id, 'mail', x.mail_id is not null, 'kind', x.kind,
           'opts', g.opts, 'tier', coalesce(d.tier, nullif(split_part(x.def_id, '_', 2), '')::int)) order by x.id), '[]'::jsonb) into r
    from x left join player_gear g on g.id = x.gear_id left join gear_defs d on d.id = x.def_id;
  return r;
end $$;

-- 우편 받기: 장비는 드롭 때 굴린 부옵션 그대로. 상자는 gear_box_open 으로
create or replace function public.mail_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; d gear_defs; gid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if ml.kind <> 'gear' then return jsonb_build_object('ok', false, 'reason', 'unsupported'); end if;
  if _gear_bag_full(uid) then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  select * into d from gear_defs where id = ml.payload->>'def_id';
  if d.tier > 5 and coalesce(ml.payload->>'source', '') <> 'event' then return jsonb_build_object('ok', false, 'reason', 'event only'); end if;
  insert into player_gear (user_id, def_id, opts, source, locked)
    values (uid, d.id, coalesce(ml.payload->'opts', _gear_roll_opts(d.id)), 'mail:' || ml.reason, d.tier >= 6) returning id into gid;
  update player_mail set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'gear_id', gid, 'def_id', d.id);
end $$;

-- 토벌 상자 열기: 슬롯 선택 → 등급(가끔 한 단계 위, 최대 영웅) 장비 1개
create or replace function public.gear_box_open(p_id bigint, p_slot text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; t int; r jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_slot not in ('weapon', 'armor', 'acc') then raise exception 'invalid slot'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found or ml.kind <> 'box' then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if _gear_bag_full(uid) then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  t := (ml.payload->>'tier')::int;
  if (ml.payload->>'up_tier') is not null and random() * 100 < coalesce((ml.payload->>'up_pct')::numeric, 0) then t := (ml.payload->>'up_tier')::int; end if;
  r := _gear_give_tier(uid, least(t, 5), p_slot, 'box:' || ml.reason, false);
  update gear_drop_log set seen = true where user_id = uid and gear_id = (r->>'gear_id')::bigint;
  update player_mail set claimed_at = now() where id = p_id;
  return r || jsonb_build_object('tier', least(t, 5));
end $$;

revoke all on function public.gear_drops_take(), public.mail_claim(bigint), public.gear_box_open(bigint, text) from public, anon;
grant execute on function public.gear_drops_take(), public.mail_claim(bigint), public.gear_box_open(bigint, text) to authenticated;

-- 확인: select source, count(*) from public.gear_drop_log group by 1;
