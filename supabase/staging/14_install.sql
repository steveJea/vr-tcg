-- ⚠ 테스트 전용 14/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
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
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> 'd7d89da318ab1607c923a8d19e4fbc0734a34a5763a279ee027425b6e83045d7' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 14) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 14 and part_hash = '4751c85533585c16010801da7d598e22e802fe20588fabc1661d076f8ac267aa') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '14_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 14) <> 13 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (14_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$grant execute on function public.war_ui() to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.war_auto_assign() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_auto_assign_v4(); end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_auto_assign() from public,anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_auto_assign() to authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public.war_meta() returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$ begin perform _guildbattle_guard_v4(); perform pg_advisory_xact_lock(hashtext('guildbattle:v4')); return _war_meta_v4(); end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.war_meta() from public,anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.war_meta() to authenticated;$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함


-- ===== SOURCE: level_unlocks_staging.sql =====
-- GENERATED: node tools/build_unlock_policy.mjs. Run ONLY on staging, after security phases 1-4.
-- Production is explicitly forbidden. No existing user state is reset.
-- 설치본의 단일 트랜잭션에 포함
-- Unlock cluster guard is enforced by installer outer guard.
create or replace function public._unlock_levels() returns jsonb language sql immutable as $$select '{"pvp_hr":3,"gear":3,"dispatch":5,"guild":6,"friends":8,"tower":10,"raid":11,"camp":12,"merge":13,"skill":13,"lend":13,"sigil":14,"pvp_open":15,"trade":15,"pvp_3v3":17,"war":18,"pvp_boss":20,"tower_wind":25,"tower_ice":25,"tower_fire":25,"tower_light":40,"tower_dark":40,"forge":20,"dojo":20}'::jsonb$$;$vr_statement$;
  execute $vr_statement$create or replace function public._unlock_intros() returns jsonb language sql immutable as $$select '[{"key":"ch0","level":1,"title":"프리미엄 소환","text":"챕터 0을 완료했어요. 프리미엄 10회 소환으로 새로운 인재를 만나 보세요.","reward":{},"route":"summon","trigger":"ch0","source_text":"챕터0 클리어- 소환(프리미엄) 10회"},{"key":"leader","level":1,"title":"인재 레벨업","text":"지급된 리더를 레벨업해 보세요. 1레벨씩 또는 10레벨씩 올릴 수 있어요.","reward":{"blood":5000,"gold":5000},"route":"cards","trigger":"1:1","source_text":"ch1 P1클리어- 지급된 리더 레벨업. lv1업, lv10업"},{"key":"deck","level":1,"title":"덱 설정","text":"덱에 출전할 인재를 배치하고 리더를 정해 보세요.","reward":{"gold":5000},"route":"decks","trigger":"1:3","source_text":"ch1 p3클리어- 덱 설정 및 방법 설명"},{"key":"pvp_hr","level":3,"title":"PvP · 장비 가방","text":"HR 이하 1대1 리그가 열렸어요. PvP 덱을 배치하고 장비를 확인해 보세요.","reward":{"gold":5000},"route":"pvp","trigger":"","source_text":"pvp덱배치 및 다른 pvp설명."},{"key":"dispatch","level":5,"title":"파견","text":"인재를 파견하면 시간이 지난 뒤 보상을 받아요. 파견할 인재와 의뢰를 골라 보세요.","reward":{"gold":5000},"route":"dispatch","trigger":"","source_text":"레벨5 되면 파견 설명 및 실행"},{"key":"guild","level":6,"title":"조직","text":"조직에 가입하거나 직접 만들 수 있어요. 가입은 지금 하지 않아도 괜찮아요.","reward":{"gold":5000,"boxes":2},"route":"guild","trigger":"","source_text":"레벨6 되면 조직 가입 또는 창설 설명"},{"key":"friends","level":8,"title":"친구 · 선물","text":"친구를 추가하고 행동력 선물을 주고받을 수 있어요.","reward":{},"route":"friends","trigger":"","source_text":"친구를 추가하고 행동력 선물을 주고받을 수 있어요."},{"key":"tower","level":10,"title":"시련의 탑","text":"덱을 골라 일반 전투 한 판만 도전해 보세요. 소탕은 원할 때 사용할 수 있어요.","reward":{"gold":5000,"boxes":2},"route":"tower","trigger":"","source_text":"시련의탑 설명, 강제 실행(일반+소탕)"},{"key":"raid","level":11,"title":"토벌","text":"조직원들과 보스를 토벌할 수 있어요. 아직 조직이 없어도 안내와 보상은 받을 수 있어요.","reward":{"tickets":10},"route":"raid","trigger":"","source_text":"토벌 방법 및 내용 설명, 시행(길드 가입자 한정)"},{"key":"camp","level":12,"title":"훈련소","text":"인재를 맡기면 훈련 경험치가 쌓여요. 가장 낮은 레벨 인재를 추천하지만 직접 골라도 돼요.","reward":{"gold":5000,"boxes":2},"route":"camp","trigger":"","source_text":"훈련소 설명 및 강제 배정(가장 레벨 낮은 캐릭터)"},{"key":"skill","level":13,"title":"EX 합성 · 스킬 강화 · 대여","text":"인재를 EX 합성하거나 스킬을 강화할 수 있어요. 조직 인재 대여도 열렸어요.","reward":{"soul":1000,"gold":5000},"route":"cards","trigger":"","source_text":"스킬 강화 방법 알려줌"},{"key":"sigil","level":14,"title":"증표","text":"인재 전용 증표를 만들고 강화할 수 있어요. 선택 상자는 우편에서 받을 수 있어요.","reward":{"sigil_boxes":10},"route":"cards","trigger":"","source_text":"증표 설명"},{"key":"trade","level":15,"title":"무제한 1대1 · 거래소","text":"무제한 1대1 리그와 거래소가 열렸어요. 거래소는 계정 생성 후 7일이 지나면 이용할 수 있어요.","reward":{"tickets":10},"route":"trade","trigger":"","source_text":"거래소 설명 및 방법"},{"key":"pvp_3v3","level":17,"title":"3대3 리그","text":"세 덱으로 겨루는 3대3 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요.","reward":{},"route":"pvp","trigger":"","source_text":"세 덱으로 겨루는 3대3 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."},{"key":"war","level":18,"title":"조직전","text":"조직원들과 방어 덱을 배치하고 상대 조직에 도전해 보세요.","reward":{},"route":"war","trigger":"","source_text":"조직원들과 방어 덱을 배치하고 상대 조직에 도전해 보세요."},{"key":"pvp_boss","level":20,"title":"보스 리그","text":"진영 보스를 지키는 보스 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요.","reward":{},"route":"pvp","trigger":"","source_text":"진영 보스를 지키는 보스 리그가 열렸어요. 두 리그에서 모두 도전할 수 있어요."},{"key":"facilities","level":20,"title":"연마소 · 도장","text":"연마소에서 장비를, 도장에서 스킬을 강화할 수 있어요. 훈련소 건물 레벨과 무관하게 이용하며 기존 재료와 도장 개방 비용은 필요해요.","reward":{"gold":5000},"route":"camp","trigger":"","source_text":"연마소, 도장 설명"},{"key":"attr25","level":25,"title":"바람 · 얼음 · 불의 탑","text":"같은 속성 인재로 도전하는 세 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요.","reward":{},"route":"tower","trigger":"","source_text":"같은 속성 인재로 도전하는 세 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."},{"key":"attr40","level":40,"title":"빛의 섬 · 어둠의 늪","text":"빛과 어둠의 인재를 위한 두 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요.","reward":{},"route":"tower","trigger":"","source_text":"빛과 어둠의 인재를 위한 두 탑이 열렸어요. 각 탑의 개방 요일에 도전해 보세요."}]'::jsonb$$;$vr_statement$;
  execute $vr_statement$-- Account levels never change here. Existing stamina->account EXP rules are untouched.
