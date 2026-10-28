-- ===== 거래 PR3: 거래 게시판 (서버) =====
-- 선행: trade_origin(_v2).sql · trade_drink.sql · gear_v1/gear_drops.sql · gear_sigil.sql · phaseE_1/2.sql. 여러 번 실행해도 안전. 화면은 다음 PR
-- 흐름: 판매 글(인재·장비 1~5개, 올리는 순간 보관) → 제안(인재·장비 0~5 + 드링크 + 골드, 바로 보관) → 판매자가 하나 수락(한 번에 교환)
--       거절(하나·여러 개·조건 아래 전부) · 제안 취소 · 글 내리기 · 72시간 만료 → 보관된 것 즉시 원래 주인에게 (장비는 가방 꽉 차면 우편함)
-- 보관 방식: 인재는 owned[] 에서 빼서 글/제안 행에 그대로 저장(레벨·성장 유지), 장비는 player_gear 행을 빼서 저장(같은 id 로 복구)
--            드링크는 거래 가능분에서 차감, 골드는 지갑에서 차감 → 끝나면 상대에게 주거나 돌려줌. 보관 중인 물건은 게임에서 아예 안 보임(=쓸 수 없음)
-- 수수료(소각): 받는 재화의 10% 올림. 물건끼리만이면 양쪽이 각자 받는 물건 등급별 고정 골드 (제안자 몫은 제안할 때 미리 보관)
-- 증표: 넘기는 인재가 그 계정의 마지막 같은 인재면 증표(단계·투입 조각)도 함께 넘어감. 받는 쪽에 이미 증표가 있으면 높은 쪽을 남기고 낮은 쪽 투입 조각은 조각으로 돌려줌
-- 장착 장비: 인재를 올릴 때 그 계정의 마지막 같은 인재면 장착 장비 자동 해제 (장비는 원래 주인 가방에)

-- 1) 조절표 (임시값) -------------------------------------------------------------
create table if not exists public.trade_config (key text primary key, val int not null, note text);
insert into public.trade_config (key, val, note) values
  ('listing_hours', 72, '판매 글 유지 시간'),
  ('max_items', 5, '한쪽 물건 최대 개수'),
  ('max_open_listings', 5, '1인 열린 판매 글'),
  ('max_open_offers', 10, '1인 대기 중 제안'),
  ('max_pending_per_listing', 100, '한 글의 대기 제안'),
  ('reoffer_cooldown_hours', 24, '거절 후 같은 글 다시 제안 대기'),
  ('bulk_max', 100, '한 번에 거절 최대'),
  ('fee_pct', 10, '받는 재화 수수료 %'),
  ('escrow_max_drinks', 20000, '1인 보관 드링크 한도'),
  ('escrow_max_gold', 2000000, '1인 보관 골드 한도'),
  ('daily_trades', 5, '하루 완료 거래 (KST)'),
  ('same_partner_7d', 3, '같은 상대 7일 거래'),
  ('resale_hours', 72, '거래로 받은 물건 다시 올리기 대기'),
  ('min_level', 20, '계정 레벨 하한'),
  ('min_account_days', 7, '가입 후 일수')
on conflict (key) do nothing;

-- 등급별 1개당 가격 범위 + 물건끼리 거래 고정 골드 수수료. g_min/g_max null = 골드 불가
create table if not exists public.trade_band (
  gkey text primary key, label text not null, d_min int not null, d_max int not null, g_min int, g_max int, fix_fee int not null
);
insert into public.trade_band values
  ('card_nr',  '인재 N·R',   1,    50,  1000,  20000,   500),
  ('card_hr',  '인재 HR',    5,   200,  5000, 100000,  1000),
  ('card_sr',  '인재 SR',   20,  1000,  null,   null,  3000),
  ('card_ur',  '인재 UR',  100,  3000,  null,   null, 10000),
  ('card_mlr', '인재 MR·LR', 300, 10000, null,  null, 10000),
  ('gear_low', '장비 낡은~고급', 1, 50,  500,  20000,   500),
  ('gear_rare','장비 희귀',  5,   200,  5000,  80000,  1000),
  ('gear_hero','장비 영웅', 20,  1000,  null,   null,  3000)
on conflict (gkey) do nothing;

do $$ declare t text; begin
  foreach t in array array['trade_config', 'trade_band'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- 2) 글·제안·기록 ------------------------------------------------------------------
