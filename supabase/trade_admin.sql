-- ===== 거래 PR5: 어뷰징 방지 마무리 · 관리자 도구 =====
-- 선행: trade_board.sql · admin.sql (_admin_guard · admin_log). 여러 번 실행해도 안전. 기존 거래 함수는 고치지 않고 트리거로 붙임
-- 1) 드링크 하루 이동량: 보내기·받기 각각 하루 10,000 (KST) — 제안할 때 보낸 쪽, 거래 기록 때 양쪽 검사
-- 2) 제안 취소 남발: 하루 취소 20번 넘으면 그날 새 제안 불가
-- 3) 의심 거래 표시(trade_flags): 같은 상대 반복 · 가격 범위 끝 · 새 계정 · 한쪽으로 크게 기운 거래 → 관리자 화면에서 확인
-- 4) 관리자: 거래 기록·글·제안 조회, 의심 거래 목록·확인 처리, 같은 상대 반복 상위, 글 강제 내림(전부 환불)·제안 강제 환불, 조절표 수정 (사유 필수, admin_log 기록)
--    완료된 거래를 되돌리는 기능은 없음 (물건이 이미 다시 움직였을 수 있어 위험) → 의심 거래는 기록 확인 후 운영 지급·회수로 처리

insert into public.trade_config (key, val, note) values
  ('daily_drink_send', 10000, '하루 드링크 보내기 (거래 완료 + 이번 제안)'),
  ('daily_drink_recv', 10000, '하루 드링크 받기'),
  ('daily_cancels', 20, '하루 제안 취소 한도 (넘으면 그날 제안 불가)'),
  ('flag_new_days', 14, '의심: 가입 n일 이내 계정'),
  ('flag_edge_pct', 5, '의심: 가격 범위 끝 ±%'),
  ('flag_ratio', 5, '의심: 한쪽 가치가 n배 이상'),
  ('flag_pair_7d', 2, '의심: 같은 상대 7일 n번째부터')
on conflict (key) do nothing;

create table if not exists public.trade_flags (
  id         bigint generated always as identity primary key,
  log_id     bigint not null references public.trade_log(id) on delete cascade,
  kind       text not null check (kind in ('repeat_pair', 'band_edge', 'new_account', 'lopsided')),
  detail     jsonb not null default '{}'::jsonb,
  reviewed_at timestamptz, reviewed_by text, note text check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  unique (log_id, kind)
);
create index if not exists trade_flags_open on public.trade_flags (created_at desc) where reviewed_at is null;
alter table public.trade_flags enable row level security;
revoke all on public.trade_flags from public, anon, authenticated;

create or replace function public._trade_day_start() returns timestamptz language sql stable as $$
  select ((now() at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul') $$;

-- 하루 보낸/받은 드링크 (완료 거래 기준: 제안자가 보냄, 판매자가 받음)
create or replace function public._trade_drinks_today(p_uid uuid, p_dir text) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum((buyer_gave->>'drinks')::bigint), 0) from trade_log
   where created_at >= _trade_day_start() and case when p_dir = 'send' then buyer = p_uid else seller = p_uid end $$;

-- 제안 넣을 때: 취소 남발 · 보내기 한도
create or replace function public._trade_offer_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from trade_offers where offerer = new.offerer and status = 'cancelled' and closed_at >= _trade_day_start()) >= _trade_cfg('daily_cancels') then
    raise exception 'cancel limit'; end if;
  if new.drinks > 0 and _trade_drinks_today(new.offerer, 'send') + new.drinks > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
  return new;
end $$;
drop trigger if exists trade_offer_guard on public.trade_offers;
create trigger trade_offer_guard before insert on public.trade_offers for each row execute function public._trade_offer_guard();

-- 거래 기록 때: 받기·보내기 한도 (넘으면 수락 전체 취소) + 의심 표시
create or replace function public._trade_log_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare d bigint := coalesce((new.buyer_gave->>'drinks')::bigint, 0);
begin
  if d > 0 then
    if _trade_drinks_today(new.seller, 'recv') + d > _trade_cfg('daily_drink_recv') then raise exception 'drink recv limit'; end if;
    if _trade_drinks_today(new.buyer, 'send') + d > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
  end if;
  return new;
end $$;
drop trigger if exists trade_log_guard on public.trade_log;
create trigger trade_log_guard before insert on public.trade_log for each row execute function public._trade_log_guard();

