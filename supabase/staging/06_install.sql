-- ⚠ 테스트 전용 6/14. 운영 실행 금지. 파일 전체를 번호 순서대로 실행.
-- 대상 프로젝트: cuyqchmdcnsgzkwyclji; 운영 htarwisgkkphutxxnuak 금지.
-- 완료한 파일은 다시 실행해도 건너뜀. 중간 오류는 해당 파일만 되돌아감.
-- 실제 project_ref는 SQL Editor가 보장해서 제공하지 않음: DB 고유번호를 대조.
-- 지정 테스트 DB의 식별번호와 일치할 때만 허용. guard 삭제/SET 우회 금지.
-- docs/STAGING.md 및 supabase/staging/README.md 먼저 확인.

begin;
do $vr_project_guard$
declare
  confirmed_ref text := 'cuyqchmdcnsgzkwyclji';
  expected_db_id text := '7703759698107299042';
  actual_db_id text;
begin
  if confirmed_ref is distinct from 'cuyqchmdcnsgzkwyclji' or confirmed_ref = 'htarwisgkkphutxxnuak' then
    raise exception 'STOP: 지정한 테스트 프로젝트만 허용합니다. 운영 DB 금지.';
  end if;
  if expected_db_id !~ '^[0-9]{16,20}$' then
    raise exception 'STOP: 테스트 DB의 실제 고유번호가 아직 등록되지 않았습니다. 안내 문서를 확인하세요.';
  end if;
  select system_identifier::text into actual_db_id from pg_catalog.pg_control_system();
  if actual_db_id is distinct from expected_db_id then
    raise exception 'STOP: 현재 접속한 DB가 지정된 테스트 DB와 다릅니다. 실행 금지.';
  end if;
exception when insufficient_privilege or undefined_function then
  raise exception 'STOP: DB 식별 조회 권한/기능이 없어 안전하게 중단합니다. guard를 삭제하지 마세요.';
end $vr_project_guard$;

-- 설치 기록은 API에서 접근할 수 없는 별도 스키마에 저장.
select pg_advisory_xact_lock(20261107, 490);
create schema if not exists vr_staging_install;
revoke all on schema vr_staging_install from public, anon, authenticated;
create table if not exists vr_staging_install.parts (
  part_no integer primary key, bundle_hash text not null, part_hash text not null,
  project_ref text not null, db_id text not null, applied_at timestamptz not null default now()
);
alter table vr_staging_install.parts enable row level security;
revoke all on vr_staging_install.parts from public, anon, authenticated;
set local check_function_bodies = off;

do $vr_install_part$
begin
  if exists (select 1 from vr_staging_install.parts where bundle_hash <> '4865c74f256feb41fff1e4fb89b5acf4b05ac5c3b4ea13de07ab10a52975d4b3' or project_ref <> 'cuyqchmdcnsgzkwyclji' or db_id <> '7703759698107299042') then
    raise exception 'STOP: 다른 버전/DB의 설치 기록입니다. 파일을 섞지 마세요.';
  end if;
  if exists (select 1 from vr_staging_install.parts where part_no = 6) then
    if not exists (select 1 from vr_staging_install.parts where part_no = 6 and part_hash = '3ab57a984bef501ac1a360805d30dbd17b38cc4fae1ed81a01209fdf40f3d679') then
      raise exception 'STOP: 완료한 파일과 내용이 다릅니다.';
    end if;
    raise notice '06_install.sql: 이미 완료, 변경 없이 건너뜀';
    return;
  end if;
  if (select count(*) from vr_staging_install.parts where part_no < 6) <> 5 then
    raise exception 'STOP: 앞 번호 파일을 먼저 실행하세요 (06_install.sql).';
  end if;
  -- 설치 도중에는 클라이언트가 미완성 게임 스키마에 접근하지 못함. 마지막에만 개방.
  revoke usage on schema public from public, anon, authenticated;
  execute $vr_statement$-- 확인: select o->>'src' src, o->>'bound' bound, count(*) from story_progress, jsonb_array_elements(data->'owned') o group by 1, 2 order by 1;


-- ===== SOURCE: trade_drink.sql =====
-- ===== 거래 PR2: 체력의 드링크 🥤 =====
-- 선행: gem.sql (player_wallet.gem_free/gem_paid · _gem_add) · phaseE_2.sql (_player_sync · _player_stamina_add). 여러 번 실행해도 안전
-- 심연석으로 구매 → 거래 가능분(tradable). 무료 심연석을 먼저 쓰고 모자라면 유료 (2026-11-10 BM. 예전에는 유료만).
-- 이벤트·보상·운영 지급 → 귀속분(bound). 거래에 묶인 분(locked)은 거래 PR 에서 사용
-- 행동력 최대 충전(gem_shop.stamina)과는 다른 상품. 드링크 1개 = 행동력 +200, 상한 999.
-- 사용: 1개당 행동력 +200, 최대치를 넘어도 쌓이지만 상한(임시 999)을 넘게는 못 씀. 귀속분부터 사용

create table if not exists public.player_items (
  user_id    uuid not null references auth.users(id) on delete cascade,
  item       text not null check (item in ('drink')),
  tradable   int  not null default 0 check (tradable >= 0),
  bound      int  not null default 0 check (bound >= 0),
  locked     int  not null default 0 check (locked >= 0 and locked <= tradable),
  updated_at timestamptz not null default now(),
  primary key (user_id, item)
);$vr_statement$;
  execute $vr_statement$alter table public.player_items enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.player_items from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create table if not exists public.item_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  item       text not null,
  d_tradable int  not null default 0,
  d_bound    int  not null default 0,
  tradable_after int not null,
  bound_after    int not null,
  reason     text not null check (char_length(reason) <= 40),   -- buy:<sku> · use · event · admin · trade(나중)
  ref        text not null default gen_random_uuid()::text,
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, ref)
);$vr_statement$;
  execute $vr_statement$create index if not exists item_log_user_idx on public.item_log (user_id, created_at desc);$vr_statement$;
  execute $vr_statement$alter table public.item_log enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.item_log from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 판매 상품. price = 심연석 (무료 우선, 그다음 유료). 1/100 · 10/950 · 30/2700
create table if not exists public.drink_shop (
  sku    text primary key,
  qty    int  not null check (qty > 0),
  price  int  not null check (price > 0),
  ord    int  not null default 0,
  active boolean not null default true
);$vr_statement$;
  execute $vr_statement$insert into public.drink_shop (sku, qty, price, ord) values ('drink1', 1, 100, 1), ('drink10', 10, 950, 2), ('drink30', 30, 2700, 3)
on conflict (sku) do nothing;$vr_statement$;
  execute $vr_statement$alter table public.drink_shop enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.drink_shop from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create table if not exists public.drink_config (key text primary key, val int not null);$vr_statement$;
  execute $vr_statement$insert into public.drink_config values ('stamina_per', 200), ('stamina_cap', 999) on conflict (key) do nothing;$vr_statement$;
  execute $vr_statement$alter table public.drink_config enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.drink_config from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._drink_cfg(k text) returns int language sql stable security definer set search_path = public as $$ select val from drink_config where key = k $$;$vr_statement$;
  execute $vr_statement$-- 내부: 증감 + 기록. p_ref 같으면 한 번만