-- cards: [{card: owned 항목, gkey}] · gear: [{row: player_gear 행, gkey}]
create table if not exists public.trade_listings (
  id         bigint generated always as identity primary key,
  seller     uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'open' check (status in ('open', 'done', 'cancelled', 'expired')),
  want       text not null default '' check (char_length(want) <= 100),
  cards      jsonb not null default '[]'::jsonb,
  gear       jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at  timestamptz,
  offer_id   bigint
);
create index if not exists trade_listings_open on public.trade_listings (expires_at) where status = 'open';
create index if not exists trade_listings_seller on public.trade_listings (seller, status);

create table if not exists public.trade_offers (
  id         bigint generated always as identity primary key,
  listing_id bigint not null references public.trade_listings(id) on delete cascade,
  offerer    uuid not null references auth.users(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled', 'refunded')),
  cards      jsonb not null default '[]'::jsonb,
  gear       jsonb not null default '[]'::jsonb,
  drinks     int not null default 0 check (drinks >= 0),
  gold       bigint not null default 0 check (gold >= 0),
  fee_gold   bigint not null default 0 check (fee_gold >= 0),       -- 물건끼리 거래: 제안자 몫 고정 수수료 (미리 보관)
  created_at timestamptz not null default now(),
  closed_at  timestamptz
);
create index if not exists trade_offers_listing on public.trade_offers (listing_id, status);
create index if not exists trade_offers_offerer on public.trade_offers (offerer, status);
create unique index if not exists trade_offers_one on public.trade_offers (listing_id, offerer) where status = 'pending';

create table if not exists public.trade_log (
  id         bigint generated always as identity primary key,
  listing_id bigint not null, offer_id bigint not null,
  seller     uuid not null, buyer uuid not null,
  seller_gave jsonb not null, buyer_gave jsonb not null,
  fees       jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists trade_log_seller on public.trade_log (seller, created_at desc);
create index if not exists trade_log_buyer on public.trade_log (buyer, created_at desc);

do $$ declare t text; begin
  foreach t in array array['trade_listings', 'trade_offers', 'trade_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- 우편함 장비: 강화 단계(plus)도 받도록 (기존엔 무시됨)
create or replace function public.mail_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; d gear_defs; gid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if ml.kind <> 'gear' then return jsonb_build_object('ok', false, 'reason', 'unsupported'); end if;
  if _gear_bag_full(uid) then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  select * into d from gear_defs where id = ml.payload->>'def_id';
  if d.tier > 5 and coalesce(ml.payload->>'source', '') <> 'event' then return jsonb_build_object('ok', false, 'reason', 'event only'); end if;
  insert into player_gear (user_id, def_id, plus, opts, source, locked)
    values (uid, d.id, least(5, greatest(0, coalesce((ml.payload->>'plus')::int, 0))), coalesce(ml.payload->'opts', _gear_roll_opts(d.id)), 'mail:' || ml.reason, d.tier >= 6) returning id into gid;
  update player_mail set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'gear_id', gid, 'def_id', d.id);
end $$;
revoke all on function public.mail_claim(bigint) from public, anon;
grant execute on function public.mail_claim(bigint) to authenticated;

-- 3) 내부 도우미 ---------------------------------------------------------------------
create or replace function public._trade_cfg(k text) returns int language sql stable security definer set search_path = public as $$
  select val from trade_config where key = k $$;

create or replace function public._trade_card_gkey(p_card text) returns text language sql stable security definer set search_path = public as $$
  select case coalesce((select grade from story_card_pool where id = p_card), 'NORMAL')
    when 'NORMAL' then 'card_nr' when 'RARE' then 'card_nr' when 'HIGH RARE' then 'card_hr'
    when 'SUPER RARE' then 'card_sr' when 'ULTRA RARE' then 'card_ur' else 'card_mlr' end $$;

create or replace function public._trade_gear_gkey(p_tier int) returns text language sql immutable as $$
  select case when p_tier <= 3 then 'gear_low' when p_tier = 4 then 'gear_rare' when p_tier = 5 then 'gear_hero' else null end $$;

-- 관련 유저 잠금 (항상 uuid 순서 → 교착 없음). 글 행 잠금 다음에 호출
create or replace function public._trade_lock_users(p_uids uuid[]) returns void language plpgsql as $$
declare u uuid;
begin
  for u in select distinct x from unnest(p_uids) x where x is not null order by 1 loop
    perform pg_advisory_xact_lock(hashtext('trade:' || u::text));
  end loop;
end $$;

-- 배열에서 uid 빼기 (문자열 또는 {uid:..} 항목)
create or replace function public._trade_strip(a jsonb, u text) returns jsonb language sql immutable as $$
  select case when jsonb_typeof(a) <> 'array' then a else
    coalesce((select jsonb_agg(x order by k) from jsonb_array_elements(a) with ordinality t(x, k)
              where not (x = to_jsonb(u) or (jsonb_typeof(x) = 'object' and x->>'uid' = u))), '[]'::jsonb) end $$;

-- 계정 조건
create or replace function public._trade_gate(p_uid uuid) returns void language plpgsql security definer set search_path = public as $$
declare lv int;
begin
  if p_uid is null then raise exception 'login required'; end if;
  lv := (_player_sync(p_uid)).level;
  if lv < _trade_cfg('min_level') then raise exception 'trade level'; end if;
  if (select created_at from auth.users where id = p_uid) > now() - make_interval(days => _trade_cfg('min_account_days')) then raise exception 'trade account age'; end if;
end $$;

-- 인재 보관: owned 에서 빼고 [{card, gkey}] 반환. 리더·수동 잠금·귀속·재판매 대기 불가. 덱 자동 잠금(dlk)은 덱에서 빼고 진행
create or replace function public._trade_take_cards(p_uid uuid, p_uids text[]) returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; owned jsonb; u text; e jsonb; res jsonb := '[]'::jsonb; cid text; decks jsonb; k int; rs int := _trade_cfg('resale_hours');
begin
  if p_uids is null or cardinality(p_uids) = 0 then return res; end if;
  if (select count(distinct x) from unnest(p_uids) x) <> cardinality(p_uids) then raise exception 'duplicate card'; end if;
  d := _story_lock(p_uid); owned := _story_owned(d);
  foreach u in array p_uids loop
    select x into e from jsonb_array_elements(owned) x where x->>'uid' = u;
    if e is null then raise exception 'card not owned'; end if;
    if u = coalesce(d->>'leader', '') then raise exception 'cannot trade leader'; end if;
    if coalesce((e->>'locked')::boolean, false) and not coalesce((e->>'dlk')::boolean, false) then raise exception 'card locked'; end if;
    if coalesce((e->>'bound')::boolean, true) then raise exception 'card bound'; end if;
    if (e->>'traded_at') is not null and (e->>'traded_at')::bigint > extract(epoch from now()) - rs * 3600 then raise exception 'resale cooldown'; end if;
    owned := _trade_strip(owned, u);
    res := res || jsonb_build_array(jsonb_build_object('card', e - 'locked' - 'dlk' - 'fav', 'gkey', _trade_card_gkey(e->>'id')));
    -- 덱에서 빼기 (스토리 덱 · PvP · 세력전)
    if jsonb_typeof(d->'decks') = 'array' then
      decks := d->'decks';
      for k in 0 .. jsonb_array_length(decks) - 1 loop
        if jsonb_typeof(decks->k->'uids') = 'array' then decks := jsonb_set(decks, array[k::text, 'uids'], _trade_strip(decks->k->'uids', u)); end if;
      end loop;
      d := jsonb_set(d, '{decks}', decks);
    end if;
    update pvp_decks set uids = _trade_strip(uids, u), snap = _trade_strip(snap, u), updated_at = now()
      where user_id = p_uid and (uids @> to_jsonb(array[u]) or exists (select 1 from jsonb_array_elements(snap) s where s->>'uid' = u));
    update war_decks set def1 = _trade_strip(def1, u), def2 = _trade_strip(def2, u), atk1 = _trade_strip(atk1, u), atk2 = _trade_strip(atk2, u), updated_at = now()
      where user_id = p_uid;
    -- 마지막 같은 인재면 장착 장비 해제 (장비는 그대로 내 가방)
    cid := e->>'id';
    if not exists (select 1 from jsonb_array_elements(owned) x where x->>'id' = cid) then
      update player_gear set equipped_card = null where user_id = p_uid and equipped_card = cid;
    end if;
  end loop;
  perform _story_save(p_uid, jsonb_set(d, '{owned}', owned));
  return res;
end $$;

-- 인재 지급 (p_traded = 거래로 받음 → 재판매 대기 표시)
create or replace function public._trade_give_cards(p_uid uuid, p_items jsonb, p_traded boolean) returns void language plpgsql security definer set search_path = public as $$
declare d jsonb; owned jsonb; it jsonb; e jsonb;
begin
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then return; end if;
  d := _story_lock(p_uid); owned := _story_owned(d);
  for it in select x from jsonb_array_elements(p_items) x loop
    e := it->'card';
    if p_traded then e := e || jsonb_build_object('traded_at', extract(epoch from now())::bigint); end if;
    owned := owned || jsonb_build_array(e);
  end loop;
  perform _story_save(p_uid, jsonb_set(d, '{owned}', owned));
end $$;

-- 장비 보관: 잠금·장착·전설 이상·재판매 대기 불가
create or replace function public._trade_take_gear(p_uid uuid, p_ids bigint[]) returns jsonb language plpgsql security definer set search_path = public as $$
declare gid bigint; g player_gear; t int; res jsonb := '[]'::jsonb; rs int := _trade_cfg('resale_hours');
begin
  if p_ids is null or cardinality(p_ids) = 0 then return res; end if;
  if (select count(distinct x) from unnest(p_ids) x) <> cardinality(p_ids) then raise exception 'duplicate gear'; end if;
  foreach gid in array p_ids loop
    select * into g from player_gear where id = gid and user_id = p_uid for update;
    if g.id is null then raise exception 'gear not owned'; end if;
    if g.locked then raise exception 'gear locked'; end if;
    if g.equipped_card is not null then raise exception 'gear equipped'; end if;
    select tier into t from gear_defs where id = g.def_id;
    if t > 5 then raise exception 'gear not tradable'; end if;
    if g.source in ('trade', 'mail:trade') and g.created_at > now() - make_interval(hours => rs) then raise exception 'resale cooldown'; end if;
    delete from player_gear where id = gid;
    res := res || jsonb_build_array(jsonb_build_object('row', to_jsonb(g), 'gkey', _trade_gear_gkey(t)));
  end loop;
  return res;
end $$;

-- 장비 지급: 돌려줄 때는 같은 행 그대로, 거래로 받으면 새 주인·재판매 대기. 가방 꽉 차면 우편함 (30일)
create or replace function public._trade_give_gear(p_uid uuid, p_items jsonb, p_traded boolean) returns int language plpgsql security definer set search_path = public as $$
declare it jsonb; r jsonb; mailed int := 0;
begin
  for it in select x from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x loop
    r := it->'row';
    if _gear_bag_full(p_uid) then
      insert into player_mail (user_id, kind, payload, reason, expires_at)
        values (p_uid, 'gear', jsonb_build_object('def_id', r->>'def_id', 'opts', r->'opts', 'plus', (r->>'plus')::int, 'from_gear', (r->>'id')::bigint), 'trade', now() + interval '30 days');
      mailed := mailed + 1;
    else
      insert into player_gear (id, user_id, def_id, plus, opts, locked, equipped_card, source, created_at) overriding system value
        values ((r->>'id')::bigint, p_uid, r->>'def_id', (r->>'plus')::int, r->'opts', false, null,
                case when p_traded then 'trade' else r->>'source' end, case when p_traded then now() else (r->>'created_at')::timestamptz end);
    end if;
  end loop;
  return mailed;
end $$;

-- 증표 이동: 보낸 쪽에 같은 인재가 더 없으면 증표(단계)를 받는 쪽으로. 투입 조각 합으로 비교
create or replace function public._trade_sigil_move(p_from uuid, p_to uuid, p_card text) returns jsonb language plpgsql security definer set search_path = public as $$
declare s player_sigils; t player_sigils; inv_s int; inv_t int;
begin
  if exists (select 1 from story_progress sp, jsonb_array_elements(_story_owned(sp.data)) x where sp.user_id = p_from and x->>'id' = p_card) then return null; end if;
  select * into s from player_sigils where user_id = p_from and card_id = p_card for update;
  if s.card_id is null or s.plus is null then return null; end if;
  inv_s := (select coalesce(sum(frags), 0) from sigil_cost where plus <= s.plus);
  update player_sigils set plus = null where user_id = p_from and card_id = p_card;
  select * into t from player_sigils where user_id = p_to and card_id = p_card for update;
  if t.card_id is null then
    insert into player_sigils (user_id, card_id, plus, frags) values (p_to, p_card, s.plus, 0);
  elsif t.plus is null then
    update player_sigils set plus = s.plus where user_id = p_to and card_id = p_card;
  else
    inv_t := (select coalesce(sum(frags), 0) from sigil_cost where plus <= t.plus);
    if s.plus > t.plus then update player_sigils set plus = s.plus, frags = frags + inv_t where user_id = p_to and card_id = p_card;
    else update player_sigils set frags = frags + inv_s where user_id = p_to and card_id = p_card; end if;
  end if;
  return jsonb_build_object('card', p_card, 'plus', s.plus);
end $$;

-- 제안 환불 (대기 → p_status). 이미 끝난 제안이면 아무것도 안 함
create or replace function public._trade_refund_offer(p_offer bigint, p_status text) returns boolean language plpgsql security definer set search_path = public as $$
declare o trade_offers;
begin
  select * into o from trade_offers where id = p_offer for update;
  if o.id is null or o.status <> 'pending' then return false; end if;
  update trade_offers set status = p_status, closed_at = now() where id = p_offer;
  perform _trade_give_cards(o.offerer, o.cards, false);
  perform _trade_give_gear(o.offerer, o.gear, false);
  if o.drinks > 0 then perform _item_add(o.offerer, 'drink', o.drinks, 0, 'trade_refund', null, jsonb_build_object('offer', o.id)); end if;
  if o.gold + o.fee_gold > 0 then perform _wallet_add(o.offerer, jsonb_build_object('gold', o.gold + o.fee_gold), 'trade_refund'); end if;
  return true;
end $$;

-- 글 닫기 (취소·만료): 판매자 물건 반환 + 대기 제안 모두 환불. 글 행은 호출 전에 잠가 둘 것
create or replace function public._trade_close_listing(p_listing bigint, p_status text) returns int language plpgsql security definer set search_path = public as $$
declare l trade_listings; oid bigint; n int := 0;
begin
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.status <> 'open' then return 0; end if;
  perform _trade_lock_users(array[l.seller] || array(select offerer from trade_offers where listing_id = l.id and status = 'pending'));
  update trade_listings set status = p_status, closed_at = now() where id = l.id;
  perform _trade_give_cards(l.seller, l.cards, false);
  perform _trade_give_gear(l.seller, l.gear, false);
  for oid in select id from trade_offers where listing_id = l.id and status = 'pending' order by id loop
    if _trade_refund_offer(oid, 'refunded') then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- 만료 처리 (주기 작업 + 게시판·내 거래 볼 때 조금씩)
create or replace function public.trade_expire_due(p_limit int default 20) returns int language plpgsql security definer set search_path = public as $$
declare lid bigint; n int := 0;
begin
  for lid in select id from trade_listings where status = 'open' and expires_at <= now() order by expires_at limit greatest(1, least(p_limit, 200)) for update skip locked loop
    perform _trade_close_listing(lid, 'expired'); n := n + 1;
  end loop;
  return n;
end $$;

-- 가격·골드 검사. p_l = 글 물건 [{gkey}], p_o = 제안 물건, 재화는 제안 쪽에만
create or replace function public._trade_check_price(p_l jsonb, p_o jsonb, p_drinks int, p_gold bigint) returns void language plpgsql stable security definer set search_path = public as $$
declare dmin bigint; dmax bigint; gmin bigint; gmax bigint; gold_ok boolean; ratio numeric;
begin
  select coalesce(sum(b.d_min), 0), coalesce(sum(b.d_max), 0), coalesce(sum(b.g_min), 0), coalesce(sum(b.g_max), 0), bool_and(b.g_max is not null)
    into dmin, dmax, gmin, gmax, gold_ok
    from jsonb_array_elements(p_l) x join trade_band b on b.gkey = x->>'gkey';
  if p_gold > 0 then
    if not gold_ok or exists (select 1 from jsonb_array_elements(p_o) x join trade_band b on b.gkey = x->>'gkey' where b.g_max is null) then raise exception 'gold not allowed'; end if;
  end if;
  if p_drinks > dmax or p_gold > coalesce(gmax, 0) then raise exception 'price too high'; end if;
  if jsonb_array_length(p_o) = 0 then
    -- 재화만 제안: 최소치 이상 (드링크·골드를 섞으면 비율 합이 1 이상)
    ratio := p_drinks::numeric / greatest(dmin, 1);
    if gold_ok and gmin > 0 then ratio := ratio + p_gold::numeric / gmin; end if;
    if ratio < 1 then raise exception 'price too low'; end if;
  end if;
end $$;

-- 4) 공개 RPC -------------------------------------------------------------------------
-- 판매 글 올리기
create or replace function public.trade_list(p_cards text[], p_gear bigint[], p_want text default '') returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := coalesce(cardinality(p_cards), 0) + coalesce(cardinality(p_gear), 0); c jsonb; g jsonb; lid bigint;
begin
  perform _trade_gate(uid);
  perform _trade_lock_users(array[uid]);
  if n < 1 then raise exception 'nothing to trade'; end if;
  if n > _trade_cfg('max_items') then raise exception 'too many items'; end if;
  if (select count(*) from trade_listings where seller = uid and status = 'open') >= _trade_cfg('max_open_listings') then raise exception 'too many listings'; end if;
  c := _trade_take_cards(uid, p_cards); g := _trade_take_gear(uid, p_gear);
  insert into trade_listings (seller, want, cards, gear, expires_at)
    values (uid, left(coalesce(btrim(p_want), ''), 100), c, g, now() + make_interval(hours => _trade_cfg('listing_hours'))) returning id into lid;
  return jsonb_build_object('ok', true, 'listing_id', lid);