-- 가치 (드링크 기준): 등급 범위 가운데 값 합
create or replace function public._trade_value(p_items jsonb) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum((b.d_min + b.d_max) / 2.0), 0) from jsonb_array_elements(coalesce(p_items, '[]')) x join trade_band b on b.gkey = x->>'gkey' $$;

create or replace function public._trade_log_flag() returns trigger language plpgsql security definer set search_path = public as $$
declare d bigint := coalesce((new.buyer_gave->>'drinks')::bigint, 0); g bigint := coalesce((new.buyer_gave->>'gold')::bigint, 0);
        lk jsonb := coalesce(new.seller_gave->'cards', '[]') || coalesce(new.seller_gave->'gear', '[]');
        ok_ jsonb := coalesce(new.buyer_gave->'cards', '[]') || coalesce(new.buyer_gave->'gear', '[]');
        dmin bigint; dmax bigint; gmin bigint; gmax bigint; vl numeric; vo numeric; e numeric := _trade_cfg('flag_edge_pct') / 100.0; r int := _trade_cfg('flag_ratio'); np int; gpd numeric;
begin
  -- 같은 상대 반복
  select count(*) into np from trade_log where ((seller = new.seller and buyer = new.buyer) or (seller = new.buyer and buyer = new.seller)) and created_at > now() - interval '7 days';
  if np >= _trade_cfg('flag_pair_7d') then
    insert into trade_flags (log_id, kind, detail) values (new.id, 'repeat_pair', jsonb_build_object('count_7d', np)) on conflict do nothing;
  end if;
  -- 새 계정
  if exists (select 1 from auth.users where id in (new.seller, new.buyer) and created_at > now() - make_interval(days => _trade_cfg('flag_new_days'))) then
    insert into trade_flags (log_id, kind, detail) values (new.id, 'new_account', jsonb_build_object('days', _trade_cfg('flag_new_days'))) on conflict do nothing;
  end if;
  -- 가격 범위 끝 (재화만 받은 거래)
  if jsonb_array_length(ok_) = 0 and (d > 0 or g > 0) then
    select coalesce(sum(b.d_min), 0), coalesce(sum(b.d_max), 0), coalesce(sum(b.g_min), 0), coalesce(sum(b.g_max), 0) into dmin, dmax, gmin, gmax
      from jsonb_array_elements(lk) x join trade_band b on b.gkey = x->>'gkey';
    if (d > 0 and (d <= dmin * (1 + e) or d >= dmax * (1 - e))) or (g > 0 and (g <= gmin * (1 + e) or g >= gmax * (1 - e))) then
      insert into trade_flags (log_id, kind, detail) values (new.id, 'band_edge', jsonb_build_object('drinks', d, 'gold', g, 'd_range', jsonb_build_array(dmin, dmax), 'g_range', jsonb_build_array(gmin, gmax))) on conflict do nothing;
    end if;
  end if;
  -- 한쪽으로 기운 거래 (골드는 등급 범위 비율로 드링크 환산)
  gpd := coalesce((select avg(g_max::numeric / d_max) from trade_band where g_max is not null), 1000);
  vl := _trade_value(lk); vo := _trade_value(ok_) + d + g / gpd;
  if least(vl, vo) > 0 and greatest(vl, vo) / least(vl, vo) >= r or (least(vl, vo) = 0 and greatest(vl, vo) > 0) then
    insert into trade_flags (log_id, kind, detail) values (new.id, 'lopsided', jsonb_build_object('seller_value', round(vl), 'buyer_value', round(vo))) on conflict do nothing;
  end if;
  return null;
end $$;
drop trigger if exists trade_log_flag on public.trade_log;
create trigger trade_log_flag after insert on public.trade_log for each row execute function public._trade_log_flag();

-- ---- 관리자 ------------------------------------------------------------------------
create or replace function public._trade_admin_log(p_action text, p_user uuid, p_amount int, p_reason text, p_before int, p_after int) returns void language plpgsql security definer set search_path = public, auth as $$
begin
  insert into admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), coalesce(auth.jwt()->>'email', ''), p_action, p_user, p_amount, left(p_reason, 200), p_before, p_after);
end $$;

