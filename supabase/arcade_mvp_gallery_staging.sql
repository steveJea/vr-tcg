-- STAGING ONLY. Run in the staging SQL Editor as one script. Safe to run more than once.
-- Arcade MVP -> 도감(gallery). The MVP comes ONLY from the server re-run verdict that
-- arcade-verify-v5 hands to arcade_engine_settle_v5 (never from the browser).
--   Rule: verified WIN only (forfeit/expired/lose/draw never count). MVP = the player's own
--   card that dealt the most damage in the server re-run (engine fallback: my highest-grade
--   field/hand card). Only that one card. Enemy cards never count.
--   Only cards in reward_card_catalog (no NPC). One registration per arcade session
--   (arcade_gallery_v5.session_id primary key), so retries/status replays add nothing.
-- 1) _arcade_gallery_v5: registers the MVP, returns {gallery:{card_id,new,mvp_count}} for the receipt.
-- 2) _arcade_close_v5 patched in place (pg_get_functiondef + replace) to call it for verified results.
-- 3) _gallery_have counts arcade MVP cards too (gallery % milestones / 'gallery_n' achievement,
--    rewards themselves unchanged, each milestone still claimable once).
-- 4) Backfill: past verified arcade wins' MVPs (once per session).
-- No engine_hash change, no Edge Function redeploy. system_identifier 7703759698107299042.
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging only (7703759698107299042)';
  end if;
  if to_regclass('public.arcade_records_v5') is null or to_regclass('public.gallery') is null
     or to_regclass('public.reward_card_catalog') is null or to_regclass('public.battle_acquisitions_v2') is null then
    raise exception 'STOP: arcade v5 / gallery / phase2 tables required';
  end if;
end $guard$;

create table if not exists public.arcade_gallery_v5 (
  session_id bigint primary key references public.arcade_sessions_v5(id),
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null references public.reward_card_catalog(card_id),
  created_at timestamptz not null default now());
create index if not exists arcade_gallery_user_v5 on public.arcade_gallery_v5(user_id, card_id);
alter table public.arcade_gallery_v5 enable row level security;
revoke all on public.arcade_gallery_v5 from public, anon, authenticated;

create or replace function public._arcade_gallery_v5(p_sid bigint, p_uid uuid, r jsonb) returns jsonb
language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare cid text; got text; new_ boolean; mvp_ int;
begin
  if r is null or r->>'result' is distinct from 'win' or nullif(r->>'mvp_id', '') is null then return '{}'::jsonb; end if;
  select c.card_id into cid from public.reward_card_catalog c where c.card_id = r->>'mvp_id';
  if cid is null then return '{}'::jsonb; end if;
  insert into public.arcade_gallery_v5(session_id, user_id, card_id) values (p_sid, p_uid, cid)
    on conflict (session_id) do nothing returning card_id into got;
  if got is null then return '{}'::jsonb; end if;
  insert into public.gallery as g (user_id, card_id, count, mvp_count, first_at, last_at)
    values (p_uid, cid, 1, 1, now(), now())
  on conflict (user_id, card_id) do update set count = g.count + 1, mvp_count = g.mvp_count + 1, last_at = now()
  returning (xmax = 0), g.mvp_count into new_, mvp_;
  return jsonb_build_object('gallery', jsonb_build_object('card_id', cid, 'new', new_, 'mvp_count', mvp_));
end $$;
revoke all on function public._arcade_gallery_v5(bigint, uuid, jsonb) from public, anon, authenticated;

do $patch$
declare f oid := to_regprocedure('public._arcade_close_v5(public.arcade_sessions_v5,jsonb,jsonb)'); def_ text;
  old_ text := $q$receipt:=r||jsonb_build_object('session_id',s.id::text,'verified',verified_);$q$;
  new_ text := $q$receipt:=r||jsonb_build_object('session_id',s.id::text,'verified',verified_);
 if verified_ then receipt:=receipt||public._arcade_gallery_v5(s.id,s.user_id,r); end if;$q$;
begin
  if f is null then raise exception 'STOP: _arcade_close_v5 missing'; end if;
  def_ := pg_get_functiondef(f);
  if position('_arcade_gallery_v5' in def_) > 0 then return; end if;
  if position(old_ in def_) = 0 then raise exception 'STOP: _arcade_close_v5 body changed, not patched'; end if;
  execute replace(def_, old_, new_);
end $patch$;
revoke all on function public._arcade_close_v5(public.arcade_sessions_v5, jsonb, jsonb) from public, anon, authenticated;

do $have$
begin
  if position('battle_acquisitions_v2' in pg_get_functiondef(to_regprocedure('public._gallery_have(uuid)'))) = 0 then
    raise exception 'STOP: _gallery_have body changed, not replaced';
  end if;
end $have$;
create or replace function public._gallery_have(p_uid uuid) returns int language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select count(*)::int from public.reward_card_catalog c where c.card_id in(
 select card_id from public.verified_game_events where user_id=p_uid and event_kind='card_acquired'
 union select card_id from public.battle_acquisitions_v2 where user_id=p_uid
 union select card_id from public.arcade_gallery_v5 where user_id=p_uid)
$$;
revoke all on function public._gallery_have(uuid) from public, anon, authenticated;

-- Backfill past verified wins (each session once; reruns add nothing).
with ins as (
  insert into public.arcade_gallery_v5(session_id, user_id, card_id, created_at)
  select r.session_id, r.user_id, c.card_id, r.created_at
  from public.arcade_records_v5 r join public.reward_card_catalog c on c.card_id = r.mvp_id
  where r.verified and r.result = 'win' and exists (select 1 from auth.users u where u.id = r.user_id)
  on conflict (session_id) do nothing
  returning user_id, card_id, created_at),
agg as (select user_id, card_id, count(*)::int n, min(created_at) f, max(created_at) l from ins group by 1, 2)
insert into public.gallery as g (user_id, card_id, count, mvp_count, first_at, last_at)
select user_id, card_id, n, n, f, l from agg
on conflict (user_id, card_id) do update set count = g.count + excluded.count, mvp_count = g.mvp_count + excluded.mvp_count,
  last_at = greatest(g.last_at, excluded.last_at);
