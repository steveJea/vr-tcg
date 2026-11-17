-- STAGING ONLY. Run in the staging SQL Editor as one script.
-- 'phase locked' when starting the phase after a story-only scene (16-12 -> 17-1, 17-7 -> 17-8,
-- 17-12 -> 17-13, 17-15 -> next chapter).
--   story_complete_scene saved the scene in story_progress only. battle_session_start_v2 opens a
--   phase via _clear_access_v2 (battle_clear_receipts_v2 or the frozen battle_legacy_access_v2
--   baseline), and a scene has neither, so the next phase stayed locked on the server while the
--   client map showed it open.
-- 1) story_complete_scene also records the scene in battle_legacy_access_v2 (access only: no stars,
--    rewards, missions). Replaying a cleared scene repairs it too.
-- 2) Backfill for scenes already cleared (only if the phase before the scene is access-cleared).
-- Patches the installed body in place (pg_get_functiondef + replace). Safe to run more than once.
-- No engine_hash change, no Edge redeploy. system_identifier 7703759698107299042.
do $$
declare
  f oid; src text; def_ text; r record; n_ int := 0;
  old_tail text := $q$  d := public._story_save(uid, d);
  begin tickets := public._story_ticket_sync(uid); exception when others then tickets := null; end;
$q$;
  new_tail text := $q$  d := public._story_save(uid, d);
  -- Scene phases have no battle session, so no battle_clear_receipts_v2 row. Record access here so
  -- battle_session_start_v2 (_clear_access_v2) opens the next phase (16-12 -> 17-1 'phase locked'). Access only, no rewards.
  insert into public.battle_legacy_access_v2 as a (user_id, cleared)
    values (uid, jsonb_build_object(p_chapter::text, jsonb_build_array(p_phase)))
  on conflict (user_id) do update set cleared = jsonb_set(a.cleared, array[p_chapter::text],
    case when jsonb_typeof(a.cleared->(p_chapter::text)) = 'array' then a.cleared->(p_chapter::text) else '[]'::jsonb end || to_jsonb(p_phase))
  where not coalesce(a.cleared->(p_chapter::text), '[]'::jsonb) @> to_jsonb(p_phase);
  begin tickets := public._story_ticket_sync(uid); exception when others then tickets := null; end;
$q$;
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: this file is for staging only (production forbidden)';
  end if;
  if to_regclass('public.battle_legacy_access_v2') is null or to_regprocedure('public._clear_access_v2(uuid,text,text)') is null then
    raise exception 'STOP: battle v2 access tables/functions not installed';
  end if;
  f := to_regprocedure('public.story_complete_scene(integer,integer)');
  if f is null then raise exception 'STOP: story_complete_scene not found'; end if;
  select prosrc into src from pg_catalog.pg_proc where oid = f;
  if src like '%insert into public.battle_legacy_access_v2 as a%' then
    raise notice 'story_complete_scene already records access; skip patch';
  elsif (length(src) - length(replace(src, old_tail, ''))) / length(old_tail) <> 1 then
    raise exception 'STOP: story_complete_scene body differs from the expected one; not patched';
  else
    def_ := replace(pg_catalog.pg_get_functiondef(f), old_tail, new_tail);
    execute def_;
    raise notice 'story_complete_scene patched (scene access)';
  end if;
  -- Backfill: scene phases already cleared in story_progress (before this fix) but invisible to
  -- _clear_access_v2. Only when the phase before the scene is itself access-cleared.
  for r in
    select s.user_id, c.chapter, c.phase
      from public.story_progress s
      join public.story_phase_config c on c.enemy_count = 0
     where jsonb_typeof(s.data->'cleared'->(c.chapter::text)) = 'array'
       and s.data->'cleared'->(c.chapter::text) @> to_jsonb(c.phase)
       and exists (select 1 from auth.users u where u.id = s.user_id)
       and not public._clear_access_v2(s.user_id, 'story', c.chapter::text || ':' || c.phase::text)
       and (c.phase = 1 or public._clear_access_v2(s.user_id, 'story', c.chapter::text || ':' || (c.phase - 1)::text))
  loop
    insert into public.battle_legacy_access_v2 as a (user_id, cleared)
      values (r.user_id, jsonb_build_object(r.chapter::text, jsonb_build_array(r.phase)))
    on conflict (user_id) do update set cleared = jsonb_set(a.cleared, array[r.chapter::text],
      case when jsonb_typeof(a.cleared->(r.chapter::text)) = 'array' then a.cleared->(r.chapter::text) else '[]'::jsonb end || to_jsonb(r.phase));
    n_ := n_ + 1;
  end loop;
  raise notice 'scene access backfill: % rows', n_;
end $$;