create or replace function public._unlock_require(p_key text) returns void language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); n int;
begin
 if u is null then raise exception 'login required'; end if;
 n:=(public._unlock_levels()->>p_key)::int;
 if n is null then raise exception 'invalid unlock key'; end if;
 if coalesce((select level from public.player_state where user_id=u),1)<n then
  raise exception 'Lv%',n;
 end if;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._unlock_pvp_key(l text,m text) returns text language plpgsql immutable as $$
begin
 if l not in ('hr','open') or m not in ('1v1','3v3','boss') or l is null or m is null then raise exception 'invalid PvP league/mode'; end if;
 return case m when 'boss' then 'pvp_boss' when '3v3' then 'pvp_3v3' else case l when 'hr' then 'pvp_hr' else 'pvp_open' end end;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._player_unlock_level(p_key text) returns int language sql immutable as $$
 select case when p_key ~ '^chapter_[0-9]+$' then 1 else case p_key
 when 'sweep' then 5 when 'skill' then 13 when 'equip' then 3 when 'equip_merge' then 20 else null end end
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._tower_min_level(p text) returns int language sql immutable as $$
 select case p when 'normal' then 10 when 'light' then 40 when 'dark' then 40 else 25 end
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._guild_min_level() returns int language sql immutable as $$select 6$$;$vr_statement$;
  execute $vr_statement$create or replace function public._lend_min_level() returns int language sql immutable as $$select 13$$;$vr_statement$;
  execute $vr_statement$create or replace function public._camp_need_level(s int) returns int language sql immutable as $$
 select case s when 1 then 12 when 2 then 20 when 3 then 35 when 4 then 50 when 5 then 70 end
$$;$vr_statement$;
  execute $vr_statement$insert into public.trade_config(key,val,note) values('min_level',15,'계정 레벨 하한') on conflict(key) do update set val=15;$vr_statement$;
  execute $vr_statement$-- CREATE OR REPLACE preserves the exact OID, defaults, ACL and phase2/3/4 validation.
-- Only this explicit list is patched; revoked legacy endpoints are NEVER re-granted.
do $rpc_gates$
declare rule jsonb; f record; body text; ddl text;
begin
 for rule in select * from jsonb_array_elements('[{"name":"dispatch_refresh","gate":"perform public._unlock_require(''dispatch'');"},{"name":"dispatch_start","gate":"perform public._unlock_require(''dispatch'');"},{"name":"guild_create","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_apply","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_update","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_transfer","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_kick","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_shop_buy","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_rally_claim","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_quest_claim","gate":"perform public._unlock_require(''guild'');"},{"name":"friend_request","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_respond","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_gift_send","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_gift_claim","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_gift_claim_all","gate":"perform public._unlock_require(''friends'');"},{"name":"friend_battle_start","gate":"perform public._unlock_require(''friends'');"},{"name":"gear_expand","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_lock","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_equip","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_unequip","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_box_open","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_enhance","gate":"perform public._unlock_require(''gear'');"},{"name":"gear_reroll","gate":"perform public._unlock_require(''gear'');"},{"name":"camp_put","gate":"perform public._unlock_require(''camp'');"},{"name":"camp_unlock","gate":"perform public._unlock_require(''camp'');"},{"name":"camp_levelup","gate":"perform public._unlock_require(''camp'');"},{"name":"story_merge","gate":"perform public._unlock_require(''merge'');"},{"name":"story_skill_levelup","gate":"perform public._unlock_require(''skill'');"},{"name":"guild_lend_set","gate":"perform public._unlock_require(''lend'');"},{"name":"guild_lend_borrow","gate":"perform public._unlock_require(''lend'');"},{"name":"sigil_craft","gate":"perform public._unlock_require(''sigil'');"},{"name":"sigil_enhance","gate":"perform public._unlock_require(''sigil'');"},{"name":"sigil_exchange","gate":"perform public._unlock_require(''sigil'');"},{"name":"sigil_mail_claim","gate":"perform public._unlock_require(''sigil'');"},{"name":"raid_sweep_v4","gate":"perform public._unlock_require(''raid'');"},{"name":"raid_set_difficulty","gate":"perform public._unlock_require(''raid'');"},{"name":"war_set_deck","gate":"perform public._unlock_require(''war'');"},{"name":"war_set_slot","gate":"perform public._unlock_require(''war'');"},{"name":"war_signup","gate":"perform public._unlock_require(''war'');"},{"name":"war_auto_assign","gate":"perform public._unlock_require(''war'');"},{"name":"pvp_set_deck","gate":"perform public._unlock_require(public._unlock_pvp_key(p_league,p_mode));"},{"name":"pvp_start_v3","gate":"perform public._unlock_require(public._unlock_pvp_key(p_league,p_mode));"},{"name":"guildbattle_start_v4","gate":"perform public._unlock_require(case p_kind when ''raid'' then ''raid'' when ''war'' then ''war'' else null end);"},{"name":"guild_invite","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_respond","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_set_role","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_checkin","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_quest_reroll","gate":"perform public._unlock_require(''guild'');"},{"name":"guild_weekly_claim","gate":"perform public._unlock_require(''guild'');"},{"name":"_guild_add_member","gate":"if coalesce((select level from public.player_state where user_id=p_uid),1)<6 then raise exception ''Lv6''; end if;"}]'::jsonb) loop
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=rule->>'name') then
   raise exception 'STOP: required unlock RPC missing: %',rule->>'name';
  end if;
  for f in select p.oid,p.prosrc,l.lanname,pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
   where n.nspname='public' and p.proname=rule->>'name' loop
   if position('-- unlock-policy-v1' in f.prosrc)>0 then continue; end if;
   if f.lanname<>'plpgsql' or f.prosrc!~* '\mbegin\M' then raise exception 'STOP: unexpected unlock RPC language/body: %',rule->>'name'; end if;
   body:=regexp_replace(f.prosrc,'\mbegin\M',E'begin\n -- unlock-policy-v1\n '||(rule->>'gate')||E'\n','i');
   ddl:=replace(f.def,f.prosrc,body);
   execute ddl;
  end loop;
 end loop;
