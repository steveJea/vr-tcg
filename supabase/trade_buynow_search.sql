-- ===== 거래소 5단계: 즉시 구매(고정가) + 서버 검색(trade_search) =====
-- 선행: trade_board.sql · trade_admin.sql. 여러 번 실행해도 안전. 지우는 것 없음 (열 추가 · 함수 추가/교체만)
-- 1) 판매 글에 '즉시 구매가'(선택): 드링크 또는 골드 중 하나. 등급별 가격 범위(trade_band)·골드 규칙은 제안과 똑같이 검사
-- 2) trade_buy: 그 가격 그대로 바로 구매 → 내부적으로 '재화 제안 + 판매자 수락'을 한 번에 (수수료 10% 소각·하루 한도·같은 상대 한도·드링크 이동 한도 그대로)
--    동시 구매: 글 행을 먼저 잠그고(for update) 관련 유저를 uuid 순서로 잠금 → 먼저 온 한 명만 성공, 나머지는 '이미 끝난 글'
--    만료: 만료 시각이 지났으면 그 자리에서 만료 처리(보관물 환불) 후 실패 응답. 가격이 화면과 다르면 'price changed'
-- 3) trade_search: 게시판 전체에서 이름(인재는 화면이 이름→id 로 바꿔서 전달, 장비는 이름 일부)·종류·등급·즉시 구매만·정렬·페이지
-- 4) 시세(6단계)용: 거래 기록(trade_log)에 즉시 구매 여부(buy_now)와 시간 색인 추가. 판매가는 이미 buyer_gave(드링크·골드)에 기록됨

-- 1) 열 추가 --------------------------------------------------------------------------
alter table public.trade_listings add column if not exists buy_drinks int check (buy_drinks is null or buy_drinks > 0);
alter table public.trade_listings add column if not exists buy_gold bigint check (buy_gold is null or buy_gold > 0);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'trade_listings_buy_one') then
    alter table public.trade_listings add constraint trade_listings_buy_one check (buy_drinks is null or buy_gold is null);
  end if;
end $$;
alter table public.trade_log add column if not exists buy_now boolean not null default false;
create index if not exists trade_log_time on public.trade_log (created_at desc);
create index if not exists trade_listings_open_id on public.trade_listings (id desc) where status = 'open';

