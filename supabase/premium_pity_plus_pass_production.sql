-- PRODUCTION (운영) · 프리미엄 소환 UR 천장 50 + 시즌패스 이름 '플러스 시즌패스' (2026-11-18 형님 결정)
-- 형님 승인 후 다음 운영 업데이트 때 실행. 상점 v2를 아직 안 돌렸으면 이름 변경은 건너뛰고 천장만 적용. shop_v2_production.sql 을 나중에 돌리면 이름도 플러스로 들어감.
-- 1) 프리미엄 소환(소환권): UR 없이 50회째는 프리미엄 UR 목록에서 무작위 1장 확정. 어떤 UR이든 나오면 0부터. 기본 확률·10회 HR 보장·하지은 강제 영입은 그대로.
--    하루 1회 무료 뽑기(story_daily_draw)는 천장이 없고 이 파일이 바꾸지 않음. 기존 소환 기록(kind=ticket)으로 카운터를 맞춤.
-- 2) shop_products.sku = pass_2 이름만 '플러스 시즌패스'로 (id·가격·보상은 그대로). 우편 제목은 상품 이름을 쓰므로 이후 우편부터 새 이름.
-- 선행: gacha_premium_ur.sql (story_ticket_draw · story_premium_ur · story_gacha). 상점 이름 변경은 shop_products 가 있을 때만.
-- 한 번에 실행 · 재실행 안전. 스테이징 파일은 premium_pity_plus_pass_staging.sql.
begin;
do $guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then raise exception 'STOP: premium pity + plus pass production only'; end if;
 if to_regclass('public.story_gacha') is null or to_regclass('public.story_gacha_log') is null or to_regclass('public.story_premium_ur') is null
    or to_regprocedure('public.story_ticket_draw(integer)') is null or to_regprocedure('public.story_tickets()') is null
    or to_regprocedure('public._story_ticket_sync(uuid)') is null then
  raise exception 'STOP: install story gacha and premium UR first'; end if;
end $guard$;

alter table public.story_gacha add column if not exists pity_misses int not null default 0 check (pity_misses >= 0);

-- 이미 뽑은 프리미엄 소환 기록으로 맞춤 (무료 뽑기·UR 확정권은 제외)
update public.story_gacha g set pity_misses = (
  select count(*)::int from public.story_gacha_log l
  where l.user_id = g.user_id and l.kind = 'ticket'
    and l.id > coalesce((select max(x.id) from public.story_gacha_log x
                         where x.user_id = g.user_id and x.kind = 'ticket' and x.grade = 'ULTRA RARE'), 0)
);

create or replace function public.story_tickets() returns jsonb language plpgsql security definer set search_path = public as $$
declare s jsonb; m int;
begin
  s := public._story_ticket_sync(auth.uid());
  select pity_misses into m from public.story_gacha where user_id = auth.uid();
  return s || jsonb_build_object('misses', coalesce(m, 0), 'pity', 50);
end $$;
revoke all on function public.story_tickets() from public, anon;
grant execute on function public.story_tickets() to authenticated;

-- 최신본(gacha_premium_ur.sql): 하지은 강제 영입 + 10회 HR 보장 + 프리미엄 UR 목록. 여기에 UR 천장 50만 추가.
create or replace function public.story_ticket_draw(p_count int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s jsonb; t int; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; out jsonb := '[]'::jsonb; i int; hr boolean := false;
  jslot int := 0; m int := 0; why text; forced boolean;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_count is null or p_count not in (1, 10) then raise exception 'invalid count'; end if;
  s := _story_ticket_sync(uid);   -- story_gacha 행 잠금 포함
  t := (s->>'tickets')::int;
  select pity_misses into m from story_gacha where user_id = uid;
  m := coalesce(m, 0);
  if t < p_count then return jsonb_build_object('ok', false, 'reason', 'tickets', 'tickets', t, 'added', (s->>'added')::int, 'misses', m, 'pity', 50); end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  if p_count = 10 and coalesce((d->>'ch0Pull')::boolean, false) = false and coalesce((d->>'ch0Jieun')::boolean, false) = false then
    jslot := 1 + floor(random() * 10)::int;   -- 강제 영입: 하지은 자리
    d := jsonb_set(d, '{ch0Jieun}', 'true'::jsonb);
  end if;
  for i in 1..p_count loop
    why := null;
    if i = jslot then
      cid := '10439'; g := 'SUPER RARE';
    else
      forced := (m >= 49);
      r := random();
      if p_count = 10 and i = 10 and not hr then   -- 10회 보장: 앞 9장이 모두 R 이하면 마지막 장은 HR 이상 (HR:SR:UR = 16:3.2:0.8)
        r := 0.80 + random() * 0.20;
      end if;
      g := case when r < 0.50 then 'NORMAL' when r < 0.80 then 'RARE' when r < 0.96 then 'HIGH RARE' when r < 0.992 then 'SUPER RARE' else 'ULTRA RARE' end;
      if forced and g <> 'ULTRA RARE' then
        g := 'ULTRA RARE'; why := 'ur_pity';
      elsif forced then why := 'ur_pity'; end if;
      cid := null;
      if g = 'ULTRA RARE' then   -- 고급 소환 UR: 정해진 목록(story_premium_ur)에서만. 새 UR은 목록에 넣어야 나옴
        select p.id into cid from story_card_pool p join story_premium_ur w on w.id = p.id where p.grade = g order by random() limit 1;
      else
        select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
      end if;
      if cid is null then raise exception 'empty pool for %', g; end if;
    end if;
    if g in ('HIGH RARE', 'SUPER RARE', 'ULTRA RARE') then hr := true; end if;
    if g = 'ULTRA RARE' then m := 0; else m := m + 1; end if;
    e := _story_new_card(cid);
    owned := owned || jsonb_build_array(e);
    out := out || jsonb_build_array(jsonb_build_object('card_id', cid, 'uid', e->>'uid', 'grade', g, 'guaranteed', why is not null, 'guarantee', why));
    insert into story_gacha_log (user_id, card_id, grade, kind) values (uid, cid, g, 'ticket');
  end loop;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  update story_gacha set tickets = tickets - p_count, pity_misses = m, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'cards', out, 'tickets', t - p_count, 'added', (s->>'added')::int, 'misses', m, 'pity', 50);
end $$;
revoke all on function public.story_ticket_draw(int) from public, anon;
grant execute on function public.story_ticket_draw(int) to authenticated;

-- 상품 id(pass_2)는 그대로, 플레이어가 보는 이름만 변경. 상점이 아직 없으면 건너뜀.
do $pass$
begin
  if to_regclass('public.shop_products') is null then return; end if;
  update public.shop_products set name = '플러스 시즌패스' where sku = 'pass_2' and name is distinct from '플러스 시즌패스';
end $pass$;

commit;
notify pgrst, 'reload schema';
