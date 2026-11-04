-- ===== 거래소 개편 2/4: 원하는 물건 지정 (want_ids) + '내 물건을 원하는 글' 검색 =====
-- 선행: trade_board.sql · trade_admin.sql · trade_buynow_search.sql. 여러 번 실행해도 안전. 지우는 것 없음 (열 추가 · 함수 추가/교체만)
-- 1) 판매 글에 원하는 물건 목록(최대 5): [{"k":"card"|"gear","id":"..."}] — 표시·검색용 (제안을 강제하지 않음, 판매자가 고름)
-- 2) trade_list3: trade_list2 + 원하는 물건. 3) 게시판·검색 응답에 want_ids 포함 (_trade_listing_json 교체, 모양 그대로 + 필드 1개)
-- 4) trade_search2: trade_search + p_want_in (내가 가진 인재 id · 장비 def id 중 하나라도 원하는 글만)

alter table public.trade_listings add column if not exists want_ids jsonb not null default '[]'::jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'trade_listings_want_ids_arr') then
    alter table public.trade_listings add constraint trade_listings_want_ids_arr check (jsonb_typeof(want_ids) = 'array' and jsonb_array_length(want_ids) <= 5);
  end if;
end $$;
create index if not exists trade_listings_want_ids on public.trade_listings using gin (want_ids jsonb_path_ops) where status = 'open';

-- 원하는 물건 검사: 배열 · 5개 이하 · k 는 card/gear · id 는 1~40자 · 중복 제거
create or replace function public._trade_want_ids(p jsonb) returns jsonb language plpgsql immutable as $$
declare res jsonb := '[]'::jsonb; e jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'array' then return res; end if;
  if jsonb_array_length(p) > 5 then raise exception 'too many wants'; end if;
  for e in select x from jsonb_array_elements(p) x loop
    if jsonb_typeof(e) <> 'object' or coalesce(e->>'k', '') not in ('card', 'gear') or char_length(coalesce(e->>'id', '')) not between 1 and 40 then raise exception 'invalid want'; end if;
    if not res @> jsonb_build_array(jsonb_build_object('k', e->>'k', 'id', e->>'id')) then res := res || jsonb_build_array(jsonb_build_object('k', e->>'k', 'id', e->>'id')); end if;
  end loop;
  return res;
end $$;

create or replace function public.trade_list3(p_cards text[], p_gear bigint[], p_want text default '', p_buy_drinks int default null, p_buy_gold bigint default null, p_want_ids jsonb default '[]'::jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb := _trade_want_ids(p_want_ids); r jsonb;
begin
  r := trade_list2(p_cards, p_gear, p_want, p_buy_drinks, p_buy_gold);
  update trade_listings set want_ids = w where id = (r->>'listing_id')::bigint and seller = auth.uid();
  return r || jsonb_build_object('want_ids', w);
end $$;

create or replace function public._trade_listing_json(l trade_listings, uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
    'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
    'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
    'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
    'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
    'buy_drinks', l.buy_drinks, 'want_ids', l.want_ids, 'buy_gold', l.buy_gold,
    'expires_at', l.expires_at, 'created_at', l.created_at) $$;

create or replace function public.trade_search2(p_q text default '', p_card_ids text[] default null, p_type text default 'all', p_gkeys text[] default null,
    p_buy_only boolean default false, p_sort text default 'new', p_limit int default 30, p_offset int default 0, p_want_in text[] default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := nullif(btrim(coalesce(p_q, '')), ''); lim int := greatest(1, least(coalesce(p_limit, 30), 50)); off int := greatest(0, least(coalesce(p_offset, 0), 2000)); res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  if q is not null then q := '%' || replace(replace(replace(left(q, 30), '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  perform trade_expire_due(10);
  with base as (
    select l.*, (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending') as n_off,
           coalesce(l.buy_drinks::numeric, l.buy_gold::numeric / 100) as price_key   -- 골드 100 = 드링크 1 로 대충 비교 (정렬용)
      from trade_listings l
     where l.status = 'open' and l.expires_at > now()
       and (coalesce(p_type, 'all') = 'all' or (p_type = 'card' and jsonb_array_length(l.cards) > 0) or (p_type = 'gear' and jsonb_array_length(l.gear) > 0))
       and (p_gkeys is null or cardinality(p_gkeys) = 0 or exists (select 1 from jsonb_array_elements(l.cards || l.gear) x where x->>'gkey' = any(p_gkeys)))
       and (p_want_in is null or cardinality(p_want_in) = 0 or exists (select 1 from jsonb_array_elements(l.want_ids) w where w->>'id' = any(p_want_in)))
       and (not coalesce(p_buy_only, false) or l.buy_drinks is not null or l.buy_gold is not null)
       and ((q is null and (p_card_ids is null or cardinality(p_card_ids) = 0))
            or (p_card_ids is not null and cardinality(p_card_ids) > 0 and exists (select 1 from jsonb_array_elements(l.cards) x where x->'card'->>'id' = any(p_card_ids)))
            or (q is not null and exists (select 1 from jsonb_array_elements(l.gear) x join gear_defs d on d.id = (x->'row'->>'def_id') where d.name ilike q)))
  ), page as (
    select id, row_number() over (order by
              case when p_sort = 'end' then extract(epoch from expires_at) end asc nulls last,
              case when p_sort = 'hot' then n_off end desc nulls last,
              case when p_sort = 'price' then price_key end asc nulls last,
              id desc) as ord
      from base
  )
  select jsonb_build_object('ok', true, 'offset', off,
      'more', exists (select 1 from page where ord = off + lim + 1),
      'listings', coalesce((select jsonb_agg(_trade_listing_json(t, uid) order by p.ord) from page p join trade_listings t on t.id = p.id where p.ord > off and p.ord <= off + lim), '[]'::jsonb))
    into res;
  return res;
end $$;


revoke all on function public._trade_want_ids(jsonb), public._trade_listing_json(trade_listings, uuid) from public, anon, authenticated;
revoke all on function public.trade_list3(text[], bigint[], text, int, bigint, jsonb), public.trade_search2(text, text[], text, text[], boolean, text, int, int, text[]) from public, anon;
grant execute on function public.trade_list3(text[], bigint[], text, int, bigint, jsonb), public.trade_search2(text, text[], text, text[], boolean, text, int, int, text[]) to authenticated;
notify pgrst, 'reload schema';