end $rpc_gates$;$vr_statement$;
  execute $vr_statement$create or replace function public.gear_dismantle(p_ids bigint[]) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public._unlock_require('gear'); return public._gear_salvage(p_ids,false); end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.gear_sell(p_ids bigint[]) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public._unlock_require('gear'); return public._gear_salvage(p_ids,true); end $$;$vr_statement$;
  execute $vr_statement$-- New users finish CH0 before CH1. Existing CH1+ access is grandfathered, not reset.
-- All later chapters already require every preceding clear in phase2; level walls above are removed.
create or replace function public._unlock_chapter1(p_target text) returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid();
begin
 if split_part(p_target,':',1)::int<1 then return; end if;
 if exists(select 1 from public.battle_clear_receipts_v2 where user_id=u and mode='story' and split_part(target,':',1)::int>=1)
 or exists(select 1 from public.battle_legacy_access_v2 b,jsonb_each(b.cleared) c where b.user_id=u and case when c.key ~ '^[0-9]{1,3}$' then c.key::int else 0 end>=1 and jsonb_array_length(case when jsonb_typeof(c.value)='array' then c.value else '[]'::jsonb end)>0) then return; end if;
 if exists(select 1 from public.story_phase_config c where c.chapter=0 and not public._clear_access_v2(u,'story','0:'||c.phase)) then raise exception 'previous chapter required'; end if;
end $$;$vr_statement$;
  execute $vr_statement$do $chapter_gate$
declare f record; body text;
begin
 select p.prosrc,pg_get_functiondef(p.oid) def into f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='battle_session_start_v2';
 if position('-- unlock-chapter-v1' in f.prosrc)=0 then
  body:=regexp_replace(f.prosrc,'\mbegin\M',E'begin\n -- unlock-chapter-v1\n if p_mode=\'story\' and p_target ~ \'^[0-9]+:[0-9]+$\' then perform public._unlock_chapter1(p_target); end if;\n','i');
  execute replace(f.def,f.prosrc,body);
 end if;
end $chapter_gate$;$vr_statement$;
  execute $vr_statement$create table if not exists public.unlock_intro_receipts (
 user_id uuid not null references auth.users(id) on delete cascade,
 event text not null, reward jsonb not null, claimed_at timestamptz not null default now(),
 primary key(user_id,event)
);$vr_statement$;
  execute $vr_statement$alter table public.unlock_intro_receipts enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.unlock_intro_receipts from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._unlock_intro_eligible(u uuid,e jsonb) returns boolean language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $$
declare t text:=e->>'trigger';
begin
 if coalesce((select level from public.player_state where user_id=u),1)<(e->>'level')::int then return false; end if;
 if coalesce(t,'')='' then return true; end if;
 if t='ch0' then return not exists(select 1 from public.story_phase_config c where c.chapter=0 and not public._clear_access_v2(u,'story','0:'||c.phase)); end if;
 return public._clear_access_v2(u,'story',t);
end $$;$vr_statement$;
  execute $vr_statement$-- Assignment proof survives removing the trainee before returning to the lobby.
create table if not exists public.unlock_tutorial_actions (
 user_id uuid not null references auth.users(id) on delete cascade,
 action text not null check(action='camp'), completed_at timestamptz not null default now(),primary key(user_id,action)
);$vr_statement$;
  execute $vr_statement$alter table public.unlock_tutorial_actions enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.unlock_tutorial_actions from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._unlock_camp_action() returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if new.card_uid is not null then insert into public.unlock_tutorial_actions(user_id,action) values(new.user_id,'camp') on conflict do nothing; end if;
 return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists unlock_camp_action on public.camp_slots;$vr_statement$;
  execute $vr_statement$create trigger unlock_camp_action after insert or update of card_uid on public.camp_slots for each row execute function public._unlock_camp_action();$vr_statement$;
  execute $vr_statement$insert into public.unlock_tutorial_actions(user_id,action) select distinct user_id,'camp' from public.camp_slots where card_uid is not null on conflict do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public._unlock_action_done(u uuid,k text) returns boolean language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare lv int:=coalesce((select level from public.player_state where user_id=u),1);
begin
 if k='tower' then
  return exists(select 1 from public.battle_sessions_v2 where user_id=u and mode='tower' and target like 'normal:%' and status='settled')
   or not exists(select 1 from jsonb_array_elements(public._camp_owned(u)) o);
 elsif k='camp' then
  return exists(select 1 from public.unlock_tutorial_actions where user_id=u and action='camp')
   or not exists(select 1 from jsonb_array_elements(public._camp_owned(u)) o where coalesce((o->>'level')::int,1)<public._camp_cap(public._camp_grade(o->>'id'),coalesce((o->>'ex')::int,0),lv));
 end if;
 return true;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.unlock_status() returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); ps public.player_state; es jsonb;
begin
 if u is null then raise exception 'login required'; end if;
 ps:=public._player_sync(u);
 select coalesce(jsonb_agg(e||jsonb_build_object('eligible',public._unlock_intro_eligible(u,e),'action_done',public._unlock_action_done(u,e->>'key'),'claimed',exists(select 1 from public.unlock_intro_receipts r where r.user_id=u and r.event=e->>'key')) order by ord),'[]') into es
 from jsonb_array_elements(public._unlock_intros()) with ordinality a(e,ord);
 return jsonb_build_object('ok',true,'level',ps.level,'levels',public._unlock_levels(),'entries',es);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.unlock_intro_claim(p_event text) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); e jsonb; rw jsonb; wallet jsonb; i int;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('unlock-intro:'||u::text));
 select x into e from jsonb_array_elements(public._unlock_intros()) x where x->>'key'=p_event;
 if e is null then raise exception 'invalid intro'; end if;
 if exists(select 1 from public.unlock_intro_receipts where user_id=u and event=p_event) then return jsonb_build_object('ok',true,'already',true); end if;
 if not public._unlock_intro_eligible(u,e) then raise exception 'intro locked'; end if;
 if not public._unlock_action_done(u,p_event) then raise exception 'tutorial action required'; end if;
 rw:=e->'reward';
 insert into public.unlock_intro_receipts(user_id,event,reward) values(u,p_event,rw);
 -- Only these fixed server-owned amounts, never client input. No account/card EXP.
 if (rw-'tickets'-'boxes'-'sigil_boxes')<>'{}'::jsonb then
  wallet:=public._wallet_add(u,rw-'tickets'-'boxes'-'sigil_boxes','unlock_intro:'||p_event);
 end if;
 if coalesce((rw->>'tickets')::int,0)>0 then
  insert into public.story_gacha(user_id,last_draw) values(u,public._gem_day()-1) on conflict do nothing;
  update public.story_gacha set tickets=tickets+(rw->>'tickets')::int,updated_at=now() where user_id=u;
 end if;
 for i in 1..coalesce((rw->>'boxes')::int,0) loop
  insert into public.player_mail(user_id,kind,payload,reason,expires_at) values(u,'box','{"tier":4,"up_tier":5,"up_pct":5}','unlock_intro:'||p_event,now()+interval '14 days');
 end loop;
 for i in 1..coalesce((rw->>'sigil_boxes')::int,0) loop
  insert into public.player_mail(user_id,kind,payload,reason,expires_at) values(u,'sigil_frag','{"pick":"raid_select","n":1}','unlock_intro:'||p_event,now()+interval '14 days');
 end loop;
 return jsonb_build_object('ok',true,'gave',rw,'wallet',wallet);
