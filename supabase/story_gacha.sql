-- ===== 스토리 특수 뽑기 (소환권) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 =====
-- 소환권: 챕터를 처음 다 깨면 +10 (지금까지 다 깬 챕터도 챕터마다 한 번씩 +10, 다시 주지 않음)
--   보관: story_gacha.tickets / ticket_chapters(이미 소환권을 준 챕터 번호)
--   지급 확인은 story_tickets() / story_ticket_draw() 를 부를 때 서버에서 함 (story_progress.cleared 와 story_phase_config 비교)
-- 특수 뽑기 확률: N 50% · R 30% · HR 16% · SR 3.2% · UR 0.8% · 10회 뽑기는 HR 이상 1장 보장
-- 추첨·차감은 전부 서버에서 (security definer). 클라이언트는 결과만 받음

alter table public.story_gacha add column if not exists tickets int not null default 0 check (tickets >= 0);
alter table public.story_gacha add column if not exists ticket_chapters int[] not null default '{}';
alter table public.story_gacha_log add column if not exists kind text not null default 'daily';

-- 챕터 첫 클리어 소환권 지급 (행 잠금). 반환 { tickets, added, chapters }
create or replace function public._story_ticket_sync(uid uuid) returns jsonb language plpgsql set search_path = public as $$
declare d jsonb; ch int; got int[]; t int; added int := 0; newch int[] := '{}';
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  select tickets, ticket_chapters into t, got from story_gacha where user_id = uid for update;
  select data into d from story_progress where user_id = uid;
  for ch in
    select c.chapter from story_phase_config c group by c.chapter
    having bool_and(case when jsonb_typeof(d->'cleared'->(c.chapter::text)) = 'array'
                         then (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase) or (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase::text) else false end)
    order by c.chapter
  loop
    if not (ch = any(got)) then got := got || ch; newch := newch || ch; added := added + 10; end if;
  end loop;
  if added > 0 then update story_gacha set tickets = tickets + added, ticket_chapters = got, updated_at = now() where user_id = uid; t := t + added; end if;
  return jsonb_build_object('tickets', t, 'added', added, 'chapters', to_jsonb(newch));
end $$;
revoke all on function public._story_ticket_sync(uuid) from public, anon, authenticated;

-- 소환권 개수 (+ 새로 받은 소환권). 반환 { tickets, added, chapters }
create or replace function public.story_tickets() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return _story_ticket_sync(auth.uid());
end $$;
revoke all on function public.story_tickets() from public, anon;
grant execute on function public.story_tickets() to authenticated;

-- 특수 뽑기: p_count = 1 또는 10. 반환 { ok, cards: [{card_id, uid, grade}], tickets, added } / 소환권 부족 { ok:false, reason:'tickets', tickets }
create or replace function public.story_ticket_draw(p_count int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s jsonb; t int; r double precision; g text; cid text; d jsonb; owned jsonb; e jsonb; out jsonb := '[]'::jsonb; i int; hr boolean := false;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_count is null or p_count not in (1, 10) then raise exception 'invalid count'; end if;
  s := _story_ticket_sync(uid);   -- story_gacha 행 잠금 포함
  t := (s->>'tickets')::int;
  if t < p_count then return jsonb_build_object('ok', false, 'reason', 'tickets', 'tickets', t, 'added', (s->>'added')::int); end if;
  d := _story_lock(uid);
  owned := _story_owned(d);
  for i in 1..p_count loop
    r := random();
    if p_count = 10 and i = 10 and not hr then   -- 10회 보장: 앞 9장이 모두 R 이하면 마지막 장은 HR 이상 (HR:SR:UR = 16:3.2:0.8)
      r := 0.80 + random() * 0.20;
    end if;
    g := case when r < 0.50 then 'NORMAL' when r < 0.80 then 'RARE' when r < 0.96 then 'HIGH RARE' when r < 0.992 then 'SUPER RARE' else 'ULTRA RARE' end;
    if g in ('HIGH RARE', 'SUPER RARE', 'ULTRA RARE') then hr := true; end if;
    select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
    if cid is null then raise exception 'empty pool for %', g; end if;
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