-- 거래 기록 (유저 지정 가능)
create or replace function public.admin_trade_log(p_user uuid default null, p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'listing_id', l.listing_id, 'offer_id', l.offer_id, 'at', l.created_at,
      'seller', l.seller, 'seller_email', (select email from auth.users where id = l.seller), 'buyer', l.buyer, 'buyer_email', (select email from auth.users where id = l.buyer),
      'seller_gave', l.seller_gave, 'buyer_gave', l.buyer_gave, 'fees', l.fees,
      'flags', (select coalesce(jsonb_agg(f.kind), '[]'::jsonb) from trade_flags f where f.log_id = l.id)) order by l.id desc), '[]'::jsonb)
    from (select * from trade_log where p_user is null or seller = p_user or buyer = p_user order by id desc limit greatest(1, least(p_limit, 500))) l);
end $$;

-- 글·제안 (유저 지정 가능, 상태 필터)
create or replace function public.admin_trade_listings(p_user uuid default null, p_status text default null, p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'status', l.status, 'seller', l.seller, 'seller_email', (select email from auth.users where id = l.seller),
      'cards', l.cards, 'gear', l.gear, 'want', l.want, 'created_at', l.created_at, 'expires_at', l.expires_at,
      'offers', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'offerer', o.offerer, 'email', (select email from auth.users where id = o.offerer),
                   'cards', o.cards, 'gear', o.gear, 'drinks', o.drinks, 'gold', o.gold, 'fee_gold', o.fee_gold, 'at', o.created_at) order by o.id), '[]'::jsonb) from trade_offers o where o.listing_id = l.id)) order by l.id desc), '[]'::jsonb)
    from (select * from trade_listings x where (p_user is null or x.seller = p_user or exists (select 1 from trade_offers o where o.listing_id = x.id and o.offerer = p_user))
            and (p_status is null or x.status = p_status) order by id desc limit greatest(1, least(p_limit, 300))) l);
end $$;

-- 의심 거래
create or replace function public.admin_trade_flags(p_open_only boolean default true, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'log_id', f.log_id, 'kind', f.kind, 'detail', f.detail, 'at', f.created_at, 'reviewed_at', f.reviewed_at, 'reviewed_by', f.reviewed_by, 'note', f.note,
      'seller_email', (select email from auth.users where id = l.seller), 'buyer_email', (select email from auth.users where id = l.buyer), 'seller', l.seller, 'buyer', l.buyer,
      'buyer_gave', l.buyer_gave, 'seller_gave', l.seller_gave) order by f.id desc), '[]'::jsonb)
    from (select * from trade_flags where not p_open_only or reviewed_at is null order by id desc limit greatest(1, least(p_limit, 500))) f join trade_log l on l.id = f.log_id);
end $$;

create or replace function public.admin_trade_flag_review(p_id bigint, p_note text) returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  update trade_flags set reviewed_at = now(), reviewed_by = auth.jwt()->>'email', note = left(coalesce(btrim(p_note), ''), 200) where id = p_id;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 같은 상대 반복 상위
create or replace function public.admin_trade_pairs(p_days int default 7, p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('a', a, 'b', b, 'a_email', (select email from auth.users where id = a), 'b_email', (select email from auth.users where id = b),
      'trades', n, 'drinks', dr, 'gold', gd, 'last', last) order by n desc, dr desc), '[]'::jsonb)
    from (select least(seller, buyer) a, greatest(seller, buyer) b, count(*) n, sum(coalesce((buyer_gave->>'drinks')::bigint, 0)) dr, sum(coalesce((buyer_gave->>'gold')::bigint, 0)) gd, max(created_at) last
            from trade_log where created_at > now() - make_interval(days => greatest(1, least(p_days, 90))) group by 1, 2 having count(*) >= 2 order by n desc limit greatest(1, least(p_limit, 200))) x);
end $$;

-- 글 강제 내림: 판매 물건 반환 + 대기 제안 모두 환불
create or replace function public.admin_trade_void_listing(p_listing bigint, p_reason text) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare l trade_listings; n int;
begin
  perform _admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null then raise exception 'not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  n := _trade_close_listing(l.id, 'cancelled');
  perform _trade_admin_log('trade_void_listing', l.seller, l.id::int, btrim(p_reason), null, n);
  return jsonb_build_object('ok', true, 'refunded', n);
end $$;