-- 2) 수락 본체 (판매자 지정). trade_accept 는 이걸 부르는 얇은 껍데기로 교체 (동작 같음)
create or replace function public._trade_accept_core(p_listing bigint, p_offer bigint, p_seller uuid, p_buy_now boolean default false) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := p_seller; l trade_listings; o trade_offers; pct int := _trade_cfg('fee_pct'); fd int := 0; fg bigint := 0; sfee bigint := 0;
        it jsonb; m1 int; m2 int; sig jsonb := '[]'::jsonb; s jsonb; oid bigint; n int := 0; day_start timestamptz := ((now() at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul');
begin
  if uid is null then raise exception 'login required'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.seller <> uid then raise exception 'listing not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  if l.expires_at <= now() then perform _trade_close_listing(l.id, 'expired'); return jsonb_build_object('ok', false, 'reason', 'listing closed'); end if;
  select * into o from trade_offers where id = p_offer and listing_id = l.id;
  if o.id is null then raise exception 'offer not found'; end if;
  perform _trade_lock_users(array[uid] || array(select offerer from trade_offers where listing_id = l.id and status = 'pending'));
  select * into o from trade_offers where id = p_offer for update;
  if o.status <> 'pending' then raise exception 'offer closed'; end if;
  -- 하루 한도 · 같은 상대 반복
  if (select count(*) from trade_log where (seller = uid or buyer = uid) and created_at >= day_start) >= _trade_cfg('daily_trades')
     or (select count(*) from trade_log where (seller = o.offerer or buyer = o.offerer) and created_at >= day_start) >= _trade_cfg('daily_trades') then raise exception 'daily trade limit'; end if;
  if (select count(*) from trade_log where ((seller = uid and buyer = o.offerer) or (seller = o.offerer and buyer = uid)) and created_at > now() - interval '7 days') >= _trade_cfg('same_partner_7d') then raise exception 'same partner limit'; end if;
  -- 물건끼리만: 판매자도 받는 물건 등급별 고정 골드
  if o.drinks = 0 and o.gold = 0 then
    select coalesce(sum(b.fix_fee), 0) into sfee from jsonb_array_elements(o.cards || o.gear) x join trade_band b on b.gkey = x->>'gkey';
    if sfee > 0 then perform _wallet_add(uid, jsonb_build_object('gold', -sfee), 'trade_fee'); end if;
  end if;
  update trade_offers set status = 'accepted', closed_at = now() where id = o.id;
  update trade_listings set status = 'done', closed_at = now(), offer_id = o.id where id = l.id;
  -- 물건 교환
  perform _trade_give_cards(o.offerer, l.cards, true);
  perform _trade_give_cards(uid, o.cards, true);
  m1 := _trade_give_gear(o.offerer, l.gear, true);
  m2 := _trade_give_gear(uid, o.gear, true);
  for it in select x from jsonb_array_elements(l.cards) x loop
    s := _trade_sigil_move(uid, o.offerer, it->'card'->>'id'); if s is not null then sig := sig || jsonb_build_array(s || jsonb_build_object('to', 'buyer')); end if;
  end loop;
  for it in select x from jsonb_array_elements(o.cards) x loop
    s := _trade_sigil_move(o.offerer, uid, it->'card'->>'id'); if s is not null then sig := sig || jsonb_build_array(s || jsonb_build_object('to', 'seller')); end if;
  end loop;
  -- 재화: 판매자에게 (10% 올림 소각)
  if o.drinks > 0 then fd := ceil(o.drinks * pct / 100.0)::int; perform _item_add(uid, 'drink', o.drinks - fd, 0, 'trade_recv', null, jsonb_build_object('offer', o.id, 'fee', fd)); end if;
  if o.gold > 0 then fg := ceil(o.gold * pct / 100.0)::bigint; perform _wallet_add(uid, jsonb_build_object('gold', o.gold - fg), 'trade_recv'); end if;
  insert into trade_log (listing_id, offer_id, seller, buyer, seller_gave, buyer_gave, fees)
  values (l.id, o.id, uid, o.offerer, jsonb_build_object('cards', l.cards, 'gear', l.gear),
          jsonb_build_object('cards', o.cards, 'gear', o.gear, 'drinks', o.drinks, 'gold', o.gold),
          jsonb_build_object('drinks', fd, 'gold', fg, 'fix_buyer', o.fee_gold, 'fix_seller', sfee, 'mailed', m1 + m2, 'sigils', sig));
  if p_buy_now then update trade_log set buy_now = true where offer_id = o.id; end if;
  -- 나머지 제안 환불
  for oid in select id from trade_offers where listing_id = l.id and status = 'pending' order by id loop
    if _trade_refund_offer(oid, 'refunded') then n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'buy_now', p_buy_now, 'mailed_buyer', m1, 'drinks', o.drinks - fd, 'gold', o.gold - fg, 'fee_drinks', fd, 'fee_gold', fg + sfee, 'refunded', n, 'mailed', m2, 'sigils', sig);
end $$;


create or replace function public.trade_accept(p_listing bigint, p_offer bigint) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return _trade_accept_core(p_listing, p_offer, auth.uid(), false);
end $$;

-- 3) 즉시 구매가와 함께 올리기 (가격 없이 부르면 기존 trade_list 와 같음)
create or replace function public.trade_list2(p_cards text[], p_gear bigint[], p_want text default '', p_buy_drinks int default null, p_buy_gold bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; l trade_listings;
begin
  p_buy_drinks := nullif(coalesce(p_buy_drinks, 0), 0); p_buy_gold := nullif(coalesce(p_buy_gold, 0), 0);
  if p_buy_drinks < 0 or p_buy_gold < 0 then raise exception 'invalid amount'; end if;
  if p_buy_drinks is not null and p_buy_gold is not null then raise exception 'buy one currency'; end if;
  r := trade_list(p_cards, p_gear, p_want);
  if p_buy_drinks is not null or p_buy_gold is not null then
    select * into l from trade_listings where id = (r->>'listing_id')::bigint for update;
    perform _trade_check_price(l.cards || l.gear, '[]'::jsonb, coalesce(p_buy_drinks, 0), coalesce(p_buy_gold, 0));   -- 범위 밖이면 전체 취소(보관도 되돌림)
    update trade_listings set buy_drinks = p_buy_drinks, buy_gold = p_buy_gold where id = l.id;
  end if;
  return r || jsonb_build_object('buy_drinks', p_buy_drinks, 'buy_gold', p_buy_gold);
end $$;

-- 4) 즉시 구매
create or replace function public.trade_buy(p_listing bigint, p_drinks int default 0, p_gold bigint default 0) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; r jsonb;
begin
  perform _trade_gate(uid);
  select * into l from trade_listings where id = p_listing for update;   -- 동시 구매·수락·내리기와 줄 세움
  if l.id is null then raise exception 'listing not found'; end if;
  if l.status = 'open' and l.expires_at <= now() then perform _trade_close_listing(l.id, 'expired'); return jsonb_build_object('ok', false, 'reason', 'listing closed'); end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  if l.seller = uid then raise exception 'own listing'; end if;
  if l.buy_drinks is null and l.buy_gold is null then raise exception 'no buy price'; end if;
  if coalesce(l.buy_drinks, 0) <> coalesce(p_drinks, 0) or coalesce(l.buy_gold, 0) <> coalesce(p_gold, 0) then raise exception 'price changed'; end if;
  if exists (select 1 from trade_offers where listing_id = l.id and offerer = uid and status = 'pending') then raise exception 'already offered'; end if;
  perform _trade_lock_users(array[uid, l.seller] || array(select offerer from trade_offers where listing_id = l.id and status = 'pending'));   -- 한 번에 uuid 순서로
  r := trade_offer(l.id, '{}'::text[], '{}'::bigint[], coalesce(l.buy_drinks, 0), coalesce(l.buy_gold, 0));   -- 구매자 재화 보관 (한도·범위 검사 그대로)
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  return _trade_accept_core(l.id, (r->>'offer_id')::bigint, l.seller, true);   -- 실패하면 위 보관까지 전부 되돌아감
end $$;