end $$;

-- 제안
create or replace function public.trade_offer(p_listing bigint, p_cards text[], p_gear bigint[], p_drinks int default 0, p_gold bigint default 0) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; n int := coalesce(cardinality(p_cards), 0) + coalesce(cardinality(p_gear), 0); c jsonb; g jsonb; oid bigint; fee bigint := 0; lk jsonb;
begin
  perform _trade_gate(uid);
  p_drinks := coalesce(p_drinks, 0); p_gold := coalesce(p_gold, 0);
  if p_drinks < 0 or p_gold < 0 then raise exception 'invalid amount'; end if;
  if n = 0 and p_drinks = 0 and p_gold = 0 then raise exception 'nothing to offer'; end if;
  if n > _trade_cfg('max_items') then raise exception 'too many items'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null then raise exception 'listing not found'; end if;
  if l.status = 'open' and l.expires_at <= now() then perform _trade_close_listing(l.id, 'expired'); return jsonb_build_object('ok', false, 'reason', 'listing closed'); end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  if l.seller = uid then raise exception 'own listing'; end if;
  perform _trade_lock_users(array[uid]);
  if exists (select 1 from trade_offers where listing_id = l.id and offerer = uid and status = 'pending') then raise exception 'already offered'; end if;
  if exists (select 1 from trade_offers where listing_id = l.id and offerer = uid and status = 'rejected'
             and closed_at > now() - make_interval(hours => _trade_cfg('reoffer_cooldown_hours'))) then raise exception 'reoffer cooldown'; end if;
  if (select count(*) from trade_offers where offerer = uid and status = 'pending') >= _trade_cfg('max_open_offers') then raise exception 'too many offers'; end if;
  if (select count(*) from trade_offers where listing_id = l.id and status = 'pending') >= _trade_cfg('max_pending_per_listing') then raise exception 'listing full'; end if;
  if (select coalesce(sum(drinks), 0) from trade_offers where offerer = uid and status = 'pending') + p_drinks > _trade_cfg('escrow_max_drinks') then raise exception 'escrow limit'; end if;
  if (select coalesce(sum(gold), 0) from trade_offers where offerer = uid and status = 'pending') + p_gold > _trade_cfg('escrow_max_gold') then raise exception 'escrow limit'; end if;
  c := _trade_take_cards(uid, p_cards); g := _trade_take_gear(uid, p_gear);
  lk := l.cards || l.gear;
  perform _trade_check_price(lk, c || g, p_drinks, p_gold);
  -- 물건끼리만: 제안자가 받을 물건(글 물건) 등급별 고정 골드를 미리 보관
  if p_drinks = 0 and p_gold = 0 then
    select coalesce(sum(b.fix_fee), 0) into fee from jsonb_array_elements(lk) x join trade_band b on b.gkey = x->>'gkey';
  end if;
  if p_drinks > 0 then perform _item_add(uid, 'drink', -p_drinks, 0, 'trade_escrow', null, jsonb_build_object('listing', l.id)); end if;
  if p_gold + fee > 0 then perform _wallet_add(uid, jsonb_build_object('gold', -(p_gold + fee)), 'trade_escrow'); end if;
  insert into trade_offers (listing_id, offerer, cards, gear, drinks, gold, fee_gold) values (l.id, uid, c, g, p_drinks, p_gold, fee) returning id into oid;
  return jsonb_build_object('ok', true, 'offer_id', oid, 'fee_gold', fee);