end $$;$vr_statement$;
  execute $vr_statement$-- Facilities are account-Lv20 features, NOT training-building upgrades.
-- Preserve every existing receipt, building level, EXP rate, price, material and job.
do $facility_policy$
declare levels jsonb:=public._unlock_levels(); intros jsonb:=public._unlock_intros(); e jsonb:='{"key":"facilities","level":20,"title":"연마소 · 도장","text":"연마소에서 장비를, 도장에서 스킬을 강화할 수 있어요. 훈련소 건물 레벨과 무관하게 이용하며 기존 재료와 도장 개방 비용은 필요해요.","reward":{"gold":5000},"route":"camp","trigger":"","source_text":"연마소, 도장 설명"}'::jsonb;
begin
 levels:=levels||'{"forge":20,"dojo":20}'::jsonb;
 if not exists(select 1 from jsonb_array_elements(intros) x where x->>'key'=e->>'key') then
  intros:=intros||jsonb_build_array(e);
  select jsonb_agg(x order by (x->>'level')::int,ord) into intros from jsonb_array_elements(intros) with ordinality a(x,ord);
 end if;
 -- CREATE OR REPLACE retains existing function OIDs and ACLs.
 execute format('create or replace function public._unlock_levels() returns jsonb language sql immutable as %L','select '||quote_literal(levels::text)||'::jsonb');
 execute format('create or replace function public._unlock_intros() returns jsonb language sql immutable as %L','select '||quote_literal(intros::text)||'::jsonb');
end $facility_policy$;$vr_statement$;
  execute $vr_statement$do $facility_functions$
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
end $facility_functions$;$vr_statement$;
  execute $vr_statement$revoke all on function public._unlock_levels(),public._unlock_intros(),public._unlock_require(text),public._unlock_pvp_key(text,text),public._unlock_chapter1(text),public._unlock_intro_eligible(uuid,jsonb),public._unlock_action_done(uuid,text),public._unlock_camp_action() from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$-- CREATE OR REPLACE above does not touch the older helper ACLs; explicitly keep all new helpers private.
revoke all on function public.unlock_status(),public.unlock_intro_claim(text) from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.unlock_status(),public.unlock_intro_claim(text) to authenticated;$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함
notify pgrst,'reload schema';$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: security_phase5_arcade.sql =====
-- 보안 5단계: 아케이드. 기존 스테이징 업그레이드 전용, 전체 파일 1회 실행(재실행 안전).
-- 운영 금지. 원본 matches/과거 지급은 보존하되 검증 전 기록은 공식 전적·랭킹·미션에 합산하지 않음.
-- 설치본의 단일 트랜잭션에 포함
-- Phase5 cluster guard is enforced by installer outer guard.
create table if not exists public.arcade_policy_v5 (
 singleton boolean primary key default true check(singleton), enabled boolean not null default true, engine_hash text not null check(engine_hash ~ '^[a-f0-9]{64}$'));$vr_statement$;
  execute $vr_statement$insert into public.arcade_policy_v5(singleton,engine_hash) values(true,'e792c491ffafe19d047aa6f58db1920e5767e4059e14816611dd38d473871161')
on conflict(singleton) do update set engine_hash=excluded.engine_hash;$vr_statement$;
  execute $vr_statement$create table if not exists public.arcade_sessions_v5 (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade, request uuid not null,
 seed bigint not null check(seed between 0 and 4294967295), options jsonb not null,
 engine_hash text not null, status text not null default 'active' check(status in('active','settled')),
 created_at timestamptz not null default now(), expires_at timestamptz not null default (now()+interval '2 hours'),
 submission jsonb, result jsonb, unique(user_id,request));$vr_statement$;
  execute $vr_statement$create unique index if not exists arcade_one_active_v5 on public.arcade_sessions_v5(user_id) where status='active';$vr_statement$;
  execute $vr_statement$create index if not exists arcade_session_day_v5 on public.arcade_sessions_v5(user_id,created_at);$vr_statement$;
  execute $vr_statement$create table if not exists public.arcade_records_v5 (
 session_id bigint primary key references public.arcade_sessions_v5(id), user_id uuid not null references auth.users(id) on delete cascade,
 result text not null check(result in('win','lose','draw')), verified boolean not null,
 skills int not null default 0 check(skills between 0 and 20000), turns int not null default 0 check(turns between 0 and 400),
 damage bigint not null default 0 check(damage>=0), mvp_id text, mvp_name text, merc_id text,
 day date not null default public._gem_day(), week date not null default public._weekly_week(), created_at timestamptz not null default now(),
 check(verified or (result='lose' and skills=0 and damage=0)));$vr_statement$;
  execute $vr_statement$create index if not exists arcade_records_user_v5 on public.arcade_records_v5(user_id,day,week);$vr_statement$;
  execute $vr_statement$alter table public.arcade_policy_v5 enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.arcade_sessions_v5 enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.arcade_records_v5 enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.arcade_policy_v5,public.arcade_sessions_v5,public.arcade_records_v5 from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$revoke all on sequence public.arcade_sessions_v5_id_seq from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._arcade_enabled_v5() returns boolean language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select coalesce((select enabled from public.arcade_policy_v5 where singleton),false) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._arcade_options_v5(o jsonb) returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
