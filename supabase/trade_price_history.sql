-- ===== 거래소 6단계: 공개 시세 (읽기 전용) =====
-- 선행: trade_board.sql · trade_buynow_search.sql. 여러 번 실행해도 안전. 테이블 변경 없음 (함수만 추가)
-- 기준: 완료된 거래(trade_log) 중 '물건 1개 ↔ 재화만'인 거래만 시세로 씀 (여러 개 묶음·물건끼리 교환은 1개 가격을 알 수 없어서 제외)
--       드링크 가격과 골드 가격은 따로 계산. 즉시 구매(buy_now)와 제안 수락을 둘 다 포함하고 개수를 나눠서 보여 줌
-- 공개 범위: 로그인한 모든 플레이어. 누가 사고팔았는지(닉네임·id)는 내보내지 않음

create or replace function public._trade_sales(p_days int) returns table (kind text, item_id text, gkey text, drinks bigint, gold bigint, buy_now boolean, at timestamptz)
language sql stable security definer set search_path = public as $$
  select case when jsonb_array_length(coalesce(t.seller_gave->'cards', '[]')) = 1 then 'card' else 'gear' end,
         coalesce(t.seller_gave->'cards'->0->'card'->>'id', t.seller_gave->'gear'->0->'row'->>'def_id'),
         coalesce(t.seller_gave->'cards'->0->>'gkey', t.seller_gave->'gear'->0->>'gkey'),
         coalesce((t.buyer_gave->>'drinks')::bigint, 0), coalesce((t.buyer_gave->>'gold')::bigint, 0), t.buy_now, t.created_at
    from trade_log t
   where t.created_at > now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 90)))
     and jsonb_array_length(coalesce(t.seller_gave->'cards', '[]')) + jsonb_array_length(coalesce(t.seller_gave->'gear', '[]')) = 1
     and jsonb_array_length(coalesce(t.buyer_gave->'cards', '[]')) + jsonb_array_length(coalesce(t.buyer_gave->'gear', '[]')) = 0
     and coalesce((t.buyer_gave->>'drinks')::bigint, 0) + coalesce((t.buyer_gave->>'gold')::bigint, 0) > 0 $$;

-- 묶음 통계 (드링크·골드 각각 n·중앙값·최저·최고, 즉시 구매/제안 개수)
create or replace function public._trade_stats(p_kind text, p_id text, p_days int) returns jsonb language sql stable security definer set search_path = public as $$
  with s as (select * from _trade_sales(p_days) where kind = p_kind and item_id = p_id)
  select jsonb_build_object('n', (select count(*) from s),
    'buy_now', (select count(*) from s where buy_now), 'offer', (select count(*) from s where not buy_now),
    'drink', (select case when count(*) = 0 then null else jsonb_build_object('n', count(*), 'median', round(percentile_cont(0.5) within group (order by drinks))::bigint, 'min', min(drinks), 'max', max(drinks)) end from s where drinks > 0 and gold = 0),
    'gold', (select case when count(*) = 0 then null else jsonb_build_object('n', count(*), 'median', round(percentile_cont(0.5) within group (order by gold))::bigint, 'min', min(gold), 'max', max(gold)) end from s where gold > 0 and drinks = 0)) $$;

-- 한 물건의 시세: p_kind = card | gear, p_id = 인재 id 또는 장비 def_id
create or replace function public.trade_price_history(p_kind text, p_id text) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_kind not in ('card', 'gear') or coalesce(p_id, '') = '' then raise exception 'invalid item'; end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'id', p_id,
    'd7', _trade_stats(p_kind, p_id, 7), 'd30', _trade_stats(p_kind, p_id, 30),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'drinks', drinks, 'gold', gold, 'buy_now', buy_now) order by at desc), '[]'::jsonb)
                 from (select * from _trade_sales(30) where kind = p_kind and item_id = p_id order by at desc limit 20) r),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'n', n, 'drink', md, 'gold', mg) order by d), '[]'::jsonb)
                from (select (at at time zone 'Asia/Seoul')::date d, count(*) n,
                             round(percentile_cont(0.5) within group (order by drinks) filter (where drinks > 0 and gold = 0))::bigint md,
                             round(percentile_cont(0.5) within group (order by gold) filter (where gold > 0 and drinks = 0))::bigint mg
                        from _trade_sales(30) where kind = p_kind and item_id = p_id group by 1) x));
end $$;

-- 시세 목록: 최근 p_days 일 많이 거래된 물건 (p_kind = all | card | gear, p_gkey 등급 키 선택)
create or replace function public.trade_price_board(p_days int default 7, p_kind text default 'all', p_gkey text default null, p_limit int default 30) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'days', greatest(1, least(coalesce(p_days, 7), 90)),
    'total', (select count(*) from _trade_sales(p_days)),
    'items', (select coalesce(jsonb_agg(x order by (x->>'n')::int desc, x->>'last_at' desc), '[]'::jsonb) from (
      select jsonb_build_object('kind', kind, 'id', item_id, 'gkey', max(gkey), 'n', count(*), 'buy_now', count(*) filter (where buy_now),
        'drink', round(percentile_cont(0.5) within group (order by drinks) filter (where drinks > 0 and gold = 0))::bigint,
        'gold', round(percentile_cont(0.5) within group (order by gold) filter (where gold > 0 and drinks = 0))::bigint,
        'last_at', max(at),
        'last', (select jsonb_build_object('drinks', s2.drinks, 'gold', s2.gold, 'buy_now', s2.buy_now) from _trade_sales(p_days) s2 where s2.kind = s.kind and s2.item_id = s.item_id order by s2.at desc limit 1)) x
      from _trade_sales(p_days) s
      where (coalesce(p_kind, 'all') = 'all' or kind = p_kind) and (p_gkey is null or gkey = p_gkey)
      group by kind, item_id
      order by count(*) desc, max(at) desc
      limit greatest(1, least(coalesce(p_limit, 30), 100))) q));
end $$;

revoke all on function public._trade_sales(int), public._trade_stats(text, text, int) from public, anon, authenticated;
revoke all on function public.trade_price_history(text, text), public.trade_price_board(int, text, text, int) from public, anon;
grant execute on function public.trade_price_history(text, text), public.trade_price_board(int, text, text, int) to authenticated;
notify pgrst, 'reload schema';