create or replace function public._item_add(p_uid uuid, p_item text, p_trad int, p_bound int, p_reason text, p_ref text, p_meta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r player_items;
begin
  if p_uid is null then raise exception 'login required'; end if;
  insert into player_items (user_id, item) values (p_uid, p_item) on conflict do nothing;
  select * into r from player_items where user_id = p_uid and item = p_item for update;
  if p_ref is not null and exists (select 1 from item_log where user_id = p_uid and ref = p_ref) then return null; end if;
  if r.tradable + coalesce(p_trad, 0) < r.locked or r.bound + coalesce(p_bound, 0) < 0 then raise exception 'not enough drink'; end if;
  update player_items set tradable = tradable + coalesce(p_trad, 0), bound = bound + coalesce(p_bound, 0), updated_at = now()
    where user_id = p_uid and item = p_item returning * into r;
  insert into item_log (user_id, item, d_tradable, d_bound, tradable_after, bound_after, reason, ref, meta)
  values (p_uid, p_item, coalesce(p_trad, 0), coalesce(p_bound, 0), r.tradable, r.bound, left(p_reason, 40), coalesce(p_ref, gen_random_uuid()::text), coalesce(p_meta, '{}'::jsonb));
  return jsonb_build_object('tradable', r.tradable, 'bound', r.bound, 'locked', r.locked, 'total', r.tradable + r.bound);
end $$;$vr_statement$;
  execute $vr_statement$-- 이벤트·보상용 지급 (항상 귀속). 다른 서버 함수에서 perform _drink_grant_bound(uid, n, 'event', 'event:<id>')
create or replace function public._drink_grant_bound(p_uid uuid, p_n int, p_reason text, p_ref text) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if p_n is null or p_n <= 0 then raise exception 'invalid amount'; end if;
  return _item_add(p_uid, 'drink', 0, p_n, p_reason, p_ref, '{}'::jsonb);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._drink_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r player_items; w player_wallet;
begin
  select * into r from player_items where user_id = p_uid and item = 'drink';
  select * into w from player_wallet where user_id = p_uid;
  return jsonb_build_object('ok', true, 'tradable', coalesce(r.tradable, 0), 'bound', coalesce(r.bound, 0), 'locked', coalesce(r.locked, 0),
    'total', coalesce(r.tradable, 0) + coalesce(r.bound, 0), 'paid_gem', coalesce(w.gem_paid, 0), 'free_gem', coalesce(w.gem_free, 0),
    'per', _drink_cfg('stamina_per'), 'cap', _drink_cfg('stamina_cap'),
    'shop', (select coalesce(jsonb_agg(jsonb_build_object('sku', sku, 'qty', qty, 'price', price) order by ord), '[]'::jsonb) from drink_shop where active));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.drink_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  return _drink_json(auth.uid());
end $$;$vr_statement$;
  execute $vr_statement$-- 구매: 무료 심연석을 먼저 쓰고, 모자라면 유료 (gem_shop 행동력 충전과 같은 _gem_spend). 산 드링크는 거래 가능.
create or replace function public.drink_buy(p_sku text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s drink_shop; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  select * into s from drink_shop where sku = p_sku and active;
  if s.sku is null then raise exception 'invalid item'; end if;
  insert into player_wallet (user_id) values (uid) on conflict (user_id) do nothing;
  g := _gem_spend(uid, s.price, 'buy:' || s.sku, jsonb_build_object('qty', s.qty, 'price', s.price));
  perform _item_add(uid, 'drink', s.qty, 0, 'buy:' || s.sku, null, jsonb_build_object('price', s.price));
  return _drink_json(uid) || jsonb_build_object('gem', g, 'bought', s.qty);
end $$;$vr_statement$;
  execute $vr_statement$-- 사용: 귀속분 먼저, 그다음 거래 가능분(묶인 분 제외). 상한을 넘기면 거부
create or replace function public.drink_use(p_n int default 1) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r player_items; ps player_state; per int := _drink_cfg('stamina_per'); cap int := _drink_cfg('stamina_cap'); fb int; ft int; st int;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_n is null or p_n < 1 or p_n > 100 then raise exception 'invalid amount'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  select * into r from player_items where user_id = uid and item = 'drink' for update;
  if r.user_id is null or r.bound + r.tradable - r.locked < p_n then raise exception 'not enough drink'; end if;
  ps := _player_sync(uid);
  if ps.stamina + per * p_n > cap then raise exception 'stamina cap'; end if;
  fb := least(r.bound, p_n); ft := p_n - fb;
  perform _item_add(uid, 'drink', -ft, -fb, 'use', null, jsonb_build_object('n', p_n, 'stamina_before', ps.stamina));
  st := _player_stamina_add(uid, per * p_n);
  return _drink_json(uid) || jsonb_build_object('stamina', st, 'used', p_n);
end $$;$vr_statement$;
  execute $vr_statement$-- 운영 지급 (귀속, 음수면 회수: 귀속분에서만)
create or replace function public.admin_grant_drink(p_user uuid, p_n int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare res jsonb;
begin
  perform public._admin_guard();
  if p_n is null or p_n = 0 or abs(p_n) > 100000 then raise exception 'amount must be ±1..100000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  res := _item_add(p_user, 'drink', 0, p_n, 'admin', null, jsonb_build_object('by', auth.jwt()->>'email', 'memo', left(btrim(p_reason), 200)));
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_drink', p_user, p_n, left(btrim(p_reason), 200), (res->>'bound')::int - p_n, (res->>'bound')::int);
  return res || jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._drink_cfg(text), public._item_add(uuid, text, int, int, text, text, jsonb), public._drink_grant_bound(uuid, int, text, text), public._drink_json(uuid) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.drink_status(), public.drink_buy(text), public.drink_use(int), public.admin_grant_drink(uuid, int, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.drink_status(), public.drink_buy(text), public.drink_use(int), public.admin_grant_drink(uuid, int, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_board.sql =====
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
create table if not exists public.trade_config (key text primary key, val int not null, note text);$vr_statement$;
  execute $vr_statement$insert into public.trade_config (key, val, note) values
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
on conflict (key) do nothing;$vr_statement$;
  execute $vr_statement$-- 등급별 1개당 가격 범위 + 물건끼리 거래 고정 골드 수수료. g_min/g_max null = 골드 불가
create table if not exists public.trade_band (
  gkey text primary key, label text not null, d_min int not null, d_max int not null, g_min int, g_max int, fix_fee int not null
);$vr_statement$;
  execute $vr_statement$insert into public.trade_band values
  ('card_nr',  '인재 N·R',   1,    50,  1000,  20000,   500),
  ('card_hr',  '인재 HR',    5,   200,  5000, 100000,  1000),
  ('card_sr',  '인재 SR',   20,  1000,  null,   null,  3000),
  ('card_ur',  '인재 UR',  100,  3000,  null,   null, 10000),
  ('card_mlr', '인재 MR·LR', 300, 10000, null,  null, 10000),
  ('gear_low', '장비 낡은~고급', 1, 50,  500,  20000,   500),
  ('gear_rare','장비 희귀',  5,   200,  5000,  80000,  1000),
  ('gear_hero','장비 영웅', 20,  1000,  null,   null,  3000)
on conflict (gkey) do nothing;$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['trade_config', 'trade_band'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 2) 글·제안·기록 ------------------------------------------------------------------
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
);$vr_statement$;
  execute $vr_statement$create index if not exists trade_listings_open on public.trade_listings (expires_at) where status = 'open';$vr_statement$;
  execute $vr_statement$create index if not exists trade_listings_seller on public.trade_listings (seller, status);$vr_statement$;
  execute $vr_statement$create table if not exists public.trade_offers (
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
);$vr_statement$;
  execute $vr_statement$create index if not exists trade_offers_listing on public.trade_offers (listing_id, status);$vr_statement$;
  execute $vr_statement$create index if not exists trade_offers_offerer on public.trade_offers (offerer, status);$vr_statement$;
  execute $vr_statement$create unique index if not exists trade_offers_one on public.trade_offers (listing_id, offerer) where status = 'pending';$vr_statement$;
  execute $vr_statement$create table if not exists public.trade_log (
  id         bigint generated always as identity primary key,
  listing_id bigint not null, offer_id bigint not null,
  seller     uuid not null, buyer uuid not null,
  seller_gave jsonb not null, buyer_gave jsonb not null,
  fees       jsonb not null,
  created_at timestamptz not null default now()
);$vr_statement$;
  execute $vr_statement$create index if not exists trade_log_seller on public.trade_log (seller, created_at desc);$vr_statement$;
  execute $vr_statement$create index if not exists trade_log_buyer on public.trade_log (buyer, created_at desc);$vr_statement$;
  execute $vr_statement$do $$ declare t text; begin
  foreach t in array array['trade_listings', 'trade_offers', 'trade_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 우편함 장비: 강화 단계(plus)도 받도록 (기존엔 무시됨)
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.mail_claim(bigint) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.mail_claim(bigint) to authenticated;$vr_statement$;
  execute $vr_statement$-- 3) 내부 도우미 ---------------------------------------------------------------------
create or replace function public._trade_cfg(k text) returns int language sql stable security definer set search_path = public as $$
  select val from trade_config where key = k $$;$vr_statement$;
  execute $vr_statement$create or replace function public._trade_card_gkey(p_card text) returns text language sql stable security definer set search_path = public as $$
  select case coalesce((select grade from story_card_pool where id = p_card), 'NORMAL')
    when 'NORMAL' then 'card_nr' when 'RARE' then 'card_nr' when 'HIGH RARE' then 'card_hr'
    when 'SUPER RARE' then 'card_sr' when 'ULTRA RARE' then 'card_ur' else 'card_mlr' end $$;$vr_statement$;
  execute $vr_statement$create or replace function public._trade_gear_gkey(p_tier int) returns text language sql immutable as $$
  select case when p_tier <= 3 then 'gear_low' when p_tier = 4 then 'gear_rare' when p_tier = 5 then 'gear_hero' else null end $$;$vr_statement$;
  execute $vr_statement$-- 관련 유저 잠금 (항상 uuid 순서 → 교착 없음). 글 행 잠금 다음에 호출
create or replace function public._trade_lock_users(p_uids uuid[]) returns void language plpgsql as $$
declare u uuid;
begin
  for u in select distinct x from unnest(p_uids) x where x is not null order by 1 loop
    perform pg_advisory_xact_lock(hashtext('trade:' || u::text));
  end loop;
end $$;$vr_statement$;
  execute $vr_statement$-- 배열에서 uid 빼기 (문자열 또는 {uid:..} 항목)
create or replace function public._trade_strip(a jsonb, u text) returns jsonb language sql immutable as $$
  select case when jsonb_typeof(a) <> 'array' then a else
    coalesce((select jsonb_agg(x order by k) from jsonb_array_elements(a) with ordinality t(x, k)
              where not (x = to_jsonb(u) or (jsonb_typeof(x) = 'object' and x->>'uid' = u))), '[]'::jsonb) end $$;$vr_statement$;
  execute $vr_statement$-- 계정 조건
create or replace function public._trade_gate(p_uid uuid) returns void language plpgsql security definer set search_path = public as $$
declare lv int;
begin
  if p_uid is null then raise exception 'login required'; end if;
  lv := (_player_sync(p_uid)).level;
  if lv < _trade_cfg('min_level') then raise exception 'trade level'; end if;
  if (select created_at from auth.users where id = p_uid) > now() - make_interval(days => _trade_cfg('min_account_days')) then raise exception 'trade account age'; end if;
end $$;$vr_statement$;
  execute $vr_statement$-- 인재 보관: owned 에서 빼고 [{card, gkey}] 반환. 리더·수동 잠금·귀속·재판매 대기 불가. 덱 자동 잠금(dlk)은 덱에서 빼고 진행
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
end $$;$vr_statement$;
  execute $vr_statement$-- 인재 지급 (p_traded = 거래로 받음 → 재판매 대기 표시)
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
end $$;$vr_statement$;
  execute $vr_statement$-- 장비 보관: 잠금·장착·전설 이상·재판매 대기 불가
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
end $$;$vr_statement$;
  execute $vr_statement$-- 장비 지급: 돌려줄 때는 같은 행 그대로, 거래로 받으면 새 주인·재판매 대기. 가방 꽉 차면 우편함 (30일)
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
end $$;$vr_statement$;
  execute $vr_statement$-- 증표 이동: 보낸 쪽에 같은 인재가 더 없으면 증표(단계)를 받는 쪽으로. 투입 조각 합으로 비교
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
end $$;$vr_statement$;
  execute $vr_statement$-- 제안 환불 (대기 → p_status). 이미 끝난 제안이면 아무것도 안 함
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
end $$;$vr_statement$;
  execute $vr_statement$-- 글 닫기 (취소·만료): 판매자 물건 반환 + 대기 제안 모두 환불. 글 행은 호출 전에 잠가 둘 것
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
end $$;$vr_statement$;
  execute $vr_statement$-- 만료 처리 (주기 작업 + 게시판·내 거래 볼 때 조금씩)
create or replace function public.trade_expire_due(p_limit int default 20) returns int language plpgsql security definer set search_path = public as $$
declare lid bigint; n int := 0;
begin
  for lid in select id from trade_listings where status = 'open' and expires_at <= now() order by expires_at limit greatest(1, least(p_limit, 200)) for update skip locked loop
    perform _trade_close_listing(lid, 'expired'); n := n + 1;
  end loop;
  return n;
end $$;$vr_statement$;
  execute $vr_statement$-- 가격·골드 검사. p_l = 글 물건 [{gkey}], p_o = 제안 물건, 재화는 제안 쪽에만
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
end $$;$vr_statement$;
  execute $vr_statement$-- 4) 공개 RPC -------------------------------------------------------------------------
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
end $$;$vr_statement$;
  execute $vr_statement$-- 제안
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
end $$;$vr_statement$;
  execute $vr_statement$-- 제안 취소 (제안자)
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
end $$;$vr_statement$;
  execute $vr_statement$-- 글 내리기 (판매자)
create or replace function public.trade_cancel(p_listing bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); l trade_listings; n int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into l from trade_listings where id = p_listing for update;
  if l.id is null or l.seller <> uid then raise exception 'listing not found'; end if;
  if l.status <> 'open' then raise exception 'listing closed'; end if;
  n := _trade_close_listing(l.id, 'cancelled');
  return jsonb_build_object('ok', true, 'refunded', n);
end $$;$vr_statement$;
  execute $vr_statement$-- 거절: 고른 제안들 (판매자, 최대 bulk_max)
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
end $$;$vr_statement$;
  execute $vr_statement$-- 조건 아래 전부 거절: 드링크 < p_min_drinks · 골드 < p_min_gold · 물건 없는 제안 (넘긴 조건 중 하나라도 맞으면)
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
end $$;$vr_statement$;
  execute $vr_statement$-- 수락 (판매자): 한 번에 교환, 수수료 소각, 나머지 제안 환불
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
end $$;$vr_statement$;
  execute $vr_statement$-- 게시판 (열린 글, 내 글 제외 아님). 제안 내용은 비공개, 개수만
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
end $$;$vr_statement$;
  execute $vr_statement$-- 내 거래: 내 글(들어온 제안 전체) + 내 제안 + 최근 기록
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
end $$;$vr_statement$;
  execute $vr_statement$-- 5) 권한 -----------------------------------------------------------------------------
revoke all on function public._trade_cfg(text), public._trade_card_gkey(text), public._trade_gear_gkey(int), public._trade_lock_users(uuid[]), public._trade_strip(jsonb, text),
  public._trade_gate(uuid), public._trade_take_cards(uuid, text[]), public._trade_give_cards(uuid, jsonb, boolean), public._trade_take_gear(uuid, bigint[]),
  public._trade_give_gear(uuid, jsonb, boolean), public._trade_sigil_move(uuid, uuid, text), public._trade_refund_offer(bigint, text),
  public._trade_close_listing(bigint, text), public._trade_check_price(jsonb, jsonb, int, bigint), public.trade_expire_due(int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.trade_list(text[], bigint[], text), public.trade_offer(bigint, text[], bigint[], int, bigint), public.trade_offer_cancel(bigint),
  public.trade_cancel(bigint), public.trade_reject(bigint, bigint[]), public.trade_reject_below(bigint, int, bigint, boolean), public.trade_accept(bigint, bigint),
  public.trade_board(int, bigint), public.trade_my() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.trade_list(text[], bigint[], text), public.trade_offer(bigint, text[], bigint[], int, bigint), public.trade_offer_cancel(bigint),
  public.trade_cancel(bigint), public.trade_reject(bigint, bigint[]), public.trade_reject_below(bigint, int, bigint, boolean), public.trade_accept(bigint, bigint),
  public.trade_board(int, bigint), public.trade_my() to authenticated;$vr_statement$;
  execute $vr_statement$-- 주기 만료 (pg_cron 이 있으면 10분마다)
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'trade_expire';
    perform cron.schedule('trade_expire', '*/10 * * * *', 'select public.trade_expire_due(200)');
  end if;
exception when others then raise notice 'trade_expire cron skipped: %', sqlerrm;
end $$;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: trade_admin.sql =====
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
on conflict (key) do nothing;$vr_statement$;
  execute $vr_statement$create table if not exists public.trade_flags (
  id         bigint generated always as identity primary key,
  log_id     bigint not null references public.trade_log(id) on delete cascade,
  kind       text not null check (kind in ('repeat_pair', 'band_edge', 'new_account', 'lopsided')),
  detail     jsonb not null default '{}'::jsonb,
  reviewed_at timestamptz, reviewed_by text, note text check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  unique (log_id, kind)
);$vr_statement$;
  execute $vr_statement$create index if not exists trade_flags_open on public.trade_flags (created_at desc) where reviewed_at is null;$vr_statement$;
  execute $vr_statement$alter table public.trade_flags enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.trade_flags from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$create or replace function public._trade_day_start() returns timestamptz language sql stable as $$
  select ((now() at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul') $$;$vr_statement$;
  execute $vr_statement$-- 하루 보낸/받은 드링크 (완료 거래 기준: 제안자가 보냄, 판매자가 받음)
create or replace function public._trade_drinks_today(p_uid uuid, p_dir text) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum((buyer_gave->>'drinks')::bigint), 0) from trade_log
   where created_at >= _trade_day_start() and case when p_dir = 'send' then buyer = p_uid else seller = p_uid end $$;$vr_statement$;
  execute $vr_statement$-- 제안 넣을 때: 취소 남발 · 보내기 한도
create or replace function public._trade_offer_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from trade_offers where offerer = new.offerer and status = 'cancelled' and closed_at >= _trade_day_start()) >= _trade_cfg('daily_cancels') then
    raise exception 'cancel limit'; end if;
  if new.drinks > 0 and _trade_drinks_today(new.offerer, 'send') + new.drinks > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists trade_offer_guard on public.trade_offers;$vr_statement$;
  execute $vr_statement$create trigger trade_offer_guard before insert on public.trade_offers for each row execute function public._trade_offer_guard();$vr_statement$;
  execute $vr_statement$-- 거래 기록 때: 받기·보내기 한도 (넘으면 수락 전체 취소) + 의심 표시
create or replace function public._trade_log_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare d bigint := coalesce((new.buyer_gave->>'drinks')::bigint, 0);
begin
  if d > 0 then
    if _trade_drinks_today(new.seller, 'recv') + d > _trade_cfg('daily_drink_recv') then raise exception 'drink recv limit'; end if;
    if _trade_drinks_today(new.buyer, 'send') + d > _trade_cfg('daily_drink_send') then raise exception 'drink send limit'; end if;
  end if;
  return new;
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists trade_log_guard on public.trade_log;$vr_statement$;
  execute $vr_statement$create trigger trade_log_guard before insert on public.trade_log for each row execute function public._trade_log_guard();$vr_statement$;
  execute $vr_statement$-- 가치 (드링크 기준): 등급 범위 가운데 값 합
create or replace function public._trade_value(p_items jsonb) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum((b.d_min + b.d_max) / 2.0), 0) from jsonb_array_elements(coalesce(p_items, '[]')) x join trade_band b on b.gkey = x->>'gkey' $$;$vr_statement$;
  execute $vr_statement$create or replace function public._trade_log_flag() returns trigger language plpgsql security definer set search_path = public as $$
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
end $$;$vr_statement$;
  execute $vr_statement$drop trigger if exists trade_log_flag on public.trade_log;$vr_statement$;
  execute $vr_statement$create trigger trade_log_flag after insert on public.trade_log for each row execute function public._trade_log_flag();$vr_statement$;
  execute $vr_statement$-- ---- 관리자 ------------------------------------------------------------------------
create or replace function public._trade_admin_log(p_action text, p_user uuid, p_amount int, p_reason text, p_before int, p_after int) returns void language plpgsql security definer set search_path = public, auth as $$
begin
  insert into admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), coalesce(auth.jwt()->>'email', ''), p_action, p_user, p_amount, left(p_reason, 200), p_before, p_after);