end $$;

-- 제안 취소 (제안자)
create or replace function public.trade_offer_cancel(p_offer bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); o trade_offers;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into o from trade_offers where id = p_offer;
  if o.id is null or o.offerer <> uid then raise exception 'offer not found'; end if;
  perform 1 from trade_listings where id = o.listing_id for update;
  perform _trade_lock_users(array[uid]);
  if not _trade_refund_offer(p_offer, 'cancelled') then raise exception 'offer closed'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 글 내리기 (판매자)
create or replace function public.trade_cancel(p_listing bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; n int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.seller <> uid then raise exception 'listing not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  n := _trade_close_listing(l.id, 'cancelled');
  return jsonb_build_object('ok', true, 'refunded', n);
end $$;

-- 거절: 고른 제안들 (판매자, 최대 bulk_max)
create or replace function public.trade_reject(p_listing bigint, p_offers bigint[]) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; oid bigint; n int := 0;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_offers is null or cardinality(p_offers) = 0 then raise exception 'nothing to reject'; end if;
  if cardinality(p_offers) > _trade_cfg('bulk_max') then raise exception 'too many offers'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.seller <> uid then raise exception 'listing not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  perform _trade_lock_users(array(select offerer from trade_offers where listing_id = l.id and id = any(p_offers) and status = 'pending'));
  for oid in select id from trade_offers where listing_id = l.id and id = any(p_offers) and status = 'pending' order by id loop
    if _trade_refund_offer(oid, 'rejected') then n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'rejected', n);
