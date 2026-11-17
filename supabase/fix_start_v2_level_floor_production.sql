-- PRODUCTION ONLY. Run in the production SQL Editor as one script.
-- battle_session_start_v2: snapshot the same card levels the client fights with.
--   Client (js/story.js floorLv, #381): an owned forced/loan card below the sheet level
--   (party.levels / chapter loanLevel) fights at the sheet level for that battle only.
--   The session snapshot kept the real (lower) level, so the v7 replay
--   (story-direct-verify-v7) simulated weaker stats and rejected the clear as 'tampered'
--   ("전투 기록이 맞지 않아요"). Ex: 16-11 forces 소민섭 10200 at Lv60.
--   Also: a guest loan card now uses chapter loanLevel first, like the client.
-- Saved card levels/EXP are unchanged (snapshot only). No engine_hash change, no Edge redeploy.
-- Patches the installed body in place (pg_get_functiondef + replace). Safe to run more than once.
-- Production: v7 replay is off here, so this only matters once v7 is turned on (with the #618 release).
-- Harmless now: the legacy finish does not re-simulate, the higher snapshot level only matches what the client used.
-- system_identifier 7692130048193495360.
do $$
declare
  f oid; src text; def_ text;
  old_guest text := $q$    o:=jsonb_build_object('uid',x,'id',cid,'guest',true,'level',coalesce((pp->'fixedLevel'->>cid)::int,(pp->'levels'->>cid)::int,lv));$q$;
  new_guest text := $q$    o:=jsonb_build_object('uid',x,'id',cid,'guest',true,'level',coalesce((pp->'fixedLevel'->>cid)::int,case when not forced @> to_jsonb(cid) then (cfg->'loanLevel'->>cid)::int end,(pp->'levels'->>cid)::int,lv));$q$;
  old_cid text := $q$   if o is null then raise exception 'card not owned or loan expired'; end if;
   cid:=o->>'id';
$q$;
  new_cid text := $q$   if o is null then raise exception 'card not owned or loan expired'; end if;
   cid:=o->>'id';
   -- story floorLv (js/story.js partyOf): an owned forced/loan card below the sheet level fights at the sheet level
   -- for this battle only (saved level untouched). The v7 replay must see the same level or it reads 'tampered'.
   if p_mode='story' and not coalesce((o->>'guest')::boolean,false) then
    v:=case when forced @> to_jsonb(cid) then case when pp->'fixedLevel' ? cid then null else pp->'levels'->>cid end
     when coalesce(cfg->'loan','[]') @> to_jsonb(cid) and not coalesce(pp->'guests','[]') @> to_jsonb(cid) then coalesce(cfg->'loanLevel'->>cid,pp->'levels'->>cid) end;
    if v ~ '^[0-9]{1,3}$' and coalesce((o->>'level')::int,1) < least(100,greatest(1,v::int)) then o:=jsonb_set(o,'{level}',to_jsonb(least(100,greatest(1,v::int)))); end if;
   end if;
$q$;
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: this file is for production only (staging forbidden)';
  end if;
  f := to_regprocedure('public.battle_session_start_v2(text,text,jsonb,uuid)');
  if f is null then raise exception 'STOP: battle_session_start_v2 not found'; end if;
  select prosrc into src from pg_catalog.pg_proc where oid = f;
  if src like '%story floorLv (js/story.js partyOf)%' then
    raise notice 'battle_session_start_v2 already floors story levels; skip';
    return;
  end if;
  if (length(src) - length(replace(src, old_guest, ''))) / length(old_guest) <> 1
     or (length(src) - length(replace(src, old_cid, ''))) / length(old_cid) <> 1 then
    raise exception 'STOP: battle_session_start_v2 body differs from the expected phase2 start; not patched';
  end if;
  def_ := pg_catalog.pg_get_functiondef(f);
  def_ := replace(replace(def_, old_guest, new_guest), old_cid, new_cid);
  execute def_;
  raise notice 'battle_session_start_v2 patched (story level floor)';
end $$;