end $$;$vr_statement$;
  execute $vr_statement$-- 거래 기록 (유저 지정 가능)
create or replace function public.admin_trade_log(p_user uuid default null, p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'listing_id', l.listing_id, 'offer_id', l.offer_id, 'at', l.created_at,
      'seller', l.seller, 'seller_email', (select email from auth.users where id = l.seller), 'buyer', l.buyer, 'buyer_email', (select email from auth.users where id = l.buyer),
      'seller_gave', l.seller_gave, 'buyer_gave', l.buyer_gave, 'fees', l.fees,
      'flags', (select coalesce(jsonb_agg(f.kind), '[]'::jsonb) from trade_flags f where f.log_id = l.id)) order by l.id desc), '[]'::jsonb)
    from (select * from trade_log where p_user is null or seller = p_user or buyer = p_user order by id desc limit greatest(1, least(p_limit, 500))) l);
end $$;$vr_statement$;
  execute $vr_statement$-- 글·제안 (유저 지정 가능, 상태 필터)
create or replace function public.admin_trade_listings(p_user uuid default null, p_status text default null, p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'status', l.status, 'seller', l.seller, 'seller_email', (select email from auth.users where id = l.seller),
      'cards', l.cards, 'gear', l.gear, 'want', l.want, 'created_at', l.created_at, 'expires_at', l.expires_at,
      'offers', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status, 'offerer', o.offerer, 'email', (select email from auth.users where id = o.offerer),
                   'cards', o.cards, 'gear', o.gear, 'drinks', o.drinks, 'gold', o.gold, 'fee_gold', o.fee_gold, 'at', o.created_at) order by o.id), '[]'::jsonb) from trade_offers o where o.listing_id = l.id)) order by l.id desc), '[]'::jsonb)
    from (select * from trade_listings x where (p_user is null or x.seller = p_user or exists (select 1 from trade_offers o where o.listing_id = x.id and o.offerer = p_user))
            and (p_status is null or x.status = p_status) order by id desc limit greatest(1, least(p_limit, 300))) l);
end $$;$vr_statement$;
  execute $vr_statement$-- 의심 거래
create or replace function public.admin_trade_flags(p_open_only boolean default true, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'log_id', f.log_id, 'kind', f.kind, 'detail', f.detail, 'at', f.created_at, 'reviewed_at', f.reviewed_at, 'reviewed_by', f.reviewed_by, 'note', f.note,
      'seller_email', (select email from auth.users where id = l.seller), 'buyer_email', (select email from auth.users where id = l.buyer), 'seller', l.seller, 'buyer', l.buyer,
      'buyer_gave', l.buyer_gave, 'seller_gave', l.seller_gave) order by f.id desc), '[]'::jsonb)
    from (select * from trade_flags where not p_open_only or reviewed_at is null order by id desc limit greatest(1, least(p_limit, 500))) f join trade_log l on l.id = f.log_id);
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_trade_flag_review(p_id bigint, p_note text) returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  update trade_flags set reviewed_at = now(), reviewed_by = auth.jwt()->>'email', note = left(coalesce(btrim(p_note), ''), 200) where id = p_id;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('ok', true);
end $$;$vr_statement$;
  execute $vr_statement$-- 같은 상대 반복 상위