end $$;

-- 조건 아래 전부 거절: 드링크 < p_min_drinks · 골드 < p_min_gold · 물건 없는 제안 (넘긴 조건 중 하나라도 맞으면)
create or replace function public.trade_reject_below(p_listing bigint, p_min_drinks int default null, p_min_gold bigint default null, p_no_items boolean default false) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ids bigint[];
begin
  if uid is null then raise exception 'login required'; end if;
  if p_min_drinks is null and p_min_gold is null and not coalesce(p_no_items, false) then raise exception 'no condition'; end if;
  if not exists (select 1 from trade_listings where id = p_listing and seller = uid) then raise exception 'listing not found'; end if;
  select array_agg(id order by id) into ids from (
    select id from trade_offers where listing_id = p_listing and status = 'pending'
      and ((p_min_drinks is not null and drinks < p_min_drinks) or (p_min_gold is not null and gold < p_min_gold)
           or (coalesce(p_no_items, false) and jsonb_array_length(cards) + jsonb_array_length(gear) = 0))
    order by id limit _trade_cfg('bulk_max')) x;
  if ids is null then return jsonb_build_object('ok', true, 'rejected', 0); end if;
  return trade_reject(p_listing, ids);
end $$;

-- 수락 (판매자): 한 번에 교환, 수수료 소각, 나머지 제안 환불
create or replace function public.trade_accept(p_listing bigint, p_offer bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; o trade_offers; pct int := _trade_cfg('fee_pct'); fd int := 0; fg bigint := 0; sfee bigint := 0;
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
  -- 나머지 제안 환불
  for oid in select id from trade_offers where listing_id = l.id and status = 'pending' order by id loop
    if _trade_refund_offer(oid, 'refunded') then n := n + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'drinks', o.drinks - fd, 'gold', o.gold - fg, 'fee_drinks', fd, 'fee_gold', fg + sfee, 'refunded', n, 'mailed', m2, 'sigils', sig);
