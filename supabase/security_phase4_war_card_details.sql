-- EXISTING STAGING ONLY: read-only war card metadata upgrade (no HP, decks, clock or engine changes).
-- Same allowlisted projection as security_phase4_raid_guildwar.sql. Run the whole file.
begin;
do $details_guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: war details staging cuyqchmdcnsgzkwyclji only'; end if;
 if not exists(select 1 from public.guildbattle_policy_v4 where singleton and engine_hash='d7b380a2680ba696fd5faefbda27a64b4cf8f624d01528258e0cc42365180728') then raise exception 'STOP: phase4 engine version mismatch'; end if;
 if to_regprocedure('public._war_side_json_v4(bigint,integer)') is null then raise exception 'STOP: install phase4 first'; end if;
end $details_guard$;
create or replace function public._war_side_json_v4(p_mid bigint, p_side int) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', a.slot, 'role', a.role, 'npc', a.npc, 'user_id', a.user_id,
      'name', case when a.npc and a.user_id is null then '동네 불량배' else coalesce(p.nickname, '조직원') end, 'deck', a.deck, 'decks', jsonb_array_length(a.snaps) - (case when jsonb_array_length(coalesce(a.snaps->1, '[]'::jsonb)) = 0 then 1 else 0 end),
      'cards', (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', c->'level', 'scale', c->'scale', 'snapshot', jsonb_build_object('id',c->'id','level',c->'level','ex',c->'ex','exb',c->'exb','boost',c->'boost','skillLv',c->'skillLv','gear',c->'gear','sigil',c->'sigil','scale',c->'scale'), 'hp', a.state->(c->>'uid'))), '[]'::jsonb) from jsonb_array_elements(a.snaps->(a.deck - 1)) c),
      'destroyed', a.destroyed_at is not null, 'locked', a.locked_until > _war_now_v4()) order by a.slot), '[]'::jsonb)
  from war_ajits_v4 a left join profiles p on p.id = a.user_id where a.match_id = p_mid and a.side = p_side $$;
revoke all on function public._war_side_json_v4(bigint,integer) from public,anon,authenticated;
do $details_acl$ begin if exists(select 1 from pg_roles where rolname='service_role') then revoke all on function public._war_side_json_v4(bigint,integer) from service_role; end if; end $details_acl$;
commit;