create or replace function public.admin_trade_pairs(p_days int default 7, p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return (select coalesce(jsonb_agg(jsonb_build_object('a', a, 'b', b, 'a_email', (select email from auth.users where id = a), 'b_email', (select email from auth.users where id = b),
      'trades', n, 'drinks', dr, 'gold', gd, 'last', last) order by n desc, dr desc), '[]'::jsonb)
    from (select least(seller, buyer) a, greatest(seller, buyer) b, count(*) n, sum(coalesce((buyer_gave->>'drinks')::bigint, 0)) dr, sum(coalesce((buyer_gave->>'gold')::bigint, 0)) gd, max(created_at) last
            from trade_log where created_at > now() - make_interval(days => greatest(1, least(p_days, 90))) group by 1, 2 having count(*) >= 2 order by n desc limit greatest(1, least(p_limit, 200))) x);
end $$;$vr_statement$;
  execute $vr_statement$-- 글 강제 내림: 판매 물건 반환 + 대기 제안 모두 환불
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
end $$;$vr_statement$;
  execute $vr_statement$-- 제안 강제 환불
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
end $$;$vr_statement$;
  execute $vr_statement$-- 조절표 보기·수정
create or replace function public.admin_trade_config() returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform _admin_guard();
  return jsonb_build_object('config', (select jsonb_agg(to_jsonb(c) order by key) from trade_config c), 'bands', (select jsonb_agg(to_jsonb(b) order by gkey) from trade_band b));
end $$;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_trade_config_set(p_key text, p_val int, p_reason text) returns jsonb language plpgsql security definer set search_path = public, auth as $$
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
end $$;$vr_statement$;
  execute $vr_statement$-- 등급 범위 수정 (p_field = d_min · d_max · g_min · g_max · fix_fee, g_* 는 null 로 골드 불가)
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
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._trade_day_start(), public._trade_drinks_today(uuid, text), public._trade_offer_guard(), public._trade_log_guard(), public._trade_value(jsonb),
  public._trade_log_flag(), public._trade_admin_log(text, uuid, int, text, int, int) from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_trade_log(uuid, int), public.admin_trade_listings(uuid, text, int), public.admin_trade_flags(boolean, int), public.admin_trade_flag_review(bigint, text),
  public.admin_trade_pairs(int, int), public.admin_trade_void_listing(bigint, text), public.admin_trade_refund_offer(bigint, text), public.admin_trade_config(),
  public.admin_trade_config_set(text, int, text), public.admin_trade_band_set(text, text, int, text) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_trade_log(uuid, int), public.admin_trade_listings(uuid, text, int), public.admin_trade_flags(boolean, int), public.admin_trade_flag_review(bigint, text),
  public.admin_trade_pairs(int, int), public.admin_trade_void_listing(bigint, text), public.admin_trade_refund_offer(bigint, text), public.admin_trade_config(),
  public.admin_trade_config_set(text, int, text), public.admin_trade_band_set(text, text, int, text) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: card_10435.sql =====
-- =====================================================================
-- 2026-10-27 카드 정리: 이름 변경 3명 + 신규 카드 하승진(10435). 여러 번 실행해도 안전.
--   10053 최창원 → 김대욱 · 10054 최창민 → 김동욱 · 10051 지세강 → 김기림
--   (서성민 SUPPORT 변경은 클라이언트 데이터만 — DB 변경 없음)
-- =====================================================================

-- 1) 카드 풀 이름 + 신규 카드 (뽑기 대상)
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10051','ULTRA RARE','김기림',true),
  ('10054','ULTRA RARE','김동욱',true),
  ('10053','ULTRA RARE','김대욱',true),
  ('10435','ULTRA RARE','하승진',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;$vr_statement$;
  execute $vr_statement$-- 2) 스킬 해금 레벨 (스킬 레벨업 서버 검증용)
insert into public.story_skill_meta (card_id, idx, unlock) values
  ('10435',1,2),
  ('10435',2,5),
  ('10435',3,7)
on conflict (card_id, idx) do update set unlock = excluded.unlock;$vr_statement$;
  execute $vr_statement$-- 3) PVP 덱 검증용 등급·코스트
insert into public.pvp_card_meta (id, grade, cost) values
  ('10435','ULTRA RARE',50)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: card_id_remap.sql =====
