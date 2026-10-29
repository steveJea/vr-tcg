-- =====================================================================
-- 챕터 0 클리어 강제 10회 영입(임유리 튜토리얼)에서 하지은(10439) 확정 — 계정당 한 번
-- 조건: 10회 뽑기 · 강제 영입이 아직 안 끝남(save.ch0Pull 없음) · 확정 받은 적 없음(save.ch0Jieun 없음)
-- 10장 중 무작위 한 자리를 하지은으로, 나머지 9장은 기존과 같이 무작위. 그 외 동작은 story_gacha.sql 과 동일
-- 여러 번 실행해도 안전 (story_ticket_draw 만 교체)
-- =====================================================================
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
      select id into cid from story_card_pool where grade = g and coalesce(gacha, true) order by random() limit 1;
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
