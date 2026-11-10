-- GENERATED: account-Lv20 facility upgrade ONLY; apply after level_unlocks_staging.sql.
-- No need to rerun the full original unlock SQL on an already-installed staging DB.
begin;
do $facility_guard$ begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: facilities only staging cuyqchmdcnsgzkwyclji; production forbidden'; end if;
 if to_regprocedure('public.unlock_intro_claim(text)') is null then raise exception 'STOP: run level_unlocks_staging.sql first'; end if;
end $facility_guard$;
-- Facilities are account-Lv20 features, NOT training-building upgrades.
-- Preserve every existing receipt, building level, EXP rate, price, material and job.
do $facility_policy$
declare levels jsonb:=public._unlock_levels(); intros jsonb:=public._unlock_intros(); e jsonb:='{"key":"facilities","level":20,"title":"연마소 · 도장","text":"⚒️ 연마소 · 🥋 도장 오픈","reward":{"gold":5000},"route":"camp","trigger":"","source_text":"연마소, 도장 설명"}'::jsonb;
begin
 levels:=levels||'{"forge":20,"dojo":20}'::jsonb;
 if not exists(select 1 from jsonb_array_elements(intros) x where x->>'key'=e->>'key') then
  intros:=intros||jsonb_build_array(e);
  select jsonb_agg(x order by (x->>'level')::int,ord) into intros from jsonb_array_elements(intros) with ordinality a(x,ord);
 end if;
 -- CREATE OR REPLACE retains existing function OIDs and ACLs.
 execute format('create or replace function public._unlock_levels() returns jsonb language sql immutable as %L','select '||quote_literal(levels::text)||'::jsonb');
 execute format('create or replace function public._unlock_intros() returns jsonb language sql immutable as %L','select '||quote_literal(intros::text)||'::jsonb');
end $facility_policy$;

do $facility_functions$
declare f record; rule jsonb; body text;
begin
 for rule in select * from jsonb_array_elements($rules$[
  {"name":"camp_forge_start","old":"if (_camp_st(uid)).camp_lv < _camp_forge_lv() then raise exception 'forge locked'; end if;","new":"perform public._unlock_require('forge'); -- facility-account-v1"},
  {"name":"camp_dojo_unlock","old":"if cs.camp_lv < _camp_dojo_lv() then raise exception 'dojo locked'; end if;","new":"perform public._unlock_require('dojo'); -- facility-account-v1"},
  {"name":"camp_dojo_start","old":"begin","new":"begin\n  perform public._unlock_require('dojo'); -- facility-account-v1"},
  {"name":"_camp_json","old":"'forge_lv', _camp_forge_lv(),","new":"'forge_account_level', 20, 'dojo_account_level', 20, 'forge_open', plv >= 20, 'dojo_open', plv >= 20, -- facility-account-v1\n    'forge_lv', _camp_forge_lv(),"}
 ]$rules$::jsonb) loop
  select p.prosrc,pg_get_functiondef(p.oid) def into strict f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname=rule->>'name';
  if position('facility-account-v1' in f.prosrc)>0 then continue; end if;
  if position(rule->>'old' in f.prosrc)=0 then raise exception 'STOP: unexpected facility function: %',rule->>'name'; end if;
  if rule->>'name'='camp_dojo_start' then body:=regexp_replace(f.prosrc,'\mbegin\M',rule->>'new','i');
  else body:=replace(f.prosrc,rule->>'old',rule->>'new'); end if;
  execute replace(f.def,f.prosrc,body);
 end loop;
end $facility_functions$;

commit;
notify pgrst,'reload schema';