create table if not exists public.card_id_alias (old_id text primary key, new_id text not null unique, name text);$vr_statement$;
  execute $vr_statement$alter table public.card_id_alias enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.card_id_alias from anon, authenticated;$vr_statement$;
  execute $vr_statement$grant select on public.card_id_alias to anon, authenticated;$vr_statement$;
  execute $vr_statement$drop policy if exists "alias_read" on public.card_id_alias;$vr_statement$;
  execute $vr_statement$create policy "alias_read" on public.card_id_alias for select using (true);$vr_statement$;
  execute $vr_statement$insert into public.card_id_alias (old_id, new_id, name) values
  ('1000300054','10001','가윤우'),
  ('2000300055','10002','강나빛'),
  ('2000700138','10003','강리안'),
  ('1000800169','10004','강명준'),
  ('1001000214','10005','강상'),
  ('2001200244','10006','강서언'),
  ('2000000005','10007','강세연'),
  ('1001400250','10008','강승헌'),
  ('1001900349','10009','강신'),
  ('1000200042','10010','강우섭'),
  ('2000800173','10011','강유영'),
  ('2002000354','10012','강재아'),
  ('1002000355','10013','강준철'),
  ('2000600118','10014','강지민'),
  ('1001500307','10015','강철진'),
  ('1001400273','10016','강철하'),
  ('1001500306','10017','강철훈'),
  ('1000100010','10018','강태안'),
  ('1000100009','10019','강태준'),
  ('1000200037','10020','강한길'),
  ('1001600328','10021','경원석'),
  ('2001400251','10022','고명희'),
  ('1000800192','10023','고병헌'),
  ('2002400374','10024','고세린'),
  ('1000600125','10025','고정태'),
  ('1000200049','10026','고차연'),
  ('1000300075','10027','고한홍'),
  ('1001500310','10028','공윤성'),
  ('2000900229','10029','공주연'),
  ('2001500309','10030','공태인'),
  ('1000300072','10031','곽명구'),
  ('1001400256','10032','곽민수'),
  ('1000300076','10033','곽재준'),
  ('1001700337','10034','곽제형'),
  ('1000600127','10035','곽진영'),
  ('1000400101','10036','곽태우'),
  ('1000300071','10037','구성원'),
  ('1001500301','10038','국태원'),
  ('2000800167','10039','권두리'),
  ('2000900203','10040','권예강'),
  ('2000900214','10041','권예리'),
  ('2000900204','10042','권예진'),
  ('2000700162','10043','권지아'),
  ('2000700161','10044','권지우'),
  ('1000400092','10045','금어진'),
  ('1001600318','10046','금유진'),
  ('2000200023','10047','길선재'),
  ('1000200022','10048','길윤재'),
  ('1000200021','10049','길정재'),
  ('2001900350','10050','김가람'),
  ('1000200018','10051','김기림'),
  ('2000900225','10052','김나현'),
  ('1002100371','10053','김대욱'),
  ('1001500315','10054','김동욱'),
  ('1001900351','10055','김들'),
  ('2000900213','10056','김미윤'),
  ('1002100360','10057','김민규'),
  ('2000000001','10058','김백중'),
  ('2000800191','10059','김샛별'),
  ('1000200030','10060','김성진'),
  ('2000700146','10061','김소영'),
  ('2000900234','10062','김신현'),
  ('2000900224','10063','김예빈'),
  ('1000300057','10064','김자근'),
  ('1001400245','10065','김재량'),
  ('1001600319','10066','김재민'),
  ('1001000213','10067','김재섭'),
  ('2001400246','10068','김재신'),
  ('1000600133','10069','김정한'),
  ('1002100366','10070','김준기'),
  ('1000200032','10071','김준하'),
  ('2000100005','10072','김지수'),
  ('2002000352','10073','김지우'),
  ('1000100012','10074','김철민'),
  ('1000400102','10075','김철중'),
  ('1000400091','10076','김철하'),
  ('1001100236','10077','김한결'),
  ('2001100237','10078','김한별'),
  ('2000300069','10079','김현진'),
  ('1000100013','10080','김홍민'),
  ('1000600120','10081','김후'),
  ('1000000033','10082','김후 환영'),
  ('2000300068','10083','김희건'),
  ('2001100238','10084','나윤아'),
  ('2001100239','10085','나윤영'),
  ('1000200033','10086','남경택'),
  ('2000200027','10087','남고은'),
  ('1000700137','10088','남궁무열'),
  ('1001400266','10089','남궁형남'),
  ('2000900219','10090','남다연'),
  ('2000900218','10091','남다윤'),
  ('2000800183','10092','남소연'),
  ('2001700341','10093','남태은'),
  ('1001400268','10094','노재범'),
  ('2000700139','10095','노정아'),
  ('2000700140','10096','노정은'),
  ('2000900236','10097','동지선'),
  ('1000500112','10098','두윤창'),
  ('2000700159','10099','류장미'),
  ('2001100220','10100','류태연'),
  ('2000700158','10101','류하늘'),
  ('2000800181','10102','류하늬'),
  ('2000200031','10103','류하예'),
  ('2000900231','10104','류햇빛'),
  ('1001100228','10105','마하랑'),
  ('1002100357','10106','마형은'),
  ('1001400255','10107','문동혁'),
  ('2000400098','10108','문유선'),
  ('1001500305','10109','문재'),
  ('2000600115','10110','문지아'),
  ('2000600126','10111','문지예'),
  ('1000600130','10112','문지철'),
  ('1002100367','10113','문철재'),
  ('1000200046','10114','문희찬'),
  ('2000100008','10115','민유연'),
  ('2000000045','10116','[염원] 민유연'),
  ('2001100235','10117','민지은'),
  ('1000100007','10118','민홍기'),
  ('1001700340','10119','박미르'),
  ('2000700157','10120','박보라'),
  ('2000800176','10121','박샘'),
  ('2000900228','10122','박설이'),
  ('1002400377','10123','박성관'),
  ('1000300067','10124','박언석'),
  ('1000600124','10125','박오류'),
  ('2000900233','10126','박인아'),
  ('2000000013','10127','박인영'),
  ('1001500289','10128','박태욱'),
  ('2000600117','10129','박혜안'),
  ('2001100231','10130','반지아'),
  ('2001100232','10131','반지윤'),
  ('2000200026','10132','배나빛'),
  ('2000900217','10133','배수연'),
  ('1000300070','10134','배승규'),
  ('2001400267','10135','백버들'),
  ('1001500286','10136','백천주'),
  ('1000200035','10137','복광준'),
  ('1000200036','10138','복광훈'),
  ('1000800182','10139','복규철'),
  ('2000800174','10140','복선아'),
  ('2000900216','10141','복정아'),
  ('1001400258','10142','봉우람'),
  ('1000000023','10143','불량배-A'),
  ('1000000024','10144','불량배-B'),
  ('1000000025','10145','불량배-C'),
  ('1000000026','10146','불량배-D'),
  ('1000000027','10147','불량배-E'),
  ('1000000028','10148','불량배-F'),
  ('1000000029','10149','불량배-G'),
  ('1000000030','10150','불량배-H'),
  ('1000000031','10151','불량배-I'),
  ('1000000032','10152','불량배-J'),
  ('2000000023','10153','불량배-K'),
  ('2000000024','10154','불량배-L'),
  ('2000000025','10155','불량배-M'),
  ('2000000026','10156','불량배-N'),
  ('2000000027','10157','불량배-O'),
  ('2000000028','10158','불량배-P'),
  ('2000000029','10159','불량배-Q'),
  ('2000000030','10160','불량배-R'),
  ('2000000031','10161','불량배-S'),
  ('2000000032','10162','불량배-T'),
  ('2000000033','10163','불량배-U'),
  ('2000000034','10164','불량배-V'),
  ('2000000035','10165','불량배-W'),
  ('2000000036','10166','불량배-X'),
  ('2000000037','10167','불량배-Y'),
  ('2000000038','10168','불량배-Z'),
  ('1000200034','10169','사주혁'),
  ('1001500288','10170','사진태'),
  ('1001700338','10171','서경석'),
  ('2000400104','10172','서규안'),
  ('1000400103','10173','서규인'),
  ('2000900227','10174','서미나'),
  ('2000000004','10175','서민아'),
  ('1002200372','10176','서성민'),
  ('2001100225','10177','서아란'),
  ('2001100226','10178','서아리'),
  ('2001400259','10179','서애정'),
  ('1000300073','10180','서영석'),
  ('1001500311','10181','서오성'),
  ('1001500285','10182','서진성'),
  ('1000300056','10183','서태우'),
  ('2000200029','10184','서하윤'),
  ('2000400085','10185','선나영'),
  ('2000400094','10186','선미영'),
  ('1000500113','10187','선영운'),
  ('2000200025','10188','선우민아'),
  ('1000200024','10189','선우민철'),
  ('2000900226','10190','선유린'),
  ('1000200050','10191','선인구'),
  ('2001700339','10192','설달'),
  ('2000700156','10193','설지원'),
  ('2000800184','10194','설하늘'),
  ('1001600320','10195','성재수'),
  ('2000000041','10196','소녀1'),
  ('2000000042','10197','소녀2'),
  ('2000000043','10198','소녀3'),
  ('2000000044','10199','소녀4'),
  ('1002400375','10200','소민섭'),
  ('1000300063','10201','소석준'),
  ('2000200028','10202','손란'),
  ('2000900235','10203','손혜연'),
  ('2000700152','10204','송다혜'),
  ('1000800180','10205','송동혁'),
  ('2001400269','10206','송예빈'),
  ('2000900206','10207','송지아'),
  ('2000900207','10208','송지은'),
  ('1001500287','10209','송철순'),
  ('1000000022','10210','수상한 남자'),
  ('2000700155','10211','신단비'),
  ('1001100240','10212','신성진'),
  ('2000000003','10213','신시은'),
  ('2001400261','10214','신아린'),
  ('2001400260','10215','신아윤'),
  ('2001100242','10216','신아은'),
  ('2001100241','10217','신예은'),
  ('1001500295','10218','신재'),
  ('2002100362','10219','신주원'),
  ('1002100361','10220','신주호'),
  ('2000800172','10221','신지아'),
  ('2000800188','10222','심버들'),
  ('2001400262','10223','안다미'),
  ('2001500294','10224','안리'),
  ('1000300060','10225','안용태'),
  ('1001800344','10226','안재수'),
  ('2001400277','10227','안주연'),
  ('1000200039','10228','안중산'),
  ('2002000353','10229','안지수'),
  ('2001400276','10230','안지연'),
  ('2001800345','10231','안지윤'),
  ('2000900230','10232','안태영'),
  ('1001700336','10233','안현'),
  ('1002400376','10234','안호선'),
  ('2000600123','10235','안희숙'),
  ('2000800179','10236','양겨울'),
  ('2000900205','10237','양서진'),
  ('2001400275','10238','양소영'),
  ('2000700166','10239','양유영'),
  ('2001400270','10240','양제림'),
  ('2000700160','10241','양주영'),
  ('2001600321','10242','양지림'),
  ('2001800343','10243','연재은'),
  ('1000300078','10244','염상휘'),
  ('1000300079','10245','염태영'),
  ('2000700151','10246','예민지'),
  ('2000800170','10247','예유나'),
  ('2000800171','10248','예유진'),
  ('2000900223','10249','예은아'),
  ('2001400249','10250','예햇빛'),
  ('1001500304','10251','예현승'),
  ('1000600121','10252','오명준'),
  ('2000700145','10253','오빛나'),
  ('2000800187','10254','오샘나'),
  ('2000900215','10255','오설화'),
  ('2000100006','10256','오유나'),
  ('2000000006','10257','오채원'),
  ('2000900212','10258','오한설'),
  ('1001100219','10259','오한음'),
  ('2000100002','10260','오희진'),
  ('2000400106','10261','온리연'),
  ('2000400105','10262','온리윤'),
  ('2000900222','10263','온유진'),
  ('2001100223','10264','왕유영'),
  ('2000200044','10265','용지혜'),
  ('2000200045','10266','용지효'),
  ('2000000040','10267','유가을'),
  ('2001400264','10268','유나리'),
  ('2001400263','10269','유아리'),
  ('2000600131','10270','유진산'),
  ('2000600136','10271','유진아'),
  ('2001100234','10272','유진이'),
  ('2000700144','10273','유태이'),
  ('2001700335','10274','유한결'),
  ('1000300065','10275','유형수'),
  ('1001100218','10276','유혜운'),
  ('2001100217','10277','유혜윰'),
  ('1001500303','10278','윤남규'),
  ('1000300059','10279','윤동훈'),
  ('2001100215','10280','윤미리내'),
  ('2001400279','10281','윤믿음'),
  ('2000000010','10282','윤샛별'),
  ('1001600322','10283','윤석구'),
  ('1001600323','10284','윤석팔'),
  ('2000600134','10285','윤세정'),
  ('2000700143','10286','윤수영'),
  ('1001500283','10287','윤우람'),
  ('2000000009','10288','윤은별'),
  ('2000300066','10289','윤정하'),
  ('2000500110','10290','윤진아'),
  ('2000000007','10291','[각성] 윤진아'),
  ('1000400090','10292','윤태민'),
  ('1000200041','10293','윤태영'),
  ('2000900211','10294','윤태희'),
  ('2000400095','10295','윤희지'),
  ('2000700150','10296','이누리'),
  ('2000400096','10297','이로하'),
  ('1000600122','10298','이명진'),
  ('1000100011','10299','이민수'),
  ('2000100003','10300','이민채'),
  ('2000000022','10301','[각성] 이민채'),
  ('2000000039','10302','[염원] 이민채'),
  ('2000900208','10303','이믿음'),
  ('1002400378','10304','이성호'),
  ('2002100365','10305','이소진'),
  ('2000600132','10306','이영아'),
  ('1001900346','10307','이영하'),
  ('2000400086','10308','이윤이'),
  ('1002100364','10309','이재덕'),
  ('2000800168','10310','이제원'),
  ('2001500316','10311','이지영'),
  ('2001700342','10312','이진경'),
  ('1002100356','10313','이진규'),
  ('1001500299','10314','이진우'),
  ('1000200048','10315','이찬열'),
  ('1002100358','10316','이택길'),
  ('2000400097','10317','이혜경'),
  ('1001700331','10318','이호준'),
  ('1000600119','10319','이후남'),
  ('1001600325','10320','인창민'),
  ('1001600324','10321','인창수'),
  ('2000700165','10322','임규리'),
  ('2000300083','10323','임나리'),
  ('2001100243','10324','임예리'),
  ('2000100001','10325','임유리'),
  ('2000000008','10326','[각성] 임유리'),
  ('2000700142','10327','임조은'),
  ('1000500108','10328','임창수'),
  ('1000500109','10329','임창열'),
  ('2000900221','10330','임한빈'),
  ('2001400248','10331','임혜리'),
  ('1000300062','10332','장동만'),
  ('1001500313','10333','장무영'),
  ('2100000002','10334','장서아'),
  ('2100000001','10335','장서현'),
  ('2000300081','10336','장세유'),
  ('1001500300','10337','장승헌'),
  ('2000300080','10338','장아유'),
  ('2000100017','10339','장은채'),
  ('1002100363','10340','장제훈'),
  ('2001100233','10341','장초롱'),
  ('2000700141','10342','장혜린'),
  ('2000600135','10343','전미성'),
  ('2000900220','10344','전민강'),
  ('1001600327','10345','전민진'),
  ('1000300064','10346','전성국'),
  ('1000800189','10347','전수양'),
  ('2000100015','10348','전잔디'),
  ('1001500298','10349','전주일'),
  ('1001400271','10350','전중혁'),
  ('1000000005','10351','전필수'),
  ('2001100216','10352','전하나'),
  ('1000300077','10353','전호영'),
  ('2000800186','10354','정다윤'),
  ('2000000015','10355','정미선'),
  ('2001700334','10356','정새론'),
  ('2000600128','10357','정서영'),
  ('1000000004','10358','정석윤'),
  ('2000800197','10359','정아람'),
  ('2000600129','10360','정아영'),
  ('2000800185','10361','정아윤'),
  ('2000900198','10362','정연아'),
  ('2000900200','10363','정영아'),
  ('1002100368','10364','정재헌'),
  ('1001500302','10365','정종일'),
  ('1001400272','10366','정지석'),
  ('2000000016','10367','정지선'),
  ('1000000002','10368','정치성'),
  ('1000000003','10369','정치욱'),
  ('1000000001','10370','정치환'),
  ('1001600326','10371','정태진'),
  ('2001100229','10372','정하나'),
  ('2001100230','10373','정하루'),
  ('1001500293','10374','정한서'),
  ('1000100016','10375','정형준'),
  ('2000700163','10376','정혜원'),
  ('2000700164','10377','정혜진'),
  ('2000900232','10378','제갈민영'),
  ('1002400384','10379','제갈버들'),
  ('1000200043','10380','조승규'),
  ('2001400257','10381','조아린'),
  ('2001500297','10382','조영애'),
  ('2000500114','10383','조윤이'),
  ('2000500111','10384','조윤하'),
  ('1001400274','10385','조주열'),
  ('1001100227','10386','조한얼'),
  ('2001400278','10387','주서영'),
  ('2000800175','10388','주서형'),
  ('2001100222','10389','주슬기'),
  ('1000300074','10390','주연욱'),
  ('2001500312','10391','주예나'),
  ('2001500314','10392','주예린'),
  ('2001500308','10393','주예서'),
  ('2000200019','10394','지세련'),
  ('2000000002','10395','지유현'),
  ('1000000009','10396','지주현'),
  ('2001600317','10397','진교진'),
  ('1001600330','10398','진수열'),
  ('2001900347','10399','진하린'),
  ('2001400247','10400','채예린'),
  ('1000200047','10401','채훈기'),
  ('1001900348','10402','천재황'),
  ('2000400084','10403','천혜원'),
  ('1000200020','10404','최강수'),
  ('2000000011','10405','최겨울'),
  ('1000500107','10406','최국선'),
  ('1000400100','10407','최대운'),
  ('1000800178','10408','최두길'),
  ('1000400093','10409','최민우'),
  ('1002100369','10410','최봉근'),
  ('2002400383','10411','최여진'),
  ('2000900202','10412','최유안'),
  ('2000400087','10413','최윤아'),
  ('2000400089','10414','최윤정'),
  ('2000400088','10415','최윤희'),
  ('1002100359','10416','최재홍'),
  ('2000400099','10417','최정인'),
  ('2000300082','10418','최지연'),
  ('1002100370','10419','최진규'),
  ('1000800177','10420','최한길'),
  ('1000000008','10421','최훈남'),
  ('1000000007','10422','최훈필'),
  ('2001500284','10423','추나리'),
  ('1001600329','10424','추정욱'),
  ('1001400252','10425','탁동탁'),
  ('2001400254','10426','탁동혜'),
  ('2002400382','10427','탁리'),
  ('2000800193','10428','탁세은'),
  ('2000700154','10429','탁희원'),
  ('1002400381','10430','표오성'),
  ('1000300061','10431','표정재'),
  ('2000800196','10432','표지아'),
  ('1001500290','10433','풍건'),
  ('1002400380','10434','풍힘찬'),
  ('1100000001','10435','하승진'),
  ('2000900201','10436','하윤하'),
  ('2001400253','10437','하장미'),
  ('2001100224','10438','하지연'),
  ('2000000014','10439','하지은'),
  ('2000000017','10440','하지혜'),
  ('1001500296','10441','하혁'),
  ('2000600116','10442','한겨울'),
  ('2002300373','10443','한믿음'),
  ('1000300058','10444','한석열'),
  ('1000100014','10445','한재'),
  ('2002400379','10446','한하루'),
  ('2000700153','10447','허동아'),
  ('1001000212','10448','허성'),
  ('1000000006','10449','허요한'),
  ('2000800195','10450','허유란'),
  ('2001100221','10451','허유리'),
  ('2000000012','10452','허유희'),
  ('1000200040','10453','허재철'),
  ('2000900199','10454','허진서'),
  ('2001500282','10455','홍가영'),
  ('2001500291','10456','홍나영'),
  ('2001500292','10457','홍다영'),
  ('1001700332','10458','황기훈'),
  ('2000700148','10459','황다미'),
  ('2000700147','10460','황다영'),
  ('2000700149','10461','황다윤'),
  ('2000100004','10462','황보예'),
  ('1000200038','10463','황보재규'),
  ('1001700333','10464','황보훈'),
  ('2000200051','10465','황예영'),
  ('2000200053','10466','황예은'),
  ('2000900210','10467','황은아'),
  ('2000900209','10468','황은채'),
  ('1000200052','10469','황준태'),
  ('2000800190','10470','황지수'),
  ('2000800194','10471','황지은'),
  ('2001500281','10472','황진'),
  ('2001400265','10473','황한결'),
  ('1001500280','10474','황혁')