begin
 if o is null or jsonb_typeof(o)<>'object' or (select count(*) from jsonb_object_keys(o))<>3 or not(o ?& array['grades','turns','clearFirst'])
 or o->'turns' not in ('0'::jsonb,'10'::jsonb,'40'::jsonb) or jsonb_typeof(o->'clearFirst')<>'boolean' then raise exception 'invalid arcade options'; end if;
 if o->'grades'<>'null'::jsonb then
  if jsonb_typeof(o->'grades')<>'array' then raise exception 'invalid arcade options'; end if;
  if jsonb_array_length(o->'grades') not between 1 and 6
  or exists(select 1 from jsonb_array_elements(o->'grades') g where g not in ('"NORMAL"','"RARE"','"HIGH RARE"','"SUPER RARE"','"ULTRA RARE"','"MYTHIC RARE"'))
  or (select count(distinct g) from jsonb_array_elements(o->'grades') g)<>jsonb_array_length(o->'grades') then raise exception 'invalid arcade options'; end if;
 end if;return o;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._arcade_close_v5(s public.arcade_sessions_v5, sub jsonb, r jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare receipt jsonb; verified_ boolean:=r is not null;
begin
 if r is null then r:=jsonb_build_object('result','lose','reason','forfeit','skills',0,'turns',0,'damage',0); end if;
 receipt:=r||jsonb_build_object('session_id',s.id::text,'verified',verified_);
 insert into public.arcade_records_v5(session_id,user_id,result,verified,skills,turns,damage,mvp_id,mvp_name,merc_id)
 values(s.id,s.user_id,r->>'result',verified_,(r->>'skills')::int,(r->>'turns')::int,(r->>'damage')::bigint,r->>'mvp_id',r->>'mvp_name',r->>'merc_id');
 update public.arcade_sessions_v5 set status='settled',submission=sub,result=receipt where id=s.id;
 return jsonb_build_object('ok',true,'status','settled','result',receipt);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_start_v5(p_request uuid,p_options jsonb,p_engine_hash text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); s public.arcade_sessions_v5; pol public.arcade_policy_v5; seed_ bigint;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('arcade-v5:'||u::text));
 select * into pol from public.arcade_policy_v5 where singleton for share;
 if pol.enabled is not true or pol.engine_hash is distinct from p_engine_hash then raise exception 'verifier unavailable'; end if;
 perform public._arcade_options_v5(p_options);if p_request is null then raise exception 'request required';end if;
 select * into s from public.arcade_sessions_v5 where user_id=u and request=p_request;
 if found then
  if s.options is distinct from p_options or s.engine_hash is distinct from p_engine_hash then raise exception 'request conflict';end if;
  return jsonb_build_object('ok',true,'id',s.id::text,'seed',s.seed,'options',s.options,'status',s.status,'result',s.result);
 end if;
 for s in select * from public.arcade_sessions_v5 where user_id=u and status='active' for update loop
  if s.expires_at>now() then raise exception 'active session';end if;
  perform public._arcade_close_v5(s,jsonb_build_object('expired',true),null);
 end loop;
 if (select count(*) from public.arcade_sessions_v5 where user_id=u and created_at>=(public._gem_day()::timestamp at time zone 'Asia/Seoul'))>=500
 or exists(select 1 from public.arcade_sessions_v5 where user_id=u and created_at>now()-interval '2 seconds') then raise exception 'rate limited';end if;
 seed_:=(('x'||substr(replace(gen_random_uuid()::text,'-',''),1,8))::bit(32)::bigint);
 insert into public.arcade_sessions_v5(user_id,request,seed,options,engine_hash) values(u,p_request,seed_,p_options,p_engine_hash) returning * into s;
 return jsonb_build_object('ok',true,'id',s.id::text,'seed',s.seed,'options',s.options,'status',s.status,'result',s.result);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_engine_session_v5(p_uid uuid,p_id bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.arcade_sessions_v5;
begin
 select * into s from public.arcade_sessions_v5 where id=p_id and user_id=p_uid;
 if not found then raise exception 'session not found';end if;
 return jsonb_build_object('id',s.id::text,'seed',s.seed,'options',s.options,'engine_hash',s.engine_hash,'status',s.status,'result',s.result);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_engine_settle_v5(p_uid uuid,p_id bigint,p_engine_hash text,p_submission jsonb,p_result jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.arcade_sessions_v5; pol public.arcade_policy_v5;
begin
 perform pg_advisory_xact_lock(hashtext('arcade-v5:'||p_uid::text));
 select * into pol from public.arcade_policy_v5 where singleton for share;
 select * into s from public.arcade_sessions_v5 where id=p_id and user_id=p_uid for update;
 if not found then raise exception 'session not found';end if;
 if s.status='settled' then
  if s.submission is distinct from p_submission and s.submission<>'{"expired":true}'::jsonb then raise exception 'submission conflict';end if;
  return jsonb_build_object('ok',true,'status','settled','result',s.result);
 end if;
 if p_submission is null or jsonb_typeof(p_submission)<>'object' or (select count(*) from jsonb_object_keys(p_submission))<>1 then raise exception 'invalid submission';end if;
 if p_submission<>'{"forfeit":true}'::jsonb and (not(p_submission?'actions') or jsonb_typeof(p_submission->'actions')<>'array' or jsonb_array_length(p_submission->'actions')>20000) then raise exception 'invalid submission';end if;
 if s.expires_at<=now() or p_submission='{"forfeit":true}'::jsonb then return public._arcade_close_v5(s,p_submission,null);end if;
 if pol.enabled is not true or pol.engine_hash is distinct from p_engine_hash or s.engine_hash is distinct from p_engine_hash then raise exception 'verifier unavailable';end if;
 if p_result is null or jsonb_typeof(p_result)<>'object' or p_result->>'result' not in ('win','lose','draw')
 or p_result->>'reason' not in ('ko','hp','cards','draw') or (p_result->>'skills')::int not between 0 and 20000 or (p_result->>'turns')::int not between 1 and 400
 or (p_result->>'damage')::bigint<0 then raise exception 'invalid server verdict';end if;
 return public._arcade_close_v5(s,p_submission,p_result);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.arcade_record_v5() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if auth.uid() is null then raise exception 'login required';end if;
 return(select jsonb_build_object('wins',count(*) filter(where result='win'),'losses',count(*) filter(where result='lose'),'draws',count(*) filter(where result='draw')) from public.arcade_records_v5 where user_id=auth.uid());
end $$;$vr_statement$;
  execute $vr_statement$-- The old raw report remains private legacy history, never an authoritative source.
revoke all on public.matches from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.matches to authenticated;$vr_statement$;
  execute $vr_statement$-- Column grants can survive table-level REVOKE in older installations.
do $$declare c record;begin for c in select attname from pg_attribute where attrelid='public.matches'::regclass and attnum>0 and not attisdropped loop execute format('revoke insert(%I),update(%I),references(%I) on public.matches from public,anon,authenticated',c.attname,c.attname,c.attname);end loop;end $$;$vr_statement$;
  execute $vr_statement$drop policy if exists matches_own_insert on public.matches;$vr_statement$;
  execute $vr_statement$create or replace view public.rankings_weekly
with (security_invoker = false) as
select
  row_number() over (order by sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end) desc,
                              count(*) filter (where m.result = 'win') desc,
                              min(m.created_at)) as rank,
  p.nickname,
  sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end)::int as score,
  (count(*) filter (where m.result = 'win'))::int as wins,
  (count(*) filter (where m.result = 'draw'))::int as draws,
  (count(*) filter (where m.result not in ('win','draw')))::int as losses,
  (m.user_id = auth.uid()) as is_me
