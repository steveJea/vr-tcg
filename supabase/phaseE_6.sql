-- =====================================================================
-- 단계 E-6: 스킬 레벨 (각성자의 혼 + 골드)
-- Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: story_*.sql, phaseE_1.sql (지갑), phaseE_3.sql (분해), phaseE_4.sql (비용 도우미 _lv_cost_g)
--
-- 규칙
--   액티브 스킬만 Lv1~10 (패시브 제외). 저장: story_progress.data.owned[i].skillLv = {"1":3,"2":1} (키 = 카드 스킬 순번 1부터, 없으면 Lv1)
--   효과(클라이언트 js/skills.js): 레벨당 +3% (Lv10 +27%) 스킬 피해·회복·버프/디버프 ATK/DEF 수치. 지속·확률·MP 그대로
--   쿨타임: Lv5 −1, Lv10 −1 더 (최소 1)
--   비용 Lv L → L+1: 혼 = 등급 기본 × ceil(L/2),  골드 = 등급 값 × L × 100  (피 없음)
--     혼 기본  N1 · R2 · HR3 · SR5 · UR8 · MR12      골드 값 = 카드 레벨업과 같은 N1 R1.5 HR2 SR3 UR4 MR6
--   해금: 카드 레벨 ≥ 스킬 해금 레벨 (story_skill_meta)
--   합성: 대상 skillLv 유지 (기존 합성이 그대로 둠), 재료의 skillLv 는 사라짐 (환급 없음)
--   분해: 쓴 혼(soulSpent)의 50% 환급 (카드별 내림), 골드 환급 없음
-- 구조: 기존 story_dismantle 을 _story_dismantle_e5 로 보관하고 같은 이름으로 감쌈 (phaseE_3.sql 재실행 후엔 이 파일도 다시 실행)
-- 확인용: select public.skill_cost_table();
-- =====================================================================

-- 1) 스킬 메타 (액티브 스킬 해금 레벨). data/skills.json 에서 생성
create table if not exists public.story_skill_meta (
  card_id text not null,
  idx     int  not null check (idx >= 1),
  unlock  int  not null default 1,
  primary key (card_id, idx)
);
alter table public.story_skill_meta enable row level security;
revoke all on public.story_skill_meta from anon, authenticated;
insert into public.story_skill_meta (card_id, idx, unlock) values
  ('1000200018',1,2),
  ('1000200018',2,5),
  ('1000200030',1,2),
  ('1000200030',2,5),
  ('1001500315',1,2),
  ('1001500315',3,7),
  ('1002100371',1,2),
  ('1002100371',2,5),
  ('1002100371',3,7),
  ('1002200372',2,5),
  ('1002400378',1,2),
  ('1002400378',2,5),
  ('1002400378',3,7),
  ('2000100001',1,2),
  ('2000100001',2,5),
  ('2000100001',3,7),
  ('2000300083',1,2),
  ('2000300083',2,5),
  ('2000300083',3,7),
  ('2000700165',1,2),
  ('2000700165',2,5),
  ('2000800197',1,2),
  ('2000800197',2,5),
  ('2000900234',2,5),
  ('2001100243',1,2),
  ('2001100243',2,5),
  ('2001400248',1,2),
  ('2001400248',2,5),
  ('2001500316',1,2),
  ('2001500316',2,5),
  ('2001500316',3,7),
  ('2001700342',1,2),
  ('2001700342',2,5),
  ('2000000001',1,2),
  ('2000000001',2,5),
  ('2000000001',3,7),
  ('2000000007',1,2),
  ('2000000007',2,5),
  ('2000000007',3,7),
  ('2000000008',1,2),
  ('2000000008',2,5),
  ('2000000008',3,7),
  ('1000000004',1,2),
  ('1000000004',2,5),
  ('1000000004',3,7),
  ('1000100007',1,3),
  ('1000100007',2,5),
  ('1002400375',1,3),
  ('1002400375',2,5),
  ('2000300082',1,3),
  ('2000300082',2,5),
  ('2000400088',1,3),
  ('2000400088',2,7),
  ('2000400097',1,3),
  ('2000400097',2,5),
  ('2000900225',1,3),
  ('2000900225',2,5),
  ('2001100233',1,3),
  ('2001100233',2,5),
  ('2001100241',1,5),
  ('2001100241',2,5),
  ('2001100242',1,3),
  ('2001100242',2,5),
  ('2001500314',1,2),
  ('2001500314',2,5),
  ('2001900347',1,2),
  ('2001900347',2,5),
  ('2000500114',1,2),
  ('2000500114',2,7),
  ('2000000003',1,2),
  ('1002100366',1,2),
  ('1002100366',2,5),
  ('2000100005',1,5),
  ('2000400087',1,5),
  ('2000400089',1,5),
  ('2000600115',1,5),
  ('2000900206',1,5),
  ('2000900207',1,5),
  ('2000900233',1,5),
  ('2001500308',1,5),
  ('2002000352',1,5),
  ('2002000353',1,5),
  ('2000000006',1,5),
  ('2000100006',1,3),
  ('2000200044',1,3),
  ('2000400098',2,5),
  ('1000600122',1,2),
  ('1000600120',1,2),
  ('2001500294',1,2),
  ('1000400092',1,2),
  ('1000400092',2,5),
  ('1000200024',1,2),
  ('1000200024',2,5),
  ('2001100235',1,2),
  ('2001100235',2,5),
  ('2000900215',2,5),
  ('1001500313',1,2),
  ('1001500313',2,5),
  ('1001500305',1,2),
  ('1001500305',2,5),
  ('2000800179',1,2),
  ('2000800179',2,5),
  ('2001400279',1,2),
  ('2001400279',2,5),
  ('2002400374',1,2),
  ('2001400246',1,2),
  ('1002000355',1,2),
  ('1002000355',2,5),
  ('1001000213',1,2),
  ('1001000213',2,5),
  ('1001600324',1,2),
  ('1001600324',2,5),
  ('2000400094',1,2),
  ('2000400094',2,5),
  ('1000300056',1,2),
  ('1000600125',1,2),
  ('1000600125',2,5),
  ('1000500109',1,2),
  ('1000500109',2,5),
  ('1000600130',1,2),
  ('1000000003',1,2),
  ('1000000003',2,5),
  ('2000700146',1,2),
  ('2000700146',2,5),
  ('2000800186',1,2),
  ('2000800186',2,5),
  ('1001500311',1,2),
  ('1001500311',2,5),
  ('2001100230',1,2),
  ('2001100230',2,5),
  ('2000200051',1,2),
  ('2000200051',2,5),
  ('2000200051',3,1),
  ('2000000017',1,2),
  ('2000000017',2,5),
  ('2000000014',2,2),
  ('2000000013',1,2),
  ('2000000013',2,5)