-- 제안 강제 환불
create or replace function public.admin_trade_refund_offer(p_offer bigint, p_reason text) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare o trade_offers;
begin
  perform _admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  select * into o from trade_offers where id = p_offer;
  if o.id is null then raise exception 'not found'; end if;
  perform 1 from trade_listings where id = o.listing_id for update;
  perform _trade_lock_users(array[o.offerer]);
  if not _trade_refund_offer(o.id, 'refunded') then raise exception 'offer closed'; end if;
  perform _trade_admin_log('trade_refund_offer', o.offerer, o.id::int, btrim(p_reason), null, null);
  return jsonb_build_object('ok', true);
end $$;

-- 조절표 보기·수정
create or replace function public.admin_trade_config() returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return jsonb_build_object('config', (select jsonb_agg(to_jsonb(c) order by key) from trade_config c), 'bands', (select jsonb_agg(to_jsonb(b) order by gkey) from trade_band b));
end $$;
create or replace function public.admin_trade_config_set(p_key text, p_val int, p_reason text) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare bef int;
begin
  perform _admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if p_val is null or p_val < 0 or p_val > 100000000 then raise exception 'invalid value'; end if;
  if p_key = 'fee_pct' and p_val > 50 then raise exception 'invalid value'; end if;
  select val into bef from trade_config where key = p_key for update;
  if bef is null then raise exception 'not found'; end if;
  update trade_config set val = p_val where key = p_key;
  perform _trade_admin_log('trade_config:' || left(p_key, 27), null, p_val, btrim(p_reason), bef, p_val);
  return jsonb_build_object('ok', true, 'key', p_key, 'before', bef, 'after', p_val);
end $$;
-- 등급 범위 수정 (p_field = d_min · d_max · g_min · g_max · fix_fee, g_* 는 null 로 골드 불가)
create or replace function public.admin_trade_band_set(p_gkey text, p_field text, p_val int, p_reason text) returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare bef int;
begin
  perform _admin_guard();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if p_field not in ('d_min', 'd_max', 'g_min', 'g_max', 'fix_fee') then raise exception 'invalid field'; end if;
  if p_val is not null and (p_val < 0 or p_val > 100000000) then raise exception 'invalid value'; end if;
  if p_val is null and p_field not in ('g_min', 'g_max') then raise exception 'invalid value'; end if;
  execute format('select %I from trade_band where gkey = $1', p_field) into bef using p_gkey;
  if not exists (select 1 from trade_band where gkey = p_gkey) then raise exception 'not found'; end if;
  execute format('update trade_band set %I = $1 where gkey = $2', p_field) using p_val, p_gkey;
  if p_field in ('g_min', 'g_max') then   -- 골드 불가/허용은 짝으로
    if p_val is null then update trade_band set g_min = null, g_max = null where gkey = p_gkey; end if;
  end if;
  if exists (select 1 from trade_band where gkey = p_gkey and (d_min > d_max or (g_min is null) <> (g_max is null) or g_min > g_max)) then raise exception 'invalid band'; end if;
  perform _trade_admin_log('trade_band:' || left(p_gkey || '.' || p_field, 28), null, p_val, btrim(p_reason), bef, p_val);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public._trade_day_start(), public._trade_drinks_today(uuid, text), public._trade_offer_guard(), public._trade_log_guard(), public._trade_value(jsonb),
  public._trade_log_flag(), public._trade_admin_log(text, uuid, int, text, int, int) from public, anon, authenticated;
revoke all on function public.admin_trade_log(uuid, int), public.admin_trade_listings(uuid, text, int), public.admin_trade_flags(boolean, int), public.admin_trade_flag_review(bigint, text),
  public.admin_trade_pairs(int, int), public.admin_trade_void_listing(bigint, text), public.admin_trade_refund_offer(bigint, text), public.admin_trade_config(),
  public.admin_trade_config_set(text, int, text), public.admin_trade_band_set(text, text, int, text) from public, anon;
grant execute on function public.admin_trade_log(uuid, int), public.admin_trade_listings(uuid, text, int), public.admin_trade_flags(boolean, int), public.admin_trade_flag_review(bigint, text),
  public.admin_trade_pairs(int, int), public.admin_trade_void_listing(bigint, text), public.admin_trade_refund_offer(bigint, text), public.admin_trade_config(),
  public.admin_trade_config_set(text, int, text), public.admin_trade_band_set(text, text, int, text) to authenticated;