on conflict (old_id) do nothing;$vr_statement$;
  execute $vr_statement$create or replace function public._war_npc_deck(p_seed text, p_scale numeric) returns jsonb language plpgsql stable as $$
declare hr text[] := array['10151','10152','10163','10164','10165','10166','10167','10168'];
        r text[] := array['10148','10149','10150','10159','10160','10161','10162'];
        male text[] := array['10148','10149','10150','10151','10152'];   -- 성별은 ID 첫 자리가 아니라 카드 데이터(gender)로 (ID 변경 후에도 맞게)
        a text[]; b text[]; ids text[]; alt text; out jsonb := '[]'::jsonb; i int;
begin
  select array_agg(x order by md5(p_seed || ':h:' || x)) into a from unnest(hr) x;
  select array_agg(x order by md5(p_seed || ':r:' || x)) into b from unnest(r) x;
  ids := a[1:2] || b[1:3];
  if (select count(distinct (x = any(male))) from unnest(ids) x) < 2 then
    select x into alt from unnest(b[4:7]) x where (x = any(male)) <> (ids[1] = any(male)) limit 1;
    ids[5] := alt;
  end if;
  for i in 1..5 loop out := out || jsonb_build_object('uid', 'n' || i, 'id', ids[i], 'level', (_war_numbers()->>'npc_level')::int, 'scale', p_scale); end loop;
  return out;
end $$;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: admin_reset.sql =====
-- =====================================================================
-- 관리자: 계정 초기화 (admin_reset_account) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: admin.sql (_admin_guard · admin_log) 및 게임 테이블 SQL 들. 없는 테이블은 건너뜀
-- 동작: 대상 유저의 게임 데이터를 새 계정 상태로 되돌림. 로그인(auth.users)은 유지. 닉네임·아바타(구글 프로필 사진)는 가입 때 값(구글 이름/사진)으로 되돌림
--   소환권(story_gacha.tickets)은 유지. 일일 뽑기는 오늘 다시 가능하게 last_draw 를 어제로. 뽑기 기록(story_gacha_log)은 삭제(인재가 지워지므로 거래 가능 수 계산이 어긋나지 않게)
--   유료 재화는 기본 유지: player_wallet.gem_paid(유료 심연석) · player_items.tradable(유료 심연석으로 산 드링크)
--   거래소: 대상이 올린 열린 글은 취소(판매자·제안자 모두 원래대로 반환), 대상의 대기 제안은 환불 → 그 뒤 초기화
--   조직: 조직원이면 탈퇴 처리. 보스면 조직원이 남아 있으면 승계자(간부 우선 → 충성 순)에게 보스 이전, 혼자면 조직 해산
-- 한 트랜잭션(함수 1회 호출)으로 실행. 실패하면 전부 되돌아감. admin_log 에 기록 (meta 에 표별 삭제 수)
-- 호출: select public.admin_reset_account('<uuid>', '<닉네임 그대로>', '사유');
-- =====================================================================

alter table public.admin_log add column if not exists meta jsonb;$vr_statement$;
  execute $vr_statement$create or replace function public.admin_reset_account(p_user uuid, p_confirm text, p_reason text, p_keep_paid boolean default true)
returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare
  nick text; em text; n bigint; s jsonb := '{}'::jsonb; lid bigint; oid bigint; m guild_members; heir uuid; gp bigint := 0; dt int := 0;
  t text;
  wipe text[] := array[
    'story_progress', 'story_gacha_log', 'saves', 'matches', 'gallery',
    'player_state', 'player_gear', 'player_gear_meta', 'player_sigils', 'player_mail', 'sigil_daily', 'gear_drop_log',
    'quest_progress', 'tower_progress', 'gem_login',
    'pvp_decks', 'pvp_ratings', 'pvp_attempts', 'pvp_reward_claims', 'pvp_bonus_tries', 'pvp_tier_claims', 'pvp_titles', 'pvp_shop_log',
    'guild_requests', 'guild_cooldowns', 'guild_attendance', 'guild_claims', 'guild_daily_quests', 'guild_titles',
    'loyalty_wallet', 'loyalty_ledger', 'war_decks', 'war_signups', 'war_atk_state'];
begin
  perform public._admin_guard();
  select u.email::text, p.nickname into em, nick from auth.users u left join public.profiles p on p.id = u.id where u.id = p_user;
  if em is null then raise exception 'no such user'; end if;
  if p_user = auth.uid() then raise exception 'cannot reset self'; end if;
  if coalesce(btrim(p_confirm), '') = '' or btrim(p_confirm) <> coalesce(nick, em) then raise exception 'confirm mismatch'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  perform pg_advisory_xact_lock(hashtext('admin_reset:' || p_user));

  -- 1) 거래소 정리 (반환·환불이 먼저 일어나야 상대방 물건이 안전)
  if to_regclass('public.trade_listings') is not null then
    n := 0;
    for lid in select id from trade_listings where seller = p_user and status = 'open' order by id loop
      perform _trade_close_listing(lid, 'cancelled'); n := n + 1;
    end loop;
    s := s || jsonb_build_object('trade_listings_cancelled', n);
    n := 0;
    for oid in select id from trade_offers where offerer = p_user and status = 'pending' order by id loop
      if _trade_refund_offer(oid, 'cancelled') then n := n + 1; end if;
    end loop;
    s := s || jsonb_build_object('trade_offers_refunded', n);
  end if;

  -- 2) 조직
  if to_regclass('public.guild_members') is not null then
    select * into m from guild_members where user_id = p_user;
    if m.user_id is not null then
      perform _guild_lock(m.guild_id);
      if m.role = 'boss' then
        select user_id into heir from guild_members where guild_id = m.guild_id and user_id <> p_user
          order by (role = 'officer') desc, case when role = 'officer' then extract(epoch from joined_at) else -loyalty_total end, joined_at limit 1;
        if heir is null then
          perform _guild_log(m.guild_id, p_user, 'disband', null, jsonb_build_object('by', 'admin_reset'));
          delete from guilds where id = m.guild_id;
          s := s || jsonb_build_object('guild', 'disbanded', 'guild_id', m.guild_id);
        else
          update guild_members set role = 'boss' where user_id = heir;
          update guilds set boss = heir where id = m.guild_id;
          delete from guild_members where user_id = p_user;
          perform _guild_log(m.guild_id, p_user, 'transfer', heir, jsonb_build_object('by', 'admin_reset'));
          s := s || jsonb_build_object('guild', 'boss_transferred', 'guild_id', m.guild_id, 'heir', heir);
        end if;
      else
        delete from guild_members where user_id = p_user;
        perform _guild_log(m.guild_id, p_user, 'leave', p_user, jsonb_build_object('by', 'admin_reset'));
        s := s || jsonb_build_object('guild', 'left', 'guild_id', m.guild_id);
      end if;
    end if;
  end if;
  if to_regclass('public.war_roster') is not null then
    update war_roster set user_id = null, def_snap = null where user_id = p_user; get diagnostics n = row_count;
    s := s || jsonb_build_object('war_roster_cleared', n);
  end if;

  -- 3) 지갑: 유료 심연석만 남김
  if to_regclass('public.player_wallet') is not null then
    select coalesce(gem_paid, 0) into gp from player_wallet where user_id = p_user;
    gp := case when p_keep_paid then coalesce(gp, 0) else 0 end;
    delete from player_wallet where user_id = p_user;
    if gp > 0 then insert into player_wallet (user_id, gem_paid) values (p_user, gp); end if;
    s := s || jsonb_build_object('gem_paid_kept', gp);
  end if;
  if to_regclass('public.gem_ledger') is not null then
    -- 무료 보상 기록(ref 고유)을 지워야 챕터·로그인 보상을 다시 받을 수 있음. 결제 기록(d_paid<>0)은 유지
    delete from gem_ledger where user_id = p_user and (d_paid = 0 or not p_keep_paid); get diagnostics n = row_count;
    s := s || jsonb_build_object('gem_ledger', n);
    if gp > 0 then insert into gem_ledger (user_id, d_free, d_paid, free_after, paid_after, reason, ref, meta)
      values (p_user, 0, 0, 0, gp, 'admin_reset', 'admin_reset:' || gen_random_uuid(), jsonb_build_object('reason', p_reason)); end if;
  end if;
  -- 드링크: 유료분(tradable)만 남김 (거래 묶임 해제 — 위에서 거래는 이미 정리됨)
  if to_regclass('public.player_items') is not null then
    select coalesce(tradable, 0) into dt from player_items where user_id = p_user and item = 'drink';
    dt := case when p_keep_paid then coalesce(dt, 0) else 0 end;
    delete from player_items where user_id = p_user;
    delete from item_log where user_id = p_user and (d_tradable = 0 or not p_keep_paid);
    if dt > 0 then
      insert into player_items (user_id, item, tradable, bound, locked) values (p_user, 'drink', dt, 0, 0);
      insert into item_log (user_id, item, d_tradable, d_bound, tradable_after, bound_after, reason, meta)
        values (p_user, 'drink', 0, 0, dt, 0, 'admin_reset', jsonb_build_object('reason', p_reason));
    end if;
    s := s || jsonb_build_object('drink_paid_kept', dt);
  end if;

  -- 3.5) 소환권 유지: story_gacha 행은 남기고 일일 뽑기만 오늘 가능하게
  if to_regclass('public.story_gacha') is not null then
    update story_gacha set last_draw = (now() at time zone 'Asia/Seoul')::date - 1, updated_at = now() where user_id = p_user;
    s := s || jsonb_build_object('tickets_kept', coalesce((select (to_jsonb(g)->>'tickets')::int from story_gacha g where user_id = p_user), 0));
  end if;
  -- 3.6) 닉네임·아바타를 새 가입 때 값으로 (handle_new_user 와 같은 규칙)
  update profiles p set
    nickname = left(coalesce(u.raw_user_meta_data->>'name', u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1), '플레이어'), 20),
    avatar_url = u.raw_user_meta_data->>'avatar_url', updated_at = now()
  from auth.users u where u.id = p_user and p.id = p_user;
  s := s || jsonb_build_object('old_nickname', nick, 'profile_reset', true);

  -- 4) 나머지 게임 데이터 삭제
  foreach t in array wipe loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I where user_id = $1', t) using p_user; get diagnostics n = row_count;
      if n > 0 then s := s || jsonb_build_object(t, n); end if;
    end if;
  end loop;

  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, meta)
  values (auth.uid(), coalesce(auth.jwt()->>'email', ''), 'reset_account', p_user, null, left(p_reason, 200), s);
  return jsonb_build_object('ok', true, 'nickname', coalesce(nick, em), 'summary', s);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.admin_reset_account(uuid, text, text, boolean) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.admin_reset_account(uuid, text, text, boolean) to authenticated;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_ch8.sql =====