from public.arcade_records_v5 m
join public.profiles p on p.id = m.user_id
where m.created_at >= (date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul')
group by m.user_id, p.nickname;$vr_statement$;
  execute $vr_statement$create or replace view public.rankings_all
with (security_invoker = false) as
select
  row_number() over (order by sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end) desc,
                              count(*) filter (where m.result = 'win') desc,
                              min(m.created_at)) as rank,
  p.nickname,
  sum(case m.result when 'win' then 3 when 'draw' then 1 else 0 end)::int as score,
  (count(*) filter (where m.result = 'win'))::int as wins,
  (count(*) filter (where m.result = 'draw'))::int as draws,
  (count(*) filter (where m.result not in ('win','draw')))::int as losses,
  (m.user_id = auth.uid()) as is_me
from public.arcade_records_v5 m
join public.profiles p on p.id = m.user_id
group by m.user_id, p.nickname;$vr_statement$;
  execute $vr_statement$revoke all on public.rankings_weekly, public.rankings_all from anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.rankings_weekly, public.rankings_all to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- Replace only progress suppliers; existing verified phase2/3 events still count.
do $$begin if to_regprocedure('public._phase5_old_mission_prog(uuid,text,boolean)') is null then alter function public._clear_mission_prog_v2(uuid,text,boolean) rename to _phase5_old_mission_prog;end if;
if to_regprocedure('public._phase5_old_ach_prog(uuid,text)') is null then alter function public._ach_prog(uuid,text) rename to _phase5_old_ach_prog;end if;end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_mission_prog_v2(u uuid,k text,w boolean) returns int language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select public._phase5_old_mission_prog(u,k,w)+coalesce((select case k when 'skill' then sum(skills) else count(*) end from public.arcade_records_v5
 where user_id=u and verified and case when w then week=public._weekly_week() else day=public._gem_day() end
 and case k when 'arcade' then true when 'win' then result='win' when 'skill' then true else false end),0)::int
$$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_missions_json_v2(u uuid,w boolean) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare defs jsonb:=case when w then public._weekly_defs() else public._daily_defs() end; period_ date:=case when w then public._weekly_week() else public._gem_day() end;
 claimed_ jsonb; missions jsonb:='[]'; m jsonb; n int; done_ int:=0; a public.daily_attend; res jsonb;
begin
 if w then select claimed into claimed_ from public.weekly_progress where user_id=u and week=period_;
 else select claimed into claimed_ from public.daily_progress where user_id=u and day=period_; end if;
 claimed_:=coalesce(claimed_,'[]');
 for m in select * from jsonb_array_elements(defs) loop
  n:=public._clear_mission_prog_v2(u,m->>'key',w); if n>=(m->>'goal')::int then done_:=done_+1; end if;
  missions:=missions||jsonb_build_array(m||jsonb_build_object('prog',least(n,(m->>'goal')::int),'held',m->>'key'='arcade' and not public._arcade_enabled_v5(),'claimed',claimed_ ? (m->>'key')));
 end loop;
 res:=jsonb_build_object('ok',true,'reward_held',false,'missions',missions,'next_reset',((period_+case when w then 7 else 1 end)::timestamp at time zone 'Asia/Seoul'),
 'all',jsonb_build_object('reward',case when w then public._weekly_all_reward() else public._daily_all_reward() end,'done',done_,'goal',jsonb_array_length(defs),'claimed',claimed_ ? 'all','held',not public._arcade_enabled_v5()));
 if w then return res||jsonb_build_object('week',period_); end if;
 select * into a from public.daily_attend where user_id=u;
 return res||jsonb_build_object('day',period_,'attend',jsonb_build_object('rewards',public._attend_defs(),'step',case when coalesce(a.step,0)>=7 and a.last_day<period_ then 0 else coalesce(a.step,0) end,'today',a.last_day=period_,'total',coalesce(a.total,0)));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._daily_json(p_uid uuid) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_missions_json_v2(p_uid,false) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._weekly_json(p_uid uuid) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_missions_json_v2(p_uid,true) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._clear_mission_claim_v2(k text,w boolean) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare u uuid:=auth.uid(); period_ date:=case when w then public._weekly_week() else public._gem_day() end; m jsonb; claimed_ jsonb; res jsonb;
begin
 if u is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:'||u::text)); perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 if k in ('arcade','all') and not public._arcade_enabled_v5() then raise exception 'reward verification pending';end if;
 if k='all' then
  if exists(select 1 from jsonb_array_elements(case when w then public._weekly_defs() else public._daily_defs() end) x where public._clear_mission_prog_v2(u,x->>'key',w)<(x->>'goal')::int) then raise exception 'not done';end if;
  m:=jsonb_build_object('reward',case when w then public._weekly_all_reward() else public._daily_all_reward() end);
 else
 select x into m from jsonb_array_elements(case when w then public._weekly_defs() else public._daily_defs() end) x where x->>'key'=k;
 if m is null then raise exception 'invalid mission'; end if;
 if public._clear_mission_prog_v2(u,k,w)<(m->>'goal')::int then raise exception 'not done'; end if;
 end if;
 if w then
  insert into public.weekly_progress(user_id,week) values(u,period_) on conflict do nothing;
  select claimed into claimed_ from public.weekly_progress where user_id=u and week=period_ for update;
 else
  insert into public.daily_progress(user_id,day) values(u,period_) on conflict do nothing;
  select claimed into claimed_ from public.daily_progress where user_id=u and day=period_ for update;
 end if;
 if claimed_ ? k then raise exception 'already claimed'; end if;
 if w then update public.weekly_progress set claimed=claimed||to_jsonb(k) where user_id=u and week=period_;
 else update public.daily_progress set claimed=claimed||to_jsonb(k) where user_id=u and day=period_; end if;
 res:=public._daily_grant(u,m->'reward',case when w then 'weekly' else 'daily' end,(case when w then 'weekly:' else 'daily:' end)||period_||':'||k);
 return public._clear_missions_json_v2(u,w)||res||jsonb_build_object('got',m->'reward');
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.daily_claim(p_key text) returns jsonb language sql security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_mission_claim_v2(p_key,false) $$;$vr_statement$;
  execute $vr_statement$create or replace function public.weekly_claim(p_key text) returns jsonb language sql security definer set search_path=pg_catalog,public,pg_temp as $$ select public._clear_mission_claim_v2(p_key,true) $$;$vr_statement$;
  execute $vr_statement$create or replace function public._ach_prog(p_uid uuid,p_id text) returns int language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if p_id='arcade_wins' then return(select count(*)::int from public.arcade_records_v5 where user_id=p_uid and verified and result='win');end if;
 if p_id='skill_uses' then return public._phase5_old_ach_prog(p_uid,p_id)+(select coalesce(sum(skills),0)::int from public.arcade_records_v5 where user_id=p_uid and verified);end if;
 return public._phase5_old_ach_prog(p_uid,p_id);
