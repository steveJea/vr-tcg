-- ===== 거래소 개편 3/4: 지정 거래 (닉네임으로 상대 찾기 → 그 사람만 받을 수 있는 거래 + 우편 알림) =====
-- 선행: trade_board.sql · trade_admin.sql · trade_buynow_search.sql · trade_wanted.sql. 여러 번 실행해도 안전. 지우는 것 없음 (열 추가 · 트리거 · 함수 추가/교체만)
-- 흐름: 보내는 사람 = 판매 글(물건 보관, 없어도 됨) + 드링크(물건 없으면 필수, 보관) + 원하는 물건 → 받는 사람에게 우편 → 받는 사람이 원하는 물건을 내고 '수락' 한 번에 끝
--  * 받는 사람도 같은 규칙: Lv.20 · 가입 7일 · 하루 거래 5번 · 같은 상대 7일 3번 · 하루 드링크 보내기/받기 한도 (기존 함수·트리거가 그대로 검사)
--  * 지정 글은 게시판·검색에 보내는 사람·받는 사람에게만 보임. 다른 사람은 제안 불가 (트리거)
--  * 보낸 드링크: 거래 완료 → 받는 사람에게 (10% 올림 소각, 재화 수수료와 같음) / 내림·만료·거절 → 보낸 사람에게 그대로 환불 (트리거)
--  * 거래 기록(trade_log.seller_gave)에 보낸 드링크도 남김 → 시세·관리자 화면·의심 표시 그대로

-- 0) 드링크 한도 해제 (형님 결정 2026-11-04): 하루 보내기·받기 · 보관 한도를 사실상 무제한으로 (값만 바꿈, 다시 돌려도 같음)
update public.trade_config set val = 2000000000 where key in ('daily_drink_send', 'daily_drink_recv', 'escrow_max_drinks') and val <> 2000000000;

alter table public.trade_listings add column if not exists target uuid references auth.users(id) on delete cascade;
alter table public.trade_listings add column if not exists give_drinks int not null default 0 check (give_drinks >= 0);
create index if not exists trade_listings_target on public.trade_listings (target, status) where target is not null;

-- 1) 닉네임으로 상대 찾기 (앞부분 일치, 최대 10명, 나 제외)
create or replace function public.trade_user_find(p_q text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); q text := btrim(coalesce(p_q, ''));
begin
  if uid is null then raise exception 'login required'; end if;
  if char_length(q) < 1 then return jsonb_build_object('ok', true, 'users', '[]'::jsonb); end if;
  q := replace(replace(replace(left(q, 20), '\', '\\'), '%', '\%'), '_', '\_');
  return jsonb_build_object('ok', true, 'users', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nick', p.nickname) order by (p.nickname = btrim(p_q)) desc, p.nickname), '[]'::jsonb)
    from (select id, nickname from profiles where id <> uid and nickname ilike q || '%' order by (nickname = btrim(p_q)) desc, nickname limit 10) p));
end $$;

-- 2) 지정 거래 보내기
create or replace function public.trade_direct_list(p_target uuid, p_cards text[], p_gear bigint[], p_drinks int default 0, p_want text default '', p_want_ids jsonb default '[]'::jsonb, p_msg text default '') returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d int := coalesce(p_drinks, 0); r jsonb; lid bigint; nick text; msg text := left(btrim(coalesce(p_msg, '')), 200); l trade_listings;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_target is null or p_target = uid or not exists (select 1 from profiles where id = p_target) then raise exception 'invalid target'; end if;
  if d < 0 then raise exception 'invalid amount'; end if;
  begin perform _trade_gate(p_target); exception when others then raise exception 'target cannot trade'; end;
  if (select count(*) from trade_listings where seller = uid and target = p_target and status = 'open') >= 3 then raise exception 'too many direct'; end if;
  if d > 0 and _trade_drinks_today(uid, 'send') + d > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
  if d > _trade_cfg('escrow_max_drinks') then raise exception 'escrow limit'; end if;
  if coalesce(cardinality(p_cards), 0) + coalesce(cardinality(p_gear), 0) > 0 then
    r := trade_list3(p_cards, p_gear, p_want, null, null, p_want_ids);   -- 물건 보관 · 레벨/가입일 · 열린 글 수 · 최대 5개 검사 그대로
  else
    -- 드링크만: 드링크 > 0 + 원하는 물건 1개 이상 필수 (그냥 주는 선물 거래 방지)
    if d <= 0 then raise exception 'nothing to trade'; end if;
    if jsonb_array_length(_trade_want_ids(p_want_ids)) = 0 then raise exception 'want required'; end if;
    perform _trade_gate(uid); perform _trade_lock_users(array[uid]);
    if (select count(*) from trade_listings where seller = uid and status = 'open') >= _trade_cfg('max_open_listings') then raise exception 'too many listings'; end if;
    insert into trade_listings (seller, want, cards, gear, want_ids, expires_at)
      values (uid, left(coalesce(btrim(p_want), ''), 100), '[]'::jsonb, '[]'::jsonb, _trade_want_ids(p_want_ids), now() + make_interval(hours => _trade_cfg('listing_hours'))) returning id into lid;
    r := jsonb_build_object('ok', true, 'listing_id', lid);
  end if;
  lid := (r->>'listing_id')::bigint;
  update trade_listings set target = p_target, give_drinks = d where id = lid and seller = uid returning * into l;
  if d > 0 then perform _item_add(uid, 'drink', -d, 0, 'trade_escrow', null, jsonb_build_object('listing', lid, 'direct', true)); end if;   -- 거래 가능 드링크 부족하면 전체 취소
  select nickname into nick from profiles where id = uid;
  insert into player_mail (user_id, kind, payload, reason, title, body, expires_at)
  values (p_target, 'msg', '{}'::jsonb, 'trade_direct', '🤝 ' || coalesce(nick, '플레이어') || '님의 지정 거래 제안',
          coalesce(nullif(msg, '') || E'\n\n', '') || '거래소 → 내 거래 → 받은 지정 거래에서 확인하고 수락할 수 있어요. (#' || lid || ')', l.expires_at);
  return r || jsonb_build_object('target', p_target, 'give_drinks', d);
end $$;

-- 3) 받은 지정 거래 목록 (받는 사람)
create or replace function public.trade_direct_inbox() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true, 'listings', (select coalesce(jsonb_agg(_trade_listing_json(l, uid) order by l.id desc), '[]'::jsonb)
    from (select * from trade_listings where target = uid and status = 'open' and expires_at > now() order by id desc limit 30) l));