-- =====================================================================
-- 스토리 챕터 8 「주홍글씨」 (단일 루트: 안지윤 · 안소라 페이즈 1·2·9·11 · 페이즈 15개, 15페이즈 보스)
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전. service_role 키 필요 없음.
-- 필요 조건: story_ch7.sql 까지 적용된 상태
-- 챕터 2~7과 같은 규칙: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 소환권 +10 은 기존 _story_ticket_sync 가 챕터 전체 첫 클리어 때 지급
-- 페이즈 수는 설정 행 개수로 정해짐 (10개 제한 없음). 페이즈 열림: 챕터 7 전체 클리어 후 (story_start_phase 의 기존 조건)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (8,1,'normal',3,null,5), (8,2,'normal',3,null,5), (8,3,'normal',3,null,5), (8,4,'normal',3,null,5), (8,5,'normal',3,null,5), (8,6,'normal',3,null,5), (8,7,'normal',3,null,5), (8,8,'normal',3,null,5), (8,9,'normal',3,null,5), (8,10,'normal',3,null,5), (8,11,'normal',3,null,5), (8,12,'normal',3,null,5), (8,13,'normal',3,null,5), (8,14,'normal',3,null,5), (8,15,'boss',5,null,1)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, count(*) from public.story_phase_config group by chapter order by chapter;  → 8 | 15
-- 출전 조건(남성 출전 불가·안지윤 출전 금지·단독 출전)·게스트 레벨·적 스토리 레벨·NPC 카드는 클라이언트 데이터(js/story-data-ch8.js, data/npc_cards.csv)에만 있음


-- ===== SOURCE: story_ch9_11.sql =====
-- =====================================================================
-- 스토리 챕터 9 「기도」(18) · 10 「마지막 랠리」(18) · 11 「사라지지 않는 약속」(16) 페이즈 설정
-- 사용법: Supabase SQL Editor 에 붙여넣고 Run. 여러 번 실행해도 안전 (insert … on conflict). 삭제 없음. service_role 키 필요 없음.
-- 필요 조건: story_ch8.sql 까지 적용된 상태
-- 규칙은 챕터 2~8과 같음: 카드 보상 없이 스탯 포인트 (일반 3, 마지막 페이즈 5). 소환권 +10 은 기존 _story_ticket_sync 가 챕터 전체 첫 클리어 때 지급
-- 페이즈 열림: 앞 챕터 전체 클리어 후 (story_start_phase 의 기존 조건)
-- =====================================================================
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  (9,1,'normal',3,null,5), (9,2,'normal',3,null,5), (9,3,'normal',3,null,5), (9,4,'normal',3,null,5), (9,5,'normal',3,null,5), (9,6,'normal',3,null,5), (9,7,'normal',3,null,5), (9,8,'normal',3,null,5), (9,9,'normal',3,null,5), (9,10,'normal',3,null,5), (9,11,'normal',3,null,5), (9,12,'normal',3,null,5), (9,13,'normal',3,null,5), (9,14,'normal',3,null,5), (9,15,'normal',3,null,5), (9,16,'normal',3,null,5), (9,17,'normal',3,null,5), (9,18,'boss',5,null,5),
  (10,1,'normal',3,null,5), (10,2,'normal',3,null,5), (10,3,'normal',3,null,5), (10,4,'normal',3,null,5), (10,5,'normal',3,null,5), (10,6,'normal',3,null,5), (10,7,'normal',3,null,5), (10,8,'normal',3,null,5), (10,9,'normal',3,null,5), (10,10,'normal',3,null,5), (10,11,'normal',3,null,5), (10,12,'normal',3,null,5), (10,13,'normal',3,null,5), (10,14,'normal',3,null,5), (10,15,'normal',3,null,5), (10,16,'normal',3,null,5), (10,17,'normal',3,null,5), (10,18,'boss',5,null,5),
  (11,1,'normal',3,null,5), (11,2,'normal',3,null,5), (11,3,'normal',3,null,5), (11,4,'normal',3,null,5), (11,5,'normal',3,null,5), (11,6,'normal',3,null,5), (11,7,'normal',3,null,5), (11,8,'normal',3,null,5), (11,9,'normal',3,null,5), (11,10,'normal',3,null,5), (11,11,'normal',3,null,5), (11,12,'normal',3,null,5), (11,13,'normal',3,null,5), (11,14,'normal',3,null,5), (11,15,'normal',3,null,5), (11,16,'boss',5,null,5)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$-- 확인: select chapter, count(*) from public.story_phase_config where chapter between 9 and 11 group by chapter order by chapter;  → 9 | 18 · 10 | 18 · 11 | 16
-- 출전 조건·대여(loan)·게스트 레벨·적 스토리 레벨·패시브는 클라이언트(js/story-data-ch9~11.js, js/skills.js, data/skills.json)에만 있음


-- ===== SOURCE: story_ch0_p4.sql =====
-- 챕터 0 Phase 4 (마나 소환 전투 튜토리얼) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (추가·갱신만, 삭제 없음)
-- 적 3명 (문지예·안리·용지혜) · 첫 클리어 보상 송지은(10208)
insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values (0,4,'normal',3,null,3)
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;$vr_statement$;
  execute $vr_statement$update public.story_phase_config set reward_card = '10208' where chapter = 0 and phase = 4;$vr_statement$;
  execute $vr_statement$select chapter, phase, type, enemy_count, reward_card from public.story_phase_config where chapter = 0 order by phase;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild_lend.sql =====
-- =====================================================================
-- 조직 인재 대여 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전 (새 테이블·함수만, 기존 데이터 삭제 없음)
-- 선행: guild.sql (guild_members · _loyalty_add · _guild_day), story_server.sql (story_progress 서버 저장)
--   · 내 인재 최대 3명을 조직에 대여 등록 (내가 계속 써도 됨)
--   · 조직원은 하루(KST) 1명 대여 · 12시간 뒤 자동 반납 (expires_at 지나면 끝)
--   · 대여 인재 = 빌릴 때 원주인의 레벨·스탯 그대로(스냅샷) · 스토리·시련의 탑에서만
--   · 내 인재는 못 빌림 · 이미 같은 인재(같은 카드)를 가지고 있으면 못 빌림
--   · 빌려줄 때마다 원주인에게 충성 +20 (_lend_reward 로 조정)
-- =====================================================================
create table if not exists public.guild_lend_slots (
  user_id uuid not null references auth.users(id) on delete cascade,
  uid text not null check (char_length(uid) <= 80),
  card_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, uid));$vr_statement$;
  execute $vr_statement$create table if not exists public.guild_loans (
  id bigint generated always as identity primary key,
  borrower uuid not null references auth.users(id) on delete cascade,
  lender uuid not null references auth.users(id) on delete cascade,
  guild_id bigint not null,
  card_id text not null, src_uid text not null, snap jsonb not null,
  day date not null, borrowed_at timestamptz not null default now(), expires_at timestamptz not null,
  unique (borrower, day));$vr_statement$;
  execute $vr_statement$create index if not exists guild_loans_borrower on public.guild_loans (borrower, expires_at desc);$vr_statement$;
  execute $vr_statement$alter table public.guild_lend_slots enable row level security;$vr_statement$;
  execute $vr_statement$alter table public.guild_loans enable row level security;$vr_statement$;
  execute $vr_statement$revoke all on public.guild_lend_slots, public.guild_loans from anon, authenticated;$vr_statement$;
  execute $vr_statement$-- 읽기·쓰기 모두 아래 함수로만

create or replace function public._lend_reward() returns int language sql immutable as $$ select 20 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lend_hours() returns int language sql immutable as $$ select 12 $$;$vr_statement$;
  execute $vr_statement$create or replace function public._lend_max() returns int language sql immutable as $$ select 3 $$;$vr_statement$;
  execute $vr_statement$-- 내 보유 인재 (story_progress.data.owned) 에서 uid 로 한 장
create or replace function public._lend_owned(p_uid uuid, p_card_uid text) returns jsonb language sql stable security definer set search_path = public as $$
  select o from story_progress s, jsonb_array_elements(case when jsonb_typeof(s.data->'owned') = 'array' then s.data->'owned' else '[]'::jsonb end) o
  where s.user_id = p_uid and o->>'uid' = p_card_uid limit 1 $$;$vr_statement$;
  execute $vr_statement$-- 등록 바꾸기: p_uids = 내 인재 uid 최대 3개 (빈 배열 = 전부 해제)