on conflict (card_id, idx) do update set unlock = excluded.unlock;

-- 2) 수치
create or replace function public._skill_lv_max() returns int language sql immutable as $$ select 10 $$;
create or replace function public._skill_soul_base(p_grade text) returns int language sql immutable as $$
  select case p_grade when 'NORMAL' then 1 when 'RARE' then 2 when 'HIGH RARE' then 3 when 'SUPER RARE' then 5 when 'ULTRA RARE' then 8 when 'MYTHIC RARE' then 12 else 1 end $$;
-- 레벨 L 에서 L+1 로 올리는 비용
create or replace function public._skill_cost(p_grade text, p_level int) returns jsonb language sql immutable as $$
  select jsonb_build_object('soul', _skill_soul_base(p_grade) * ceil(p_level / 2.0)::int, 'gold', ceil(_lv_cost_g(p_grade) * p_level * 100)::int) $$;
revoke all on function public._skill_lv_max(), public._skill_soul_base(text), public._skill_cost(text, int) from public, anon, authenticated;

-- 공개: 비용표 (탐침 겸용)
create or replace function public.skill_cost_table() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'version', 6, 'max', _skill_lv_max(), 'step_pct', 3, 'cd_minus_at', jsonb_build_array(5, 10),
    'skills', (select count(*) from story_skill_meta),
    'grades', jsonb_object_agg(g, jsonb_build_object('soul', _skill_soul_base(g), 'g', _lv_cost_g(g), 'lv1', _skill_cost(g, 1),
      'total', (select jsonb_build_object('soul', sum((_skill_cost(g, l)->>'soul')::int), 'gold', sum((_skill_cost(g, l)->>'gold')::int)) from generate_series(1, _skill_lv_max() - 1) l))))
  from unnest(array['NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE']) g
$$;
revoke all on function public.skill_cost_table() from public, anon;
grant execute on function public.skill_cost_table() to authenticated;