end $$;

-- 4) 수락 (받는 사람: 원하는 물건·재화를 내고 바로 완료). 재화 범위·하루 한도·같은 상대 한도는 기존 제안/수락 그대로
create or replace function public.trade_direct_accept(p_listing bigint, p_cards text[], p_gear bigint[], p_drinks int default 0, p_gold bigint default 0) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; r jsonb; o bigint;
begin
  perform _trade_gate(uid);
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.target is distinct from uid then raise exception 'listing not found'; end if;
  if l.status = 'open' and l.expires_at <= now() then perform _trade_close_listing(l.id, 'expired'); return jsonb_build_object('ok', false, 'reason', 'listing closed'); end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  perform _trade_lock_users(array[uid, l.seller] || array(select offerer from trade_offers where listing_id = l.id and status = 'pending'));
  select id into o from trade_offers where listing_id = l.id and offerer = uid and status = 'pending';
  if o is not null then perform _trade_refund_offer(o, 'cancelled'); end if;   -- 예전에 넣어 둔 제안이 있으면 돌려주고 새로
  r := trade_offer(l.id, p_cards, p_gear, coalesce(p_drinks, 0), coalesce(p_gold, 0));
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  return _trade_accept_core(l.id, (r->>'offer_id')::bigint, l.seller, false) || jsonb_build_object('got_drinks', l.give_drinks - ceil(l.give_drinks * _trade_cfg('fee_pct') / 100.0)::int);
end $$;

-- 5) 거절 (받는 사람) → 보낸 사람 물건·드링크 환불 + 우편
create or replace function public.trade_direct_decline(p_listing bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; nick text;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.target is distinct from uid then raise exception 'listing not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  perform _trade_close_listing(l.id, 'cancelled');
  select nickname into nick from profiles where id = uid;
  insert into player_mail (user_id, kind, payload, reason, title, body)
  values (l.seller, 'msg', '{}'::jsonb, 'trade_direct', '🙅 ' || coalesce(nick, '플레이어') || '님이 지정 거래를 거절했어요', '보낸 물건과 드링크는 그대로 돌려받았어요. (#' || l.id || ')');
  return jsonb_build_object('ok', true);
end $$;

-- 6) 트리거: 지정 글엔 받는 사람만 제안
create or replace function public._trade_direct_offer_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select target into t from trade_listings where id = new.listing_id;
  if t is not null and new.offerer <> t then raise exception 'direct only'; end if;
  return new;