end $$;

-- 게시판 (열린 글, 내 글 제외 아님). 제안 내용은 비공개, 개수만
create or replace function public.trade_board(p_limit int default 50, p_before bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true, 'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'mine', l.seller = uid, 'want', l.want,
      'cards', (select coalesce(jsonb_agg(x->'card' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.cards) x),
      'gear', (select coalesce(jsonb_agg((x->'row') - 'user_id' || jsonb_build_object('gkey', x->>'gkey')), '[]'::jsonb) from jsonb_array_elements(l.gear) x),
      'offers', (select count(*) from trade_offers o where o.listing_id = l.id and o.status = 'pending'),
      'my_offer', (select o.id from trade_offers o where o.listing_id = l.id and o.offerer = uid and o.status = 'pending'),
      'expires_at', l.expires_at, 'created_at', l.created_at) order by l.id desc), '[]'::jsonb)
    from (select * from trade_listings where status = 'open' and expires_at > now() and (p_before is null or id < p_before) order by id desc limit greatest(1, least(p_limit, 100))) l));
end $$;

-- 내 거래: 내 글(들어온 제안 전체) + 내 제안 + 최근 기록
create or replace function public.trade_my() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform trade_expire_due(10);
  return jsonb_build_object('ok', true,
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'status', l.status, 'want', l.want, 'cards', l.cards, 'gear', l.gear, 'expires_at', l.expires_at, 'offer_id', l.offer_id,
        'offers', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'cards', o.cards, 'gear', o.gear, 'drinks', o.drinks, 'gold', o.gold, 'created_at', o.created_at,
                     'nick', (select nickname from profiles where id = o.offerer)) order by o.id), '[]'::jsonb)
                   from trade_offers o where o.listing_id = l.id and (o.status = 'pending' or o.id = l.offer_id))) order by l.id desc), '[]'::jsonb)
      from (select * from trade_listings where seller = uid and (status = 'open' or closed_at > now() - interval '7 days') order by id desc limit 30) l),
    'offers', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'listing_id', o.listing_id, 'status', o.status, 'cards', o.cards, 'gear', o.gear, 'drinks', o.drinks, 'gold', o.gold,
        'fee_gold', o.fee_gold, 'created_at', o.created_at, 'closed_at', o.closed_at,
        'reoffer_at', case when o.status = 'rejected' then o.closed_at + make_interval(hours => _trade_cfg('reoffer_cooldown_hours')) end) order by o.id desc), '[]'::jsonb)
      from (select * from trade_offers where offerer = uid and (status = 'pending' or closed_at > now() - interval '7 days') order by id desc limit 50) o),
    'config', (select jsonb_object_agg(key, val) from trade_config),
    'bands', (select jsonb_agg(to_jsonb(b) order by gkey) from trade_band b));