create or replace function public.guild_lend_set(p_uids jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); u text; o jsonb; n int := 0;
begin
  if me is null then raise exception 'login required'; end if;
  if not exists (select 1 from guild_members where user_id = me) then raise exception 'not in guild'; end if;
  if jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) > _lend_max() then raise exception 'too many'; end if;
  delete from guild_lend_slots where user_id = me;
  for u in select distinct value from jsonb_array_elements_text(p_uids) loop
    o := _lend_owned(me, u);
    if o is null then raise exception 'not owned'; end if;
    if exists (select 1 from guild_lend_slots where user_id = me and card_id = o->>'id') then continue; end if;   -- 같은 카드 두 장 X
    insert into guild_lend_slots (user_id, uid, card_id) values (me, u, o->>'id'); n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'n', n);
end $$;$vr_statement$;
  execute $vr_statement$-- 대여 화면: 내 등록 · 조직원 등록 인재(원주인 레벨) · 내 대여 중 · 오늘 빌렸는지
create or replace function public.guild_lend_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); gid bigint; mine jsonb; others jsonb; cur jsonb; today boolean;
begin
  if me is null then raise exception 'login required'; end if;
  select guild_id into gid from guild_members where user_id = me;
  if gid is null then return jsonb_build_object('in_guild', false); end if;
  select coalesce(jsonb_agg(jsonb_build_object('uid', s.uid, 'id', s.card_id, 'level', (_lend_owned(me, s.uid)->>'level')::int) order by s.created_at), '[]'::jsonb) into mine
    from guild_lend_slots s where s.user_id = me and _lend_owned(me, s.uid) is not null;
  select coalesce(jsonb_agg(jsonb_build_object('owner', s.user_id, 'owner_name', coalesce(p.nickname, '조직원'), 'uid', s.uid, 'id', s.card_id, 'level', (o.o->>'level')::int) order by p.nickname, s.created_at), '[]'::jsonb) into others
    from guild_lend_slots s join guild_members m on m.user_id = s.user_id and m.guild_id = gid left join profiles p on p.id = s.user_id
    cross join lateral (select _lend_owned(s.user_id, s.uid) o) o
    where s.user_id <> me and o.o is not null;
  select jsonb_build_object('id', l.id, 'card_id', l.card_id, 'snap', l.snap, 'lender', l.lender, 'lender_name', coalesce(p.nickname, '조직원'), 'expires_at', l.expires_at) into cur
    from guild_loans l left join profiles p on p.id = l.lender where l.borrower = me and l.expires_at > now() order by l.expires_at desc limit 1;
  today := exists (select 1 from guild_loans where borrower = me and day = _guild_day());
  return jsonb_build_object('in_guild', true, 'max', _lend_max(), 'hours', _lend_hours(), 'reward', _lend_reward(), 'mine', mine, 'others', others, 'loan', cur, 'borrowed_today', today, 'now', now());
end $$;$vr_statement$;
  execute $vr_statement$-- 빌리기: 하루 1명 · 12시간 · 같은 조직 · 내 것 X · 같은 카드 보유 X · 원주인 레벨 스냅샷 · 원주인 충성 +보상
create or replace function public.guild_lend_borrow(p_owner uuid, p_uid text) returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); gid bigint; s guild_lend_slots; o jsonb; snap jsonb; lid bigint; ex timestamptz;
begin
  if me is null then raise exception 'login required'; end if;
  if p_owner = me then raise exception 'own card'; end if;
  select guild_id into gid from guild_members where user_id = me;
  if gid is null then raise exception 'not in guild'; end if;
  if not exists (select 1 from guild_members where user_id = p_owner and guild_id = gid) then raise exception 'not guildmate'; end if;
  perform pg_advisory_xact_lock(hashtext('guild_lend:' || me::text));
  if exists (select 1 from guild_loans where borrower = me and day = _guild_day()) then raise exception 'already borrowed today'; end if;
  select * into s from guild_lend_slots where user_id = p_owner and uid = p_uid;
  if s.user_id is null then raise exception 'not lendable'; end if;
  o := _lend_owned(p_owner, p_uid);
  if o is null then raise exception 'not lendable'; end if;
  if exists (select 1 from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) x
             where sp.user_id = me and x->>'id' = s.card_id) then raise exception 'already own card'; end if;
  snap := jsonb_strip_nulls(jsonb_build_object('id', o->'id', 'level', o->'level', 'boost', o->'boost', 'ex', o->'ex', 'exb', o->'exb', 'skillLv', o->'skillLv'));
  ex := now() + make_interval(hours => _lend_hours());
  insert into guild_loans (borrower, lender, guild_id, card_id, src_uid, snap, day, expires_at) values (me, p_owner, gid, s.card_id, p_uid, snap, _guild_day(), ex) returning id into lid;
  perform _loyalty_add(p_owner, _lend_reward(), 'lend', 'lend:' || lid, jsonb_build_object('borrower', me, 'card', s.card_id));
  perform _guild_log(gid, me, 'lend', p_owner, jsonb_build_object('card', s.card_id));
  return jsonb_build_object('ok', true, 'id', lid, 'card_id', s.card_id, 'snap', snap, 'expires_at', ex);
end $$;$vr_statement$;
  execute $vr_statement$-- 일찍 반납 (선택)
create or replace function public.guild_lend_return() returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n int;
begin
  if me is null then raise exception 'login required'; end if;
  update guild_loans set expires_at = now() where borrower = me and expires_at > now(); get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'n', n);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public._lend_owned(uuid, text), public._lend_reward(), public._lend_hours(), public._lend_max() from public, anon, authenticated;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_lend_set(jsonb), public.guild_lend_status(), public.guild_lend_borrow(uuid, text), public.guild_lend_return() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_lend_set(jsonb), public.guild_lend_status(), public.guild_lend_borrow(uuid, text), public.guild_lend_return() to authenticated;$vr_statement$;
  execute $vr_statement$select 'guild_lend ok' as result;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: story_decks10.sql =====
-- 마이 덱: 덱당 최대 5장 → 10장 (스토리 마나 전투 손패 10장). story_set_decks 만 다시 정의 · 여러 번 실행해도 안전 · 데이터 삭제 없음
-- 탑·PvP·전쟁·토벌은 클라이언트에서 앞 5장만 씀
create or replace function public.story_set_decks(p_decks jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; clean jsonb := '[]'::jsonb; x jsonb; ids jsonb; u text; nm text;
        alluids text[] := '{}'; mine text[]; i int; e jsonb;
begin
  d := _story_lock(uid);
  owned := _story_owned(d);
  if p_decks is null or jsonb_typeof(p_decks) <> 'array' then raise exception 'bad decks'; end if;
  if jsonb_array_length(p_decks) > 10 then raise exception 'too many decks'; end if;
  select coalesce(array_agg(o->>'uid'), '{}') into mine from jsonb_array_elements(owned) o where coalesce(o->>'uid', '') <> '' and o->>'uid' not like 'guest:%';
  for x in select * from jsonb_array_elements(p_decks) loop
    if jsonb_typeof(x) <> 'object' then raise exception 'bad deck'; end if;
    nm := left(btrim(coalesce(x->>'name', '')), 16);
    ids := '[]'::jsonb;
    if jsonb_typeof(x->'uids') = 'array' then
      if jsonb_array_length(x->'uids') > 10 then raise exception 'deck too large'; end if;
      for u in select jsonb_array_elements_text(x->'uids') loop
        if not (u = any(mine)) then raise exception 'card not owned'; end if;
        if not (ids @> to_jsonb(u)) then ids := ids || to_jsonb(u); alluids := alluids || u; end if;
      end loop;
    end if;
    clean := clean || jsonb_build_object('name', nm, 'uids', ids);
  end loop;
  for i in 0 .. coalesce(jsonb_array_length(owned), 0) - 1 loop
    e := owned->i;
    if (e->>'uid') = any(alluids) then
      if not coalesce((e->>'locked')::boolean, false) then e := e || jsonb_build_object('locked', true, 'dlk', true); end if;
    elsif coalesce((e->>'dlk')::boolean, false) then
      e := e - 'locked' - 'dlk';
    end if;
    owned := jsonb_set(owned, array[i::text], e);
  end loop;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{decks}', clean);
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'decks', clean);
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.story_set_decks(jsonb) from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.story_set_decks(jsonb) to authenticated;$vr_statement$;
  execute $vr_statement$select 'story_decks10 ok' as result;$vr_statement$;
  execute $vr_statement$-- ===== SOURCE: guild_lend_notice.sql =====
-- 조직 인재 대여 알림 — 선행: guild_lend.sql. 여러 번 실행해도 안전 (열 추가·함수만, 삭제 없음)
-- 내 인재를 누가 빌리면, 다음에 게임/조직 홈을 열 때 'OO님이 OO를 빌렸어요 · 충성 +20' 을 한 번 보여 주고 읽음 표시
alter table public.guild_loans add column if not exists lender_seen boolean not null default false;$vr_statement$;
  execute $vr_statement$create index if not exists guild_loans_lender_unseen on public.guild_loans (lender) where not lender_seen;$vr_statement$;
  execute $vr_statement$-- 안 본 알림 (최근 30개, 7일 안) 을 돌려주고 읽음으로 표시
create or replace function public.guild_lend_notices() returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r jsonb;
begin
  if me is null then raise exception 'login required'; end if;
  with x as (
    select l.id from guild_loans l where l.lender = me and not l.lender_seen and l.borrowed_at > now() - interval '7 days' order by l.borrowed_at desc limit 30),
  u as (update guild_loans l set lender_seen = true from x where l.id = x.id returning l.*)
  select coalesce(jsonb_agg(jsonb_build_object('borrower_name', coalesce(p.nickname, '조직원'), 'card_id', u.card_id, 'reward', _lend_reward(), 'at', u.borrowed_at) order by u.borrowed_at desc), '[]'::jsonb) into r
    from u left join profiles p on p.id = u.borrower;
  update guild_loans set lender_seen = true where lender = me and not lender_seen;   -- 7일 지난 것도 정리
  return r;
end $$;$vr_statement$;
  execute $vr_statement$revoke all on function public.guild_lend_notices() from public, anon;$vr_statement$;
  execute $vr_statement$grant execute on function public.guild_lend_notices() to authenticated;$vr_statement$;
  execute $vr_statement$select 'guild_lend_notice ok' as result;$vr_statement$;

  insert into vr_staging_install.parts(part_no, bundle_hash, part_hash, project_ref, db_id)
  values (6, '4865c74f256feb41fff1e4fb89b5acf4b05ac5c3b4ea13de07ab10a52975d4b3', '3ab57a984bef501ac1a360805d30dbd17b38cc4fae1ed81a01209fdf40f3d679', 'cuyqchmdcnsgzkwyclji', '7703759698107299042');
end $vr_install_part$;
commit;
select '06_install.sql: 완료 또는 이미 완료 (6/14)' as result;