-- 5) 게시판·검색에 즉시 구매가 포함 (게시판 응답 모양은 그대로 + buy_drinks/buy_gold)
create or replace function public._trade_listing_json(l trade_listings, uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
    'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
    'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
    'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
    'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
    'buy_drinks', l.buy_drinks, 'buy_gold', l.buy_gold,
    'expires_at', l.expires_at, 'created_at', l.created_at) $$;

create or replace function public.trade_board(p_limit int default 50, p_before bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true, 'listings', (select coalesce(jsonb_agg(_trade_listing_json(l, uid) order by l.id desc), '[]'::jsonb)
    from (select * from trade_listings where status = 'open' and expires_at > now() and (p_before is null or id < p_before) order by id desc limit greatest(1, least(p_limit, 100))) l));
end $$;

-- p_type: all|card|gear · p_gkeys: trade_band 키(card_nr, card_hr, …, gear_low …) 중 하나라도 · p_card_ids: 이름으로 찾은 인재 id (화면이 변환)
-- p_q: 장비 이름 일부 (인재 이름은 DB 에 없어서 p_card_ids 로) · p_buy_only: 즉시 구매만 · p_sort: new|end|hot|price · p_offset 페이지
create or replace function public.trade_search(p_q text default '', p_card_ids text[] default null, p_type text default 'all', p_gkeys text[] default null,
    p_buy_only boolean default false, p_sort text default 'new', p_limit int default 30, p_offset int default 0) returns jsonb language plpgsql security definer set search_path = public as $$
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

-- 6) 권한 ------------------------------------------------------------------------------
revoke all on function public._trade_accept_core(bigint, bigint, uuid, boolean), public._trade_listing_json(trade_listings, uuid) from public, anon, authenticated;
revoke all on function public.trade_list2(text[], bigint[], text, int, bigint), public.trade_buy(bigint, int, bigint),
  public.trade_search(text, text[], text, text[], boolean, text, int, int), public.trade_accept(bigint, bigint), public.trade_board(int, bigint) from public, anon;
grant execute on function public.trade_list2(text[], bigint[], text, int, bigint), public.trade_buy(bigint, int, bigint),
  public.trade_search(text, text[], text, text[], boolean, text, int, int), public.trade_accept(bigint, bigint), public.trade_board(int, bigint) to authenticated;
notify pgrst, 'reload schema';