end $$;

-- 5) 권한 -----------------------------------------------------------------------------
revoke all on function public._trade_cfg(text), public._trade_card_gkey(text), public._trade_gear_gkey(int), public._trade_lock_users(uuid[]), public._trade_strip(jsonb, text),
  public._trade_gate(uuid), public._trade_take_cards(uuid, text[]), public._trade_give_cards(uuid, jsonb, boolean), public._trade_take_gear(uuid, bigint[]),
  public._trade_give_gear(uuid, jsonb, boolean), public._trade_sigil_move(uuid, uuid, text), public._trade_refund_offer(bigint, text),
  public._trade_close_listing(bigint, text), public._trade_check_price(jsonb, jsonb, int, bigint), public.trade_expire_due(int) from public, anon, authenticated;
revoke all on function public.trade_list(text[], bigint[], text), public.trade_offer(bigint, text[], bigint[], int, bigint), public.trade_offer_cancel(bigint),
  public.trade_cancel(bigint), public.trade_reject(bigint, bigint[]), public.trade_reject_below(bigint, int, bigint, boolean), public.trade_accept(bigint, bigint),
  public.trade_board(int, bigint), public.trade_my() from public, anon;
grant execute on function public.trade_list(text[], bigint[], text), public.trade_offer(bigint, text[], bigint[], int, bigint), public.trade_offer_cancel(bigint),
  public.trade_cancel(bigint), public.trade_reject(bigint, bigint[]), public.trade_reject_below(bigint, int, bigint, boolean), public.trade_accept(bigint, bigint),
  public.trade_board(int, bigint), public.trade_my() to authenticated;

-- 주기 만료 (pg_cron 이 있으면 10분마다)
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'trade_expire';
    perform cron.schedule('trade_expire', '*/10 * * * *', 'select public.trade_expire_due(200)');
  end if;
exception when others then raise notice 'trade_expire cron skipped: %', sqlerrm;
end $$;