-- 3) 스킬 레벨업: p_uid 카드의 p_skill 번째(1부터) 액티브 스킬을 최대 p_levels 단계 (1~9). 재화가 허락하는 만큼만, 1단계도 못 올리면 'not enough ...'
create or replace function public.story_skill_levelup(p_uid text, p_skill int, p_levels int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i int; e jsonb; g text; ul int; lv int; from_lv int; k int := 0; gold int := 0; soul int := 0; c jsonb; w jsonb; hg bigint := 0; hs bigint := 0; sl jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_levels is null or p_levels < 1 or p_levels > 9 then raise exception 'invalid levels'; end if;
  if p_skill is null or p_skill < 1 then raise exception 'invalid skill'; end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  select (n - 1)::int into i from jsonb_array_elements(owned) with ordinality x(e, n) where x.e->>'uid' = p_uid;
  if i is null then raise exception 'card not owned'; end if;
  e := _story_norm(owned->i);
  select m.unlock into ul from story_skill_meta m where m.card_id = e->>'id' and m.idx = p_skill;
  if ul is null then raise exception 'invalid skill'; end if;            -- 없는 스킬·패시브
  if (e->>'level')::int < ul then raise exception 'skill locked'; end if;
  select grade into g from story_card_pool where id = e->>'id';
  g := coalesce(g, 'NORMAL');
  sl := case when jsonb_typeof(e->'skillLv') = 'object' then e->'skillLv' else '{}'::jsonb end;
  lv := greatest(1, least(_skill_lv_max(), coalesce((sl->>p_skill::text)::int, 1))); from_lv := lv;
  if lv >= _skill_lv_max() then raise exception 'max skill level'; end if;
  select coalesce(pw.gold, 0), coalesce(pw.soul, 0) into hg, hs from player_wallet pw where pw.user_id = uid;
  hg := coalesce(hg, 0); hs := coalesce(hs, 0);
  while k < p_levels and lv < _skill_lv_max() loop
    c := _skill_cost(g, lv);
    if gold + (c->>'gold')::int > hg or soul + (c->>'soul')::int > hs then
      if k = 0 then raise exception 'not enough %', case when soul + (c->>'soul')::int > hs then 'soul' else 'gold' end; end if;
      exit;
    end if;
    gold := gold + (c->>'gold')::int; soul := soul + (c->>'soul')::int;
    lv := lv + 1; k := k + 1;
  end loop;
  w := _wallet_add(uid, jsonb_build_object('gold', -gold, 'soul', -soul), 'skill_levelup');
  e := e || jsonb_build_object('skillLv', sl || jsonb_build_object(p_skill::text, lv), 'soulSpent', coalesce((e->>'soulSpent')::int, 0) + soul);
  owned := jsonb_set(owned, array[i::text], e);
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  return jsonb_build_object('data', d, 'skill', p_skill, 'from', from_lv, 'level', lv, 'gained', k, 'gold', gold, 'soul', soul, 'wallet', w);
end $$;
revoke all on function public.story_skill_levelup(text, int, int) from public, anon;
grant execute on function public.story_skill_levelup(text, int, int) to authenticated;

-- 4) 분해 감싸기: 원래 분해 후 쓴 혼 50% 환급
do $$
declare src text;
begin
  select prosrc into src from pg_proc where oid = to_regprocedure('public.story_dismantle(text[])');
  if src is not null and src not like '%phaseE_6 wrapper%' then
    drop function if exists public._story_dismantle_e5(text[]);
    alter function public.story_dismantle(text[]) rename to _story_dismantle_e5;
  end if;
end $$;
revoke all on function public._story_dismantle_e5(text[]) from public, anon, authenticated;

create or replace function public.story_dismantle(p_uids text[]) returns jsonb language plpgsql security definer set search_path = public as $$
-- phaseE_6 wrapper
declare uid uuid := auth.uid(); d jsonb; back int := 0; r jsonb; w jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select data into d from story_progress where user_id = uid for update;
  select coalesce(sum(floor(greatest(0, coalesce((x.e->>'soulSpent')::int, 0)) * 0.5)), 0)::int into back
    from jsonb_array_elements(_story_owned(coalesce(d, '{}'::jsonb))) x(e) where x.e->>'uid' = any(p_uids);
  r := _story_dismantle_e5(p_uids);                                         -- 검증 실패하면 전부 롤백
  if back > 0 then
    w := _wallet_add(uid, jsonb_build_object('soul', back), 'dismantle_skill');
    r := r || jsonb_build_object('soul', coalesce((r->>'soul')::int, 0) + back, 'skill_soul', back, 'wallet', w);
  end if;
  return r;
end $$;
revoke all on function public.story_dismantle(text[]) from public, anon;
grant execute on function public.story_dismantle(text[]) to authenticated;