end $$;$vr_statement$;
  execute $vr_statement$do $$declare src text;begin
 src:=pg_get_functiondef('public._ach_json(uuid)'::regprocedure);
 execute replace(src,'''pvp_tier'')','''pvp_tier'',''arcade_wins'')');
end $$;$vr_statement$;
  execute $vr_statement$-- Explicit ACLs even when the project's default privileges are broad.
revoke all on function public._arcade_enabled_v5(),public._arcade_options_v5(jsonb),public._arcade_close_v5(public.arcade_sessions_v5,jsonb,jsonb),public._phase5_old_mission_prog(uuid,text,boolean),public._phase5_old_ach_prog(uuid,text),public._clear_mission_prog_v2(uuid,text,boolean),public._clear_missions_json_v2(uuid,boolean),public._clear_mission_claim_v2(text,boolean),public._ach_prog(uuid,text) from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.arcade_start_v5(uuid,jsonb,text),public.arcade_record_v5(),public.arcade_engine_session_v5(uuid,bigint),public.arcade_engine_settle_v5(uuid,bigint,text,jsonb,jsonb) from public,anon,authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.arcade_start_v5(uuid,jsonb,text),public.arcade_record_v5() to authenticated;$vr_statement$;
  execute $vr_statement$do $$declare f record;begin if exists(select 1 from pg_roles where rolname='service_role') then
 revoke all on public.arcade_policy_v5,public.arcade_sessions_v5,public.arcade_records_v5 from service_role;
 revoke all on sequence public.arcade_sessions_v5_id_seq from service_role;
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like '%arcade%v5' or p.proname like '_phase5_%') loop execute format('revoke all on function %s from service_role',f.sig);end loop;
 grant execute on function public.arcade_engine_session_v5(uuid,bigint),public.arcade_engine_settle_v5(uuid,bigint,text,jsonb,jsonb) to service_role;
 end if;end $$;$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함
select 'phase5 arcade verification installed — staging only' as result;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: security_phase6_story_tower.sql =====
-- 보안 6단계: 시련의 탑 소탕만 서버가 같은 전투를 다시 계산한다.
-- 스토리·수동 탑·특강은 기존 plausibility-v3 그대로다. 이 파일은 그 승패를 다시 증명하지 않는다.
-- 기존 스테이징 업그레이드 전용. 전체 파일 1회 실행(재실행 안전). 운영 금지.
-- 진행·잔액·이미 받은 보상은 지우거나 다시 주지 않는다.
-- 설치본의 단일 트랜잭션에 포함
-- Phase6 cluster guard is enforced by installer outer guard.

create table if not exists public.battle_replay_policy_v6 (
 singleton boolean primary key default true check (singleton),
 enabled boolean not null default false,
 engine_hash text not null check (engine_hash ~ '^[a-f0-9]{64}$'));$vr_statement$;
  execute $vr_statement$-- Starts off. Re-running this file updates the engine hash only and does not turn enforcement on.