end $$;
drop trigger if exists trade_direct_offer_guard on public.trade_offers;
create trigger trade_direct_offer_guard before insert on public.trade_offers for each row execute function public._trade_direct_offer_guard();

-- 7) 트리거: 보낸 드링크 정산 (완료 → 받는 사람 / 그 밖 종료 → 보낸 사람)
create or replace function public._trade_direct_settle() returns trigger language plpgsql security definer set search_path = public as $$
declare buyer uuid; fee int;
begin
  if new.give_drinks <= 0 or old.status <> 'open' or new.status = 'open' then return new; end if;
  if new.status = 'done' then
    select offerer into buyer from trade_offers where id = new.offer_id;
    fee := ceil(new.give_drinks * _trade_cfg('fee_pct') / 100.0)::int;
    perform _item_add(buyer, 'drink', new.give_drinks - fee, 0, 'trade_recv', null, jsonb_build_object('listing', new.id, 'fee', fee, 'direct', true));
  else
    perform _item_add(new.seller, 'drink', new.give_drinks, 0, 'trade_refund', null, jsonb_build_object('listing', new.id, 'direct', true));
  end if;
  return new;
end $$;
drop trigger if exists trade_direct_settle on public.trade_listings;
create trigger trade_direct_settle after update of status on public.trade_listings for each row execute function public._trade_direct_settle();

-- 8) 트리거: 거래 기록에 보낸 드링크 남기기 + 한도 (보낸 사람 보내기 · 받는 사람 받기)
create or replace function public._trade_direct_log() returns trigger language plpgsql security definer set search_path = public as $$
declare d int;
begin
  select give_drinks into d from trade_listings where id = new.listing_id;
  if coalesce(d, 0) > 0 then
    if _trade_drinks_today(new.seller, 'send') + d > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
    if _trade_drinks_today(new.buyer, 'recv') + d > _trade_cfg('daily_drink_recv') then raise exception 'drink recv limit'; end if;
    new.seller_gave := new.seller_gave || jsonb_build_object('drinks', d);
    new.fees := new.fees || jsonb_build_object('direct_drinks', ceil(d * _trade_cfg('fee_pct') / 100.0)::int);
  end if;
  return new;
end $$;
drop trigger if exists trade_direct_log on public.trade_log;
create trigger trade_direct_log before insert on public.trade_log for each row execute function public._trade_direct_log();

-- 9) 게시판·검색: 지정 글은 당사자에게만 (응답 모양 그대로 + direct·give_drinks·to_me·seller_name·target_name)
create or replace function public._trade_listing_json(l trade_listings, uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
    'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
    'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
    'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
    'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
    'buy_drinks', l.buy_drinks, 'want_ids', l.want_ids,
    'direct', l.target is not null, 'give_drinks', l.give_drinks, 'to_me', l.target = uid,
    'seller_name', case when l.target is not null then (select nickname from profiles where id = l.seller) end,
    'target_name', case when l.target is not null and l.seller = uid then (select nickname from profiles where id = l.target) end, 'buy_gold', l.buy_gold,
    'expires_at', l.expires_at, 'created_at', l.created_at) $$;

create or replace function public.trade_board(p_limit int default 50, p_before bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true, 'listings', (select coalesce(jsonb_agg(_trade_listing_json(l, uid) order by l.id desc), '[]'::jsonb)
    from (select l.* from trade_listings l where status = 'open' and expires_at > now() and (target is null or target = uid or seller = uid) and (p_before is null or id < p_before) order by id desc limit greatest(1, least(p_limit, 100))) l));
end $$;

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
       and (l.target is null or l.target = uid or l.seller = uid)
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
       and (l.target is null or l.target = uid or l.seller = uid)
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


revoke all on function public._trade_listing_json(trade_listings, uuid), public._trade_direct_offer_guard(), public._trade_direct_settle(), public._trade_direct_log() from public, anon, authenticated;
revoke all on function public.trade_user_find(text), public.trade_direct_list(uuid, text[], bigint[], int, text, jsonb, text), public.trade_direct_inbox(),
  public.trade_direct_accept(bigint, text[], bigint[], int, bigint), public.trade_direct_decline(bigint) from public, anon;
grant execute on function public.trade_user_find(text), public.trade_direct_list(uuid, text[], bigint[], int, text, jsonb, text), public.trade_direct_inbox(),
  public.trade_direct_accept(bigint, text[], bigint[], int, bigint), public.trade_direct_decline(bigint) to authenticated;
notify pgrst, 'reload schema';
