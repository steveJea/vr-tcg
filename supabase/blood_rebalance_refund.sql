-- ⚠ 1회용. blood_rebalance.sql 다음에 실행. 다시 돌려도 이미 받은 유저는 건너뜀 (blood_rebalance_refunds 기록)
-- =====================================================================
-- 피 리밸런스 (2/2): 기존 유저 레벨업 비용 차액 환급
--   카드마다 bloodSpent(예전 공식으로 실제 쓴 피) 의 절반을 환급 = floor(bloodSpent / 2)
--   골드는 기록이 없어서 같은 단계의 골드:피 비율로 계산 = floor(환급 피 × g × 10 / b)   (SR 이면 피 1 당 골드 3.75)
--   카드의 bloodSpent 는 남은 절반으로 줄임 → 앞으로 분해 환급(50%)도 새 비용 기준
--   전투 EXP 로 오른 레벨은 피를 안 썼으니 환급 없음
--
-- [먼저] blood_rebalance_preview.sql 실행해서 숫자 확인 (읽기 전용)
-- [그다음] 1) ~ 2) 실행
-- =====================================================================

-- 0) 미리보기는 blood_rebalance_preview.sql (읽기 전용)

-- 1) 환급 기록 (유저당 1행 = 1회만)
create table if not exists public.blood_rebalance_refunds (
  user_id uuid primary key,
  cards int not null,
  blood bigint not null,
  gold bigint not null,
  at timestamptz not null default now()
);
alter table public.blood_rebalance_refunds enable row level security;
revoke all on public.blood_rebalance_refunds from public, anon, authenticated;

-- 2) 환급 실행
do $$
declare r record; d jsonb; owned jsonb; e jsonb; i int; s int; rb int; g text; tb bigint; tg bigint; n int;
begin
  for r in select sp.user_id from story_progress sp
           where not exists (select 1 from blood_rebalance_refunds x where x.user_id = sp.user_id) loop
    select data into d from story_progress where user_id = r.user_id for update;
    owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
    tb := 0; tg := 0; n := 0;
    for i in 0 .. jsonb_array_length(owned) - 1 loop
      e := owned->i; s := coalesce((e->>'bloodSpent')::int, 0);
      if s < 2 then continue; end if;
      select grade into g from story_card_pool where id = e->>'id'; g := coalesce(g, 'NORMAL');
      rb := s / 2;
      tb := tb + rb; tg := tg + floor(rb * _lv_cost_g(g) * 10 / _lv_cost_b(g))::bigint; n := n + 1;
      owned := jsonb_set(owned, array[i::text], e || jsonb_build_object('bloodSpent', s - rb));
    end loop;
    if n > 0 then
      update story_progress set data = jsonb_set(d, '{owned}', owned) where user_id = r.user_id;
      perform _wallet_add(r.user_id, jsonb_build_object('blood', tb, 'gold', tg), 'blood_rebalance_refund');
    end if;
    insert into blood_rebalance_refunds(user_id, cards, blood, gold) values (r.user_id, n, tb, tg);
  end loop;
end $$;

-- 확인: select count(*), sum(cards), sum(blood), sum(gold) from public.blood_rebalance_refunds;
