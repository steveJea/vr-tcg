-- =====================================================================
-- 고급 소환(소환권 뽑기) UR 고정 목록. 새 UR 카드는 자동으로 들어가지 않음 (이 표에 넣어야 나옴)
-- 제외(2026-11-01 형님 결정): [각성] 윤진아 10291 · 이성호 10304 · 임규리 10322 · 하승진 10435 · 하지혜 10440 · 정아람 10359
-- 하루 1회 무료 뽑기 UR도 같은 목록 사용 (확률은 그대로). story_daily_draw 도 교체.
-- story_ticket_draw 교체 (story_ch0_jieun.sql 최신본 + UR 목록). 여러 번 실행해도 안전
-- =====================================================================
create table if not exists public.story_premium_ur (id text primary key, name text);
alter table public.story_premium_ur enable row level security;
drop policy if exists premium_ur_read on public.story_premium_ur;
create policy premium_ur_read on public.story_premium_ur for select using (true);
delete from public.story_premium_ur where id in ('10291','10304','10322','10435','10440','10359');
insert into public.story_premium_ur (id, name) values
  ('10051','김기림'),('10053','김대욱'),('10054','김동욱'),('10058','김백중'),('10176','서성민'),('10312','이진경'),
  ('10323','임나리'),('10324','임예리'),('10325','임유리'),('10331','임혜리'),('10358','정석윤')
on conflict (id) do nothing;

create or replace function public.story_ticket_draw(p_count int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s jsonb; t int; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; out jsonb := '[]'::jsonb; i int; hr boolean := false;
  jslot int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_count is null or p_count not in (1, 10) then raise exception 'invalid count'; end if;
  s := _story_ticket_sync(uid);   -- story_gacha 행 잠금 포함
  t := (s->>'tickets')::int;
  if t < p_count then return jsonb_build_object('ok', false, 'reason', 'tickets', 'tickets', t, 'added', (s->>'added')::int); end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  if p_count = 10 and coalesce((d->>'ch0Pull')::boolean, false) = false and coalesce((d->>'ch0Jieun')::boolean, false) = false then
    jslot := 1 + floor(random() * 10)::int;   -- 강제 영입: 하지은 자리
    d := jsonb_set(d, '{ch0Jieun}', 'true'::jsonb);
  end if;
  for i in 1..p_count loop
    if i = jslot then
      cid := '10439'; g := 'SUPER RARE';
    else
      r := random();
      if p_count = 10 and i = 10 and not hr then   -- 10회 보장: 앞 9장이 모두 R 이하면 마지막 장은 HR 이상 (HR:SR:UR = 16:3.2:0.8)
        r := 0.80 + random() * 0.20;
      end if;
      g := case when r < 0.50 then 'NORMAL' when r < 0.80 then 'RARE' when r < 0.96 then 'HIGH RARE' when r < 0.992 then 'SUPER RARE' else 'ULTRA RARE' end;
      cid := null;
      if g = 'ULTRA RARE' then   -- 고급 소환 UR: 정해진 목록(story_premium_ur)에서만. 새 UR은 목록에 넣어야 나옴
        select p.id into cid from story_card_pool p join story_premium_ur w on w.id = p.id where p.grade = g order by random() limit 1;
      else
        select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
      end if;
      if cid is null then raise exception 'empty pool for %', g; end if;
    end if;
    if g in ('HIGH RARE', 'SUPER RARE', 'ULTRA RARE') then hr := true; end if;
    e := _story_new_card(cid);
    owned := owned || jsonb_build_array(e);
    out := out || jsonb_build_array(jsonb_build_object('card_id', cid, 'uid', e->>'uid', 'grade', g));
    insert into story_gacha_log (user_id, card_id, grade, kind) values (uid, cid, g, 'ticket');
  end loop;
  d := _story_save(uid, jsonb_set(d, '{owned}', owned));
  update story_gacha set tickets = tickets - p_count, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'cards', out, 'tickets', t - p_count, 'added', (s->>'added')::int);
end $$;
revoke all on function public.story_ticket_draw(int) from public, anon;
grant execute on function public.story_ticket_draw(int) to authenticated;


create or replace function public.story_daily_draw() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); today date := (now() at time zone 'Asia/Seoul')::date; last date; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; cnt int;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_gacha (user_id, last_draw) values (uid, today - 1) on conflict (user_id) do nothing;
  select last_draw into last from story_gacha where user_id = uid for update;
  if last >= today then return jsonb_build_object('ok', false, 'reason', 'already', 'day', today); end if;
  r := random();
  g := case when r < 0.70 then 'NORMAL' when r < 0.90 then 'RARE' when r < 0.965 then 'HIGH RARE' when r < 0.995 then 'SUPER RARE' else 'ULTRA RARE' end;
  if g = 'ULTRA RARE' then   -- 무료 뽑기 UR도 고급 소환과 같은 목록(story_premium_ur)에서만
    select p.id into cid from story_card_pool p join story_premium_ur w on w.id = p.id where p.grade = g order by random() limit 1;
  else
    select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
  end if;
  if cid is null then raise exception 'empty pool for %', g; end if;
  d := _story_lock(uid);
  e := _story_new_card(cid);
  owned := _story_owned(d) || jsonb_build_array(e);
  select count(*) into cnt from jsonb_array_elements(owned) o where o->>'id' = cid;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{gachaLast}', to_jsonb(today::text));
  d := _story_save(uid, d);
  update story_gacha set last_draw = today, updated_at = now() where user_id = uid;
  insert into story_gacha_log (user_id, card_id, grade) values (uid, cid, g);
  return jsonb_build_object('ok', true, 'card_id', cid, 'uid', e->>'uid', 'grade', g, 'count', cnt, 'day', today);
end $$;
grant execute on function public.story_daily_draw() to authenticated;

-- 확인용: 고급 소환에서 나올 수 있는 UR (11명)
select w.id, w.name, p.grade from public.story_premium_ur w left join public.story_card_pool p on p.id = w.id order by w.id;