insert into public.battle_replay_policy_v6(singleton, enabled, engine_hash)
 values (true, false, '1dbdb45994799cdcf3db14bd6eb44689d35678a733774caffcfd9867df85685c')
 on conflict (singleton) do update set engine_hash = excluded.engine_hash;$vr_statement$;
  execute $vr_statement$alter table public.battle_replay_policy_v6 enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.battle_replay_policy_v6 from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$do $$ begin
 if to_regprocedure('public._phase6_old_finish_v2(uuid,jsonb)') is null then
  alter function public.battle_session_finish_v2(uuid, jsonb) rename to _phase6_old_finish_v2;
 end if;
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.battle_session_finish_v2(p_session uuid, p_report jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare m text;
begin
 select mode into m from public.battle_sessions_v2 where id = p_session and user_id = auth.uid();
 if m = 'tower_sweep' and coalesce((select enabled from public.battle_replay_policy_v6 where singleton), false) then
  raise exception 'sweep replay required';
 end if;
 return public._phase6_old_finish_v2(p_session, p_report);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.battle_sweep_session_v6(p_uid uuid, p_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.battle_sessions_v2;
begin
 if p_uid is null or p_id is null then raise exception 'battle session not found'; end if;
 select * into s from public.battle_sessions_v2 where id = p_id and user_id = p_uid;
 if not found or s.mode <> 'tower_sweep' then raise exception 'battle session not found'; end if;
 return jsonb_build_object('ok', true, 'id', s.id, 'mode', s.mode, 'target', s.target, 'seed', s.seed,
  'snapshot', s.snapshot, 'status', s.status, 'expires_at', s.expires_at, 'submission', s.submission, 'settlement', s.settlement);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.battle_sweep_settle_v6(p_uid uuid, p_id uuid, p_engine_hash text, p_result jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s public.battle_sessions_v2; pol public.battle_replay_policy_v6; tp public.tower_progress;
 tw text; fl int; win_ boolean; reason_ text; tr int; mt int; first_ boolean; baseline int;
 rw jsonb; cur jsonb; pay jsonb := '{}'::jsonb; res jsonb;
begin
 if p_uid is null or p_id is null then raise exception 'battle session not found'; end if;
 perform pg_advisory_xact_lock(hashtext('battle-v2:' || p_uid::text));
 perform pg_advisory_xact_lock(hashtext('gem:' || p_uid::text));
 select * into pol from public.battle_replay_policy_v6 where singleton;
 select * into s from public.battle_sessions_v2 where id = p_id and user_id = p_uid for update;
 if not found or s.mode <> 'tower_sweep' then raise exception 'battle session not found'; end if;
 if s.status = 'settled' then
  if p_result is null or s.submission is distinct from p_result then raise exception 'submission conflict'; end if;
  return s.settlement;
 end if;
 if s.status <> 'issued' then raise exception 'battle session closed'; end if;
 if s.expires_at <= clock_timestamp() then
  update public.battle_sessions_v2 set status = 'expired', finished_at = clock_timestamp() where id = s.id and status = 'issued';
  return jsonb_build_object('ok', false, 'session', s.id, 'status', 'expired', 'reward_held', true, 'validation', 'replay-v6');
 end if;
 if pol.enabled is not true or pol.engine_hash is distinct from p_engine_hash or p_engine_hash !~ '^[a-f0-9]{64}$' then
  raise exception 'verifier unavailable';
 end if;
 -- The replay is the proof of the floor. min_seconds is a wall-clock stand-in for
 -- client-reported wins. A sweep opens one session per floor and settles it as soon
 -- as the replay returns; the client paces from the sweep start, so a later floor's
 -- session can be younger than 1 second and the check rejects a normal sweep.
 -- Volume stays limited per request by the daily session issuance cap and the tower
 -- daily floor cap, not by a minimum combat duration.
 if not public._clear_enabled_v2('tower') then raise exception 'reward verification pending'; end if;
 if jsonb_typeof(p_result) is distinct from 'object'
  or (select count(*) from jsonb_object_keys(p_result)) <> 4
  or not (p_result ?& array['win','reason','turns','my_turns'])
  or jsonb_typeof(p_result->'win') is distinct from 'boolean'
  or p_result->>'turns' !~ '^[0-9]{1,2}$' or p_result->>'my_turns' !~ '^[0-9]{1,2}$' then raise exception 'invalid replay'; end if;
 win_ := (p_result->>'win')::boolean;
 reason_ := p_result->>'reason';
 tr := (p_result->>'turns')::int;
 mt := (p_result->>'my_turns')::int;
 if tr < 1 or tr > 40 or mt <> ceil(tr / 2.0)::int then raise exception 'invalid replay'; end if;
 if win_ and reason_ <> 'wipe' or not win_ and reason_ not in ('wipe', 'timeout') then raise exception 'invalid replay'; end if;
 tw := split_part(s.target, ':', 1);
 fl := split_part(s.target, ':', 2)::int;
 if fl % 10 = 0 or fl < 1 then raise exception 'boss floor or invalid floor'; end if;
 tp := public._tower_row(p_uid, tw);
 perform public._tower_gate(p_uid, tw, tp);
 if fl > 1 and not public._clear_access_v2(p_uid, 'tower', tw || ':' || (fl - 1)::text) then raise exception 'floor locked'; end if;
 if not win_ then
  res := jsonb_build_object('ok', true, 'session', s.id, 'status', 'settled', 'win', false, 'cleared', false,
   'reward_held', false, 'validation', 'replay-v6', 'reason', reason_, 'turns', tr, 'reward', '{}'::jsonb, 'currency', '{}'::jsonb);
  update public.battle_sessions_v2 set status = 'settled', submission = p_result, settlement = res, finished_at = clock_timestamp() where id = s.id;
  return res;
 end if;
 baseline := coalesce((select (tower_paid->>tw)::int from public.battle_legacy_access_v2 where user_id = p_uid), 0);
 first_ := fl > baseline and not exists(select 1 from public.battle_clear_receipts_v2 where user_id = p_uid and mode = 'tower' and target = s.target);
 rw := case when first_ then public._tower_reward(tw, fl) else '{}'::jsonb end;
 cur := case when first_ then public._tower_currency(tw, fl) else '{}'::jsonb end;
 if first_ then pay := public._clear_grant_v2(p_uid, rw || cur, 'tower_v2', 'tower:' || s.target); end if;
 insert into public.battle_clear_receipts_v2(user_id, mode, target, session_id) values (p_uid, 'tower', s.target, s.id) on conflict do nothing;
 update public.tower_progress set battle = null, clears = clears + 1, day_floors = day_floors + 1, best_floor = greatest(best_floor, fl),
  paid_floor = case when first_ then greatest(paid_floor, fl) else paid_floor end,
  rewards = (select jsonb_object_agg(k, coalesce((rewards->>k)::int, 0) + coalesce((rw->>k)::int, 0) + coalesce((cur->>k)::int, 0)) from unnest(array['tickets','gold','blood','shard','soul']) k),
  updated_at = now()
  where user_id = p_uid and tower = tw;
 insert into public.battle_events_v2(session_id, user_id, mode, win, skills, day, week)
  values (s.id, p_uid, 'tower', true, 0, public._gem_day(), public._weekly_week())
  on conflict (session_id) do update set win = true, skills = 0;
 res := jsonb_build_object('tower', tw, 'floor', fl, 'best_floor', greatest(tp.best_floor, fl), 'first', first_, 'paid', first_,
  'reward', rw, 'currency', cur, 'tickets', pay->'tickets', 'today', tp.day_floors + 1, 'daily', public._tower_daily(tw),
  'ok', true, 'session', s.id, 'status', 'settled', 'win', true, 'cleared', true, 'reward_held', false,
  'validation', 'replay-v6', 'reason', reason_, 'turns', tr);
 update public.battle_sessions_v2 set status = 'settled', submission = p_result, settlement = res, finished_at = clock_timestamp() where id = s.id;
 return res;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._phase6_old_finish_v2(uuid, jsonb), public.battle_session_finish_v2(uuid, jsonb),
 public.battle_sweep_session_v6(uuid, uuid), public.battle_sweep_settle_v6(uuid, uuid, text, jsonb) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$grant execute on function public.battle_session_finish_v2(uuid, jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$do $$ begin
 if exists (select 1 from pg_roles where rolname = 'service_role') then
  revoke all on function public._phase6_old_finish_v2(uuid, jsonb), public.battle_session_finish_v2(uuid, jsonb),
   public.battle_sweep_session_v6(uuid, uuid), public.battle_sweep_settle_v6(uuid, uuid, text, jsonb) from service_role;
  revoke all on public.battle_replay_policy_v6 from service_role;
  grant execute on function public.battle_sweep_session_v6(uuid, uuid), public.battle_sweep_settle_v6(uuid, uuid, text, jsonb) to service_role;
 end if;
end $$;$vr_statement$;
  execute $vr_statement$notify pgrst, 'reload schema';$vr_statement$;
  execute $vr_statement$-- 설치본의 단일 트랜잭션에 포함
select 'phase6 tower sweep replay installed — staging only, story and manual tower remain plausibility-v3' as result;$vr_statement$;
  execute $vr_statement$-- 공개 게임 설정만 명시적으로 조회 허용 (사용자 자료 아님).
grant select on public.story_card_pool, public.story_phase_config, public.story_premium_ur,
  public.pvp_card_meta, public.pvp_reward_table, public.pvp_tier_table, public.pvp_streak_table,
  public.dispatch_card_meta, public.dispatch_zones to anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 설치 완료 (원본 SQL의 사용자 테이블은 처음부터 비어 있어야 함).
set local check_function_bodies = on;$vr_statement$;
  execute $vr_statement$do $staging_verify$
declare f record;
begin
  for f in
    select pg_get_functiondef(p.oid) ddl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop execute f.ddl; end loop;
  if exists (select 1 from auth.users) then raise exception 'STOP: 설치 중 사용자 자료 발견'; end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
      and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e')) then
    raise exception 'STOP: RLS 없는 테이블 발견';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and left(p.proname,1)='_'
      and pg_get_function_result(p.oid) <> 'trigger'
      and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then
    raise exception 'STOP: 외부 호출 가능한 내부 서버 함수 발견';
  end if;
end $staging_verify$;$vr_statement$;

  grant usage on schema public to public, anon, authenticated;
  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (14, 'd7d89da318ab1607c923a8d19e4fbc0734a34a5763a279ee027425b6e83045d7', '4751c85533585c16010801da7d598e22e802fe20588fabc1661d076f8ac267aa', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '14_install.sql: 완료 또는 이미 완료 (14/14)' as result;
