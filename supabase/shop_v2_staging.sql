-- STAGING ONLY · 상점 개편 (디버그 시트 68 · AG_상점구성 / 상점 구성안) — 운영 실행 금지 (운영본: shop_v2_production.sql)
-- 선행 (스테이징엔 이미 있음): mail_v2 · gem · 드링크 · special_summon_staging. UR 확정권 우편(ur_ticket_mail_staging)·상점 BM·시즌패스 SQL 은 있어도 되고 없어도 됨 (이 파일이 필요한 표·함수를 직접 만듦).
-- 이 파일 전체를 한 번에 실행. 재실행 안전(멱등). 유저 지갑·구매 기록·우편은 지우지 않음.
--
-- 바뀌는 것
--  1) 모든 상점 지급은 우편함으로만 (보관 기한 없음). 즉시 지급 = 바로 우편 1통, 기간 지급 = 날짜별 우편.
--  2) 시즌패스: 프리미엄 / 스페셜 / 럭셔리 (30일, 같은 패스는 기간 중 다시 못 삼, 서로 다른 패스는 함께 가능). 매일 보상은 시트대로(행동력 → 무료 드링크).
--  3) 심연석 패키지: 100 / 525 / 1,050 / 3,200 / 5,500 (첫 구매 2배 그대로).
--  4) 아이템 패키지: 프리미엄 소환권 10·25·45, 스페셜 소환권 10·25·45, 레벨업 패키지. 옛 스페셜 소환권 10/45/160/220 은 판매 종료(비활성).
--  5) 심연석 상점(심연석으로 구매, 무료 심연석 먼저): 프리미엄 소환권 150 · 스페셜 소환권 150 · 유료 드링크 100 (수량 선택)
--     + 장비 매일 00시(KST) 랜덤 9칸(무기·방어구·장신구 각 3칸). 칸마다 등급 HR 85% / SR 14% / UR 1%, 칸당 하루 1회.
--  6) 팝업스토어: 첫 구매 혜택 1,650원 · 스페셜 구매 혜택 16,500원 (계정당 1회, 1일차 즉시 + 2·3일차 우편).
--  7) 스킨 상점 없음.
-- 원화(KRW) 상품은 실결제(PG) 계약 전이라 이 테스트 DB 에서만 '테스트 지급'(shop_buy). 토스 테스트 결제는 상점에서 더 이상 쓰지 않음.
-- 우편 첨부 추가: gem_paid(유료 심연석) · special_tickets(스페셜 소환권) · drink(유료 드링크, 거래 가능) · drink_bound(무료 드링크, 귀속) · card(인재 1장, 귀속)
-- 주의: seasonpass_mail_staging.sql 을 나중에 다시 돌리면 이 파일도 다시 실행하세요 (우편 래퍼를 이 파일이 최신으로 교체).
begin;
do $guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: shop v2 staging only'; end if;
 if to_regclass('public.player_mail') is null or to_regclass('public.story_gacha') is null or to_regclass('public.gear_defs') is null
    or to_regclass('public.special_wallet') is null or to_regclass('public.story_card_pool') is null or to_regclass('public.player_items') is null
    or to_regprocedure('public._mail_sync(uuid)') is null or to_regprocedure('public.mail_msg_claim(bigint)') is null
    or to_regprocedure('public._mail_clean_payload(jsonb)') is null
    or to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is null or to_regprocedure('public._gem_spend(uuid,integer,text,jsonb)') is null
    or to_regprocedure('public._wallet_add(uuid,jsonb,text)') is null or to_regprocedure('public._player_stamina_add(uuid,integer)') is null
    or to_regprocedure('public._item_add(uuid,text,integer,integer,text,text,jsonb)') is null
    or to_regprocedure('public._story_lock(uuid)') is null or to_regprocedure('public._story_new_card(text)') is null
    or to_regprocedure('public._story_save(uuid,jsonb)') is null or to_regprocedure('public._story_owned(jsonb)') is null then
  raise exception 'STOP: install mail_v2 + gem/wallet/stamina/drink + special summon first';
 end if;
end $guard$;

-- ── 기본 ────────────────────────────────────────────────────────────────
create or replace function public._shop_guard() returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'shop unavailable';
 end if;
end $$;
-- 원화 상품 '테스트 지급' 허용 여부. 스테이징만 허용. (운영본은 항상 'payment not ready')
create or replace function public._shop_krw_guard() returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' /*krw*/ then
  raise exception 'payment not ready';
 end if;
end $$;
create or replace function public._shop_day() returns date language sql stable as $$
 select (now() at time zone 'Asia/Seoul')::date $$;
create or replace function public._shop_month() returns date language sql stable as $$
 select date_trunc('month', now() at time zone 'Asia/Seoul')::date $$;

create table if not exists public.shop_products (
 sku text primary key check (sku ~ '^[a-z][a-z0-9_]{0,40}$'),
 tab text not null,
 name text not null check (char_length(name) between 1 and 40),
 blurb text not null default '' check (char_length(blurb) <= 200),
 price_krw integer not null check (price_krw between 100 and 1000000),
 month_max integer check (month_max is null or (month_max between 1 and 100)),
 sort integer not null default 0,
 active boolean not null default true,
 reward jsonb not null,
 payment_sku text
);
alter table public.shop_products drop constraint if exists shop_products_tab_check;
alter table public.shop_products add constraint shop_products_tab_check check (tab in ('charge','pack','pass','popup'));
alter table public.shop_products add column if not exists acct_max integer check (acct_max is null or acct_max between 1 and 100);
create table if not exists public.shop_purchases (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 sku text not null, ym date not null,
 first_bonus boolean not null default false,
 created_at timestamptz not null default clock_timestamp()
);
create index if not exists shop_purchases_user_sku_ym on public.shop_purchases (user_id, sku, ym);
create table if not exists public.shop_passes (
 user_id uuid not null references auth.users(id) on delete cascade,
 sku text not null, seq integer not null check (seq > 0),
 starts_on date not null, ends_on date not null,
 primary key (user_id, sku, seq), check (ends_on >= starts_on)
);
alter table public.shop_passes add column if not exists revoked_on date;
create table if not exists public.shop_pass_claims (
 user_id uuid not null, sku text not null, seq integer not null, day date not null,
 primary key (user_id, sku, seq, day),
 foreign key (user_id, sku, seq) references public.shop_passes (user_id, sku, seq) on delete cascade
);
-- 기간 지급(팝업스토어 2·3일차 등): 그날(KST)이 되면 우편함을 열 때 우편으로 옮김.
create table if not exists public.shop_mail_queue (
 user_id uuid not null references auth.users(id) on delete cascade,
 mail_key text not null check (char_length(mail_key) <= 80),
 deliver_on date not null,
 title text not null, body text not null default '',
 payload jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 primary key (user_id, mail_key)
);
-- 심연석 상점 (심연석으로 구매)
create table if not exists public.shop_gem_items (
 sku text primary key check (sku ~ '^[a-z][a-z0-9_]{0,40}$'),
 name text not null, price_gem integer not null check (price_gem between 1 and 100000),
 reward jsonb not null, max_qty integer not null default 99 check (max_qty between 1 and 999),
 sort integer not null default 0, active boolean not null default true
);
create table if not exists public.shop_gem_log (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 sku text not null, qty integer not null, price integer not null,
 created_at timestamptz not null default clock_timestamp()
);
create index if not exists shop_gem_log_user on public.shop_gem_log (user_id, created_at);
-- 장비 칸: 등급 → 장비 단계(gear_defs.tier) · 가격 · 확률(가중치 합 1000 = 0.1% 단위)
create table if not exists public.shop_gear_grades (
 grade text primary key check (grade in ('HR','SR','UR')),
 tier integer not null check (tier between 1 and 7),
 price_gem integer not null check (price_gem between 1 and 100000),
 weight integer not null check (weight between 0 and 1000)
);
create table if not exists public.shop_gear_daily (
 user_id uuid not null references auth.users(id) on delete cascade,
 day date not null, slot_no integer not null check (slot_no between 1 and 9),
 slot text not null, grade text not null, def_id text not null, price integer not null,
 bought_at timestamptz,
 primary key (user_id, day, slot_no)
);
alter table public.shop_products enable row level security;
alter table public.shop_purchases enable row level security;
alter table public.shop_passes enable row level security;
alter table public.shop_pass_claims enable row level security;
alter table public.shop_mail_queue enable row level security;
alter table public.shop_gem_items enable row level security;
alter table public.shop_gem_log enable row level security;
alter table public.shop_gear_grades enable row level security;
alter table public.shop_gear_daily enable row level security;
revoke all on public.shop_products, public.shop_purchases, public.shop_passes, public.shop_pass_claims, public.shop_mail_queue,
 public.shop_gem_items, public.shop_gem_log, public.shop_gear_grades, public.shop_gear_daily from public, anon, authenticated;

alter table public.player_mail add column if not exists pass_key text;
create unique index if not exists player_mail_pass_uniq on public.player_mail (user_id, pass_key) where pass_key is not null;

-- ── 상품 (시트 그대로. 재실행하면 이 숫자로 되돌림) ───────────────────────────
-- 시즌패스 30일. payment_sku 없음 = 토스 결제 안 씀 (원화는 테스트 지급만).
insert into public.shop_products (sku,tab,name,blurb,price_krw,month_max,acct_max,sort,reward,payment_sku) values
 ('pass_1','pass','프리미엄 시즌패스','30일 매일 프리미엄 소환권 1 · 무료 드링크 1 · 골드 5,000',5500,null,null,30,
  '{"pass":true,"days":30,"first":{},"daily":{"tickets":1,"drink_bound":1,"gold":5000}}',null),
 ('pass_2','pass','스페셜 시즌패스','즉시 프리미엄 소환권 10 · 30일 매일 프리미엄 소환권 1 · 무료 드링크 2 · 골드 10,000 · 무료 심연석 50',22000,null,null,31,
  '{"pass":true,"days":30,"first":{"tickets":10},"daily":{"tickets":1,"drink_bound":2,"gold":10000,"gem_free":50}}',null),
 ('pass_3','pass','럭셔리 시즌패스','즉시 스페셜 소환권 30 · 유료 심연석 300 · 30일 매일 프리미엄 소환권 1 · 무료 드링크 2 · 골드·피·조각 10,000 · 무료 심연석 100',44000,null,null,32,
  '{"pass":true,"days":30,"first":{"special_tickets":30,"gem_paid":300},"daily":{"tickets":1,"drink_bound":2,"gold":10000,"blood":10000,"shard":10000,"gem_free":100}}',null),
 ('gem_100','charge','심연석 100','첫 구매 2배',1100,null,null,1,'{"gem_paid":100,"gem_free":0,"first_double":true}','gem_100'),
 ('gem_500','charge','심연석 525','첫 구매 2배',5500,null,null,2,'{"gem_paid":500,"gem_free":25,"first_double":true}','gem_500'),
 ('gem_1000','charge','심연석 1,050','첫 구매 2배',11000,null,null,3,'{"gem_paid":1050,"gem_free":0,"first_double":true}','gem_1000'),
 ('gem_3000','charge','심연석 3,200','첫 구매 2배',33000,null,null,4,'{"gem_paid":3200,"gem_free":0,"first_double":true}','gem_3000'),
 ('gem_55000','charge','심연석 5,500','첫 구매 2배',55000,null,null,5,'{"gem_paid":5500,"gem_free":0,"first_double":true}','gem_55000'),
 ('prem_10','pack','프리미엄 소환권 10','월 3회',11000,3,null,10,'{"tickets":10}',null),
 ('prem_25','pack','프리미엄 소환권 25','월 3회',33000,3,null,11,'{"tickets":25}',null),
 ('prem_45','pack','프리미엄 소환권 45','월 2회',66000,2,null,12,'{"tickets":45}',null),
 ('spec_10','pack','스페셜 소환권 10','월 3회',11000,3,null,13,'{"special_tickets":10}',null),
 ('spec_25','pack','스페셜 소환권 25','월 3회',33000,3,null,14,'{"special_tickets":25}',null),
 ('spec_45','pack','스페셜 소환권 45','월 2회',66000,2,null,15,'{"special_tickets":45}',null),
 ('level_1','pack','레벨업 패키지','골드 150,000 · 피 150,000 · 조각 50,000 · 월 2회',22000,2,null,20,'{"gold":150000,"blood":150000,"shard":50000}',null),
 ('popup_first','popup','첫 구매 혜택','즉시 임유리 1장 · 골드 10,000 · 피 10,000 / 2일차 프리미엄 소환권 10 / 3일차 스페셜 소환권 10',1650,null,1,40,
  '{"card":"10325","gold":10000,"blood":10000,"later":[{"day":2,"grant":{"tickets":10}},{"day":3,"grant":{"special_tickets":10}}]}',null),
 ('popup_special','popup','스페셜 구매 혜택','즉시 임유리 1장 · 골드 50,000 · 피 50,000 / 2일차 프리미엄 소환권 20 / 3일차 스페셜 소환권 20',16500,null,1,41,
  '{"card":"10325","gold":50000,"blood":50000,"later":[{"day":2,"grant":{"tickets":20}},{"day":3,"grant":{"special_tickets":20}}]}',null)
on conflict (sku) do update set tab=excluded.tab, name=excluded.name, blurb=excluded.blurb, price_krw=excluded.price_krw,
 month_max=excluded.month_max, acct_max=excluded.acct_max, sort=excluded.sort, active=true, reward=excluded.reward, payment_sku=excluded.payment_sku;
-- 옛 상품 판매 종료 (구매 기록은 그대로)
update public.shop_products set active=false where sku not in ('pass_1','pass_2','pass_3','gem_100','gem_500','gem_1000','gem_3000','gem_55000',
 'prem_10','prem_25','prem_45','spec_10','spec_25','spec_45','level_1','popup_first','popup_special');
do $pay_off$ begin
 if to_regclass('public.payment_products') is not null then
  update public.payment_products set active=false where id in ('pass_1','pass_2','pass_3');
 end if;
end $pay_off$;

insert into public.shop_gem_items (sku,name,price_gem,reward,max_qty,sort) values
 ('gem_prem_ticket','프리미엄 소환권',150,'{"tickets":1}',99,1),
 ('gem_spec_ticket','스페셜 소환권',150,'{"special_tickets":1}',99,2),
 ('gem_drink','유료 드링크',100,'{"drink":1}',99,3)
on conflict (sku) do update set name=excluded.name, price_gem=excluded.price_gem, reward=excluded.reward, max_qty=excluded.max_qty, sort=excluded.sort, active=true;
alter table public.shop_gear_grades drop constraint if exists shop_gear_grades_weight_check;
alter table public.shop_gear_grades add constraint shop_gear_grades_weight_check check (weight between 0 and 1000);
-- 확률 = 가중치/1000: 희귀 95% · 영웅 4.9% · 전설 0.1% (2026-11-17 형님 결정)
-- 장비 등급 ↔ 장비 단계: HR=희귀(4) · SR=영웅(5) · UR=전설(6). 바꾸려면 이 표만 고치면 됨.
insert into public.shop_gear_grades (grade,tier,price_gem,weight) values ('HR',4,500,950),('SR',5,1000,49),('UR',6,5000,1)
on conflict (grade) do update set tier=excluded.tier, price_gem=excluded.price_gem, weight=excluded.weight;

-- ── 지급 = 우편 ───────────────────────────────────────────────────────────
-- 상점 지급 내용 → 우편 첨부 (값 그대로). gem_free → gem(무료), gem_paid → gem_paid(유료).
create or replace function public._shop_mail_payload(d jsonb) returns jsonb language sql immutable set search_path=pg_catalog,public as $$
 select jsonb_strip_nulls(jsonb_build_object(
  'gem', nullif(coalesce((d->>'gem_free')::int,0),0),
  'gem_paid', nullif(coalesce((d->>'gem_paid')::int,0),0),
  'tickets', nullif(coalesce((d->>'tickets')::int,0),0),
  'special_tickets', nullif(coalesce((d->>'special_tickets')::int,0),0),
  'stamina', nullif(coalesce((d->>'stamina')::int,0),0),
  'drink', nullif(coalesce((d->>'drink')::int,0),0),
  'drink_bound', nullif(coalesce((d->>'drink_bound')::int,0),0),
  'card', nullif(d->>'card',''),
  'gear', nullif(d->>'gear',''),
  'cur', nullif(jsonb_strip_nulls(jsonb_build_object('gold',nullif(coalesce((d->>'gold')::int,0),0),'blood',nullif(coalesce((d->>'blood')::int,0),0),'shard',nullif(coalesce((d->>'shard')::int,0),0))),'{}'::jsonb)))
$$;
-- 시즌패스 매일 우편도 같은 변환 사용 (무료 드링크 포함)
create or replace function public._shop_pass_mail_payload(d jsonb) returns jsonb language sql immutable set search_path=pg_catalog,public as $$
 select public._shop_mail_payload(d) $$;

create or replace function public._shop_mail(p_uid uuid, p_grant jsonb, p_title text, p_body text, p_key text) returns bigint
language plpgsql security definer set search_path=pg_catalog,public as $$
declare pl jsonb := public._shop_mail_payload(coalesce(p_grant,'{}'::jsonb)); mid bigint;
begin
 if p_uid is null then raise exception 'login required'; end if;
 if pl = '{}'::jsonb then return null; end if;
 if pl ? 'card' and not exists (select 1 from story_card_pool where id = pl->>'card') then raise exception 'invalid grant'; end if;
 if pl ? 'gear' and not exists (select 1 from gear_defs where id = pl->>'gear') then raise exception 'invalid grant'; end if;
 insert into player_mail (user_id, kind, payload, reason, title, body, created_at, expires_at, pass_key)
 values (p_uid, 'msg', pl, 'shop', left(p_title, 60), left(coalesce(p_body,''), 500), now(), 'infinity', p_key)
 on conflict (user_id, pass_key) where pass_key is not null do nothing returning player_mail.id into mid;
 return mid;
end $$;

create or replace function public._shop_queue_sync(p_uid uuid) returns int language plpgsql security definer set search_path=pg_catalog,public as $$
declare n int;
begin
 if p_uid is null then return 0; end if;
 insert into player_mail (user_id, kind, payload, reason, title, body, created_at, expires_at, pass_key)
 select q.user_id, 'msg', q.payload, 'shop', q.title, q.body, now(), 'infinity', q.mail_key
 from shop_mail_queue q where q.user_id = p_uid and q.deliver_on <= public._shop_day()
 on conflict (user_id, pass_key) where pass_key is not null do nothing;
 get diagnostics n = row_count;
 return n;
end $$;

-- 결제 테이블이 있으면(스테이징) 예전 토스 결제 기록도 첫 구매·환불 판단에 씀. 없으면(운영) 상점 기록만.
do $paid_helpers$
begin
 if to_regclass('public.payment_orders') is not null then
  execute $f$create or replace function public._shop_paid_before(p_uid uuid, p_sku text) returns boolean language sql stable security definer set search_path=pg_catalog,public as $b$
   select p_sku is not null and exists (select 1 from payment_orders o where o.user_id=p_uid and o.product_id=p_sku and o.status='paid') $b$$f$;
  execute $f$create or replace function public._shop_pass_refunded(p_uid uuid, p_sku text, p_seq int) returns boolean language sql stable security definer set search_path=pg_catalog,public as $b$
   select exists (select 1 from payment_orders o where o.user_id=p_uid and o.product_id=p_sku and o.receipt->>'seq'=p_seq::text and o.cancel_status='refunded') $b$$f$;
 else
  execute $f$create or replace function public._shop_paid_before(p_uid uuid, p_sku text) returns boolean language sql stable security definer set search_path=pg_catalog,public as $b$ select false $b$$f$;
  execute $f$create or replace function public._shop_pass_refunded(p_uid uuid, p_sku text, p_seq int) returns boolean language sql stable security definer set search_path=pg_catalog,public as $b$ select false $b$$f$;
 end if;
end $paid_helpers$;

-- 시즌패스 날짜별 우편 (시작일 ~ 오늘, 직접 받은 날 · 환불 중단 이후 · 환불된 주문 제외). 고유키 pass:sku:회차:날짜.
create or replace function public._shop_pass_mail_sync(p_uid uuid) returns int language plpgsql security definer set search_path=pg_catalog,public as $$
declare today date := public._shop_day(); n int;
begin
 if p_uid is null then return 0; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||p_uid::text));
 insert into player_mail (user_id, kind, payload, reason, title, body, created_at, expires_at, pass_key)
 select sp.user_id, 'msg', public._shop_pass_mail_payload(p.reward->'daily'), 'season_pass',
        p.name||' '||(g.d-sp.starts_on+1)||'일차 보상', to_char(g.d,'YYYY-MM-DD')||' 시즌패스 매일 보상이에요. 보관 기한 없음.',
        now(), 'infinity', 'pass:'||sp.sku||':'||sp.seq||':'||g.d
 from shop_passes sp join shop_products p on p.sku=sp.sku
 cross join lateral (select x::date d from generate_series(sp.starts_on, least(sp.ends_on, today, coalesce(sp.revoked_on-1, today)), interval '1 day') x) g
 where sp.user_id=p_uid and sp.starts_on<=today
   and not exists (select 1 from shop_pass_claims c where c.user_id=sp.user_id and c.sku=sp.sku and c.seq=sp.seq and c.day=g.d)
   and not public._shop_pass_refunded(sp.user_id, sp.sku, sp.seq)
 on conflict (user_id, pass_key) where pass_key is not null do nothing;
 get diagnostics n = row_count;
 return n;
end $$;

-- ── 우편 래퍼 (seasonpass_mail 과 같은 원본 이름 사용: 원본 함수는 *_base_pass_v1 로 보존) ─────────────
do $wrap$
declare f record; cur text;
begin
 for f in select * from (values ('_mail_sync','(uuid)','_mail_sync_base_pass_v1'),('mail_msg_claim','(bigint)','_mail_msg_claim_base_pass_v1'),
                               ('_mail_clean_payload','(jsonb)','_mail_clean_payload_base_pass_v1')) v(name,args,base) loop
  select prosrc into cur from pg_proc where oid=to_regprocedure('public.'||f.name||f.args);
  if position('-- pass-mail-wrapper' in replace(cur,chr(13),''))>0 then continue; end if;
  if to_regprocedure('public.'||f.base||f.args) is not null then execute format('drop function public.%I%s',f.base,f.args); end if;
  execute format('alter function public.%I%s rename to %I',f.name,f.args,f.base);
  execute format('revoke all on function public.%I%s from public,anon,authenticated',f.base,f.args);
 end loop;
end $wrap$;

create or replace function public._mail_sync(p_uid uuid) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 -- pass-mail-wrapper · shop-v2: 전체 우편 복사(원본) + 시즌패스 날짜별 우편 + 상점 기간 지급
 perform public._mail_sync_base_pass_v1(p_uid);
 perform public._shop_pass_mail_sync(p_uid);
 perform public._shop_queue_sync(p_uid);
end $$;

create or replace function public._mail_clean_payload(p jsonb) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v int; r jsonb;
begin
 -- pass-mail-wrapper: 원본 검사 + 행동력(stamina 0..10000)
 v := coalesce((coalesce(p,'{}'::jsonb)->>'stamina')::int, 0);
 if v < 0 or v > 10000 then raise exception 'stamina must be 0..10000'; end if;
 r := public._mail_clean_payload_base_pass_v1(coalesce(p,'{}'::jsonb) - 'stamina');
 if v > 0 then r := r || jsonb_build_object('stamina', v); end if;
 return r;
end $$;

-- 받기: 원본(심연석·소환권·UR 확정권·재화·장비) + 행동력 · 유료 심연석 · 스페셜 소환권 · 드링크 · 인재. 같은 트랜잭션·같은 행 잠금 → 한 번만.
create or replace function public.mail_msg_claim(p_id bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); ml player_mail; p jsonb; r jsonb; got jsonb; st int; v int; t int; cid text; grade text; d jsonb; e jsonb;
begin
 -- pass-mail-wrapper · shop-v2
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||uid::text));
 select * into ml from player_mail where id=p_id and user_id=uid and claimed_at is null and expires_at>now() for update;
 p := coalesce(ml.payload, '{}'::jsonb);
 r := public._mail_msg_claim_base_pass_v1(p_id);
 if not coalesce((r->>'ok')::boolean,false) or ml.id is null then return r; end if;
 got := coalesce(r->'got','{}'::jsonb);
 v := coalesce((p->>'stamina')::int, 0);
 if v > 0 then st := public._player_stamina_add(uid, v); got := got || jsonb_build_object('stamina', v); r := r || jsonb_build_object('stamina', st); end if;
 v := coalesce((p->>'gem_paid')::int, 0);
 if v > 0 then
  perform public._gem_add(uid, 0, v, 'mail', 'mail-paid:'||ml.id, jsonb_build_object('mail_id', ml.id, 'reason', ml.reason));
  got := got || jsonb_build_object('gem_paid', v);
 end if;
 v := coalesce((p->>'special_tickets')::int, 0);
 if v > 0 then
  insert into special_wallet(user_id) values (uid) on conflict do nothing;
  update special_wallet set tickets = tickets + v where user_id = uid returning tickets into t;
  got := got || jsonb_build_object('special_tickets', v); r := r || jsonb_build_object('special_tickets_total', t);
 end if;
 v := coalesce((p->>'drink')::int, 0);
 if v > 0 then perform public._item_add(uid, 'drink', v, 0, 'mail', 'mail:'||ml.id, jsonb_build_object('mail_id', ml.id)); got := got || jsonb_build_object('drink', v); end if;
 v := coalesce((p->>'drink_bound')::int, 0);
 if v > 0 then perform public._item_add(uid, 'drink', 0, v, 'mail', 'mail-bound:'||ml.id, jsonb_build_object('mail_id', ml.id)); got := got || jsonb_build_object('drink_bound', v); end if;
 cid := nullif(p->>'card','');
 if cid is not null then
  select c.grade into grade from story_card_pool c where c.id = cid;
  if grade is not null then
   d := public._story_lock(uid);
   e := public._story_new_card(cid);
   d := public._story_save(uid, jsonb_set(d, '{owned}', public._story_owned(d) || jsonb_build_array(e)));
   insert into story_gacha_log (user_id, card_id, grade, kind) values (uid, cid, grade, 'shop');
   got := got || jsonb_build_object('card', cid);
  end if;
 end if;
 return r || jsonb_build_object('got', got);
end $$;

-- 우편함 '모두 받기': 첨부 있는 메시지 우편만 (장비 가방 꽉 차면 그 우편은 남김). 1회 최대 200통.
create or replace function public.mail_claim_all() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); m record; r jsonb; k text; x jsonb; tot jsonb := '{}'::jsonb; cur jsonb := '{}'::jsonb; n int := 0; skip int := 0; gear int := 0; cards int := 0; w jsonb;
begin
 -- shop-v2
 if uid is null then raise exception 'login required'; end if;
 perform public._mail_sync(uid);
 for m in select id from player_mail where user_id=uid and kind='msg' and claimed_at is null and expires_at>now() and payload<>'{}'::jsonb order by id limit 200 loop
  r := public.mail_msg_claim(m.id);
  if not coalesce((r->>'ok')::boolean,false) then skip := skip+1; continue; end if;
  n := n+1; if r ? 'wallet' and r->'wallet' <> 'null'::jsonb then w := r->'wallet'; end if;
  for k, x in select key, value from jsonb_each(coalesce(r->'got','{}'::jsonb)) loop
   if k in ('gem','gem_paid','tickets','ur_tickets','special_tickets','stamina','drink','drink_bound') then tot := tot || jsonb_build_object(k, coalesce((tot->>k)::int,0) + (x#>>'{}')::int);
   elsif k='cur' then select cur || coalesce(jsonb_object_agg(e.key, coalesce((cur->>e.key)::bigint,0) + (e.value#>>'{}')::bigint),'{}'::jsonb) into cur from jsonb_each(x) e;
   elsif k='gear_id' then gear := gear+1;
   elsif k='card' then cards := cards+1; end if;
  end loop;
 end loop;
 if cur <> '{}'::jsonb then tot := tot || jsonb_build_object('cur', cur); end if;
 if gear > 0 then tot := tot || jsonb_build_object('gear', gear); end if;
 if cards > 0 then tot := tot || jsonb_build_object('cards', cards); end if;
 return jsonb_build_object('ok', true, 'claimed', n, 'skipped', skip, 'got', tot, 'wallet', w);
end $$;

-- ── 상점 상태 ─────────────────────────────────────────────────────────────
-- 오늘(KST) 장비 9칸: 무기·방어구·장신구 각 3칸, 칸마다 등급 가중치로 뽑고 그 등급 단계의 장비 1종 무작위.
create or replace function public._shop_gear_roll(p_uid uuid) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare today date := public._shop_day(); s text; i int; k int := 0; roll numeric; acc int; gr record; pick shop_gear_grades; def text; tot int;
begin
 if exists (select 1 from shop_gear_daily where user_id=p_uid and day=today) then return; end if;
 select coalesce(sum(weight),0) into tot from shop_gear_grades;
 if tot <= 0 then return; end if;
 foreach s in array array['weapon','armor','acc'] loop
  for i in 1..3 loop
   k := k + 1; roll := random() * tot; acc := 0; pick := null;
   for gr in select * from shop_gear_grades order by weight desc, grade loop
    acc := acc + gr.weight;
    if roll < acc then select * into pick from shop_gear_grades where grade = gr.grade; exit; end if;
   end loop;
   if pick.grade is null then select * into pick from shop_gear_grades order by weight desc limit 1; end if;
   select g.id into def from gear_defs g where g.slot=s and g.tier=pick.tier and not coalesce(g.raid_only,false) order by random() limit 1;
   if def is not null then
    insert into shop_gear_daily (user_id, day, slot_no, slot, grade, def_id, price) values (p_uid, today, k, s, pick.grade, def, pick.price_gem)
    on conflict do nothing;
   end if;
  end loop;
 end loop;
end $$;

create or replace function public.shop_status() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); w player_wallet; today date := public._shop_day(); mon date := public._shop_month(); sp_t int; tk int;
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 perform public._shop_gear_roll(uid);
 select * into w from player_wallet where user_id = uid;
 select tickets into sp_t from special_wallet where user_id = uid;
 select tickets into tk from story_gacha where user_id = uid;
 return jsonb_build_object(
  'ok', true, 'v', 2,
  'gem', coalesce(w.gem_free,0)+coalesce(w.gem_paid,0), 'free', coalesce(w.gem_free,0), 'paid', coalesce(w.gem_paid,0),
  'tickets', coalesce(tk,0), 'special_tickets', coalesce(sp_t,0),
  'month', mon, 'today', today, 'krw_test', (select system_identifier::text from pg_catalog.pg_control_system()) = '7703759698107299042' /*krw*/,
  'products', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'sku', p.sku, 'tab', p.tab, 'name', p.name, 'blurb', p.blurb, 'price_krw', p.price_krw,
      'month_max', p.month_max, 'acct_max', p.acct_max,
      'month_used', (select count(*)::int from shop_purchases s where s.user_id=uid and s.sku=p.sku and s.ym=mon),
      'acct_used', (select count(*)::int from shop_purchases s where s.user_id=uid and s.sku=p.sku),
      'sort', p.sort, 'grant', p.reward,
      'pass_until', case when p.tab='pass' then (select max(x.ends_on) from shop_passes x where x.user_id=uid and x.sku=p.sku and x.ends_on>=today and x.revoked_on is null) end,
      'first_open', coalesce((p.reward->>'first_double')::boolean, false)
        and not exists (select 1 from shop_purchases s where s.user_id=uid and s.sku=p.sku and s.first_bonus)
        and not public._shop_paid_before(uid, p.payment_sku)
    ) order by p.sort), '[]'::jsonb)
    from shop_products p where p.active),
  'gem_items', (select coalesce(jsonb_agg(jsonb_build_object('sku', g.sku, 'name', g.name, 'price', g.price_gem, 'grant', g.reward, 'max_qty', g.max_qty) order by g.sort), '[]'::jsonb)
    from shop_gem_items g where g.active),
  'gear', (select coalesce(jsonb_agg(jsonb_build_object('slot_no', d.slot_no, 'slot', d.slot, 'grade', d.grade, 'def_id', d.def_id, 'tier', gd.tier, 'name', gd.name, 'icon', gd.icon,
      'price', d.price, 'bought', d.bought_at is not null) order by d.slot_no), '[]'::jsonb)
    from shop_gear_daily d join gear_defs gd on gd.id=d.def_id where d.user_id=uid and d.day=today),
  'gear_rates', (select coalesce(jsonb_object_agg(grade, jsonb_build_object('tier', tier, 'price', price_gem, 'weight', weight)), '{}'::jsonb) from shop_gear_grades),
  'passes', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'sku', sp.sku, 'seq', sp.seq, 'starts_on', sp.starts_on, 'ends_on', sp.ends_on,
      'state', case when sp.starts_on > today then 'queued' when sp.ends_on < today then 'ended' else 'active' end,
      'claimed_today', exists (select 1 from shop_pass_claims c where c.user_id=sp.user_id and c.sku=sp.sku and c.seq=sp.seq and c.day=today)
    ) order by sp.sku, sp.seq), '[]'::jsonb)
    from shop_passes sp where sp.user_id=uid));
end $$;

-- 달력: claimed = 받음, sent = 우편함에 있음, mail_pending = 안 받은 패스 우편 수 (상점 구매 우편은 제외).
create or replace function public.shop_pass_days() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid := auth.uid();
begin
 perform public._shop_guard();
 if u is null then raise exception 'login required'; end if;
 perform public._shop_pass_mail_sync(u);
 return jsonb_build_object('today', public._shop_day(), 'via', 'mail',
  'mail_pending', (select count(*) from player_mail where user_id=u and pass_key like 'pass:%' and claimed_at is null and expires_at>now()),
  'passes', coalesce((select jsonb_agg(jsonb_build_object('sku',sp.sku,'seq',sp.seq,'name',p.name,'starts_on',sp.starts_on,'ends_on',sp.ends_on,
    'days',sp.ends_on-sp.starts_on+1,'daily',p.reward->'daily','revoked_on',sp.revoked_on,
    'state',case when public._shop_day()<sp.starts_on then 'queued' when public._shop_day()>sp.ends_on then 'ended' else 'active' end,
    'claimed',coalesce((select jsonb_agg(d order by d) from (
        select c.day d from shop_pass_claims c where c.user_id=u and c.sku=sp.sku and c.seq=sp.seq
        union select split_part(ml.pass_key,':',4)::date from player_mail ml where ml.user_id=u and ml.claimed_at is not null and ml.pass_key like 'pass:'||sp.sku||':'||sp.seq||':%') z),'[]'::jsonb),
    'sent',coalesce((select jsonb_agg(split_part(ml.pass_key,':',4)::date order by ml.pass_key) from player_mail ml
        where ml.user_id=u and ml.claimed_at is null and ml.pass_key like 'pass:'||sp.sku||':'||sp.seq||':%'),'[]'::jsonb))
    order by p.sort, sp.seq) from shop_passes sp join shop_products p on p.sku=sp.sku
    where sp.user_id=u and (sp.ends_on>=public._shop_day()-31 or exists (select 1 from player_mail ml where ml.user_id=u and ml.pass_key like 'pass:'||sp.sku||':'||sp.seq||':%' and ml.claimed_at is null))), '[]'::jsonb));
end $$;

-- 예전 '오늘 받기' 화면 호환: 지급 없이 우편만 생성.
create or replace function public.shop_pass_claim() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); n int;
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 n := public._shop_pass_mail_sync(uid);
 return public.shop_status() || jsonb_build_object('claimed', '[]'::jsonb, 'mailed', n, 'via', 'mail');
end $$;

-- ── 구매 ─────────────────────────────────────────────────────────────────
-- 원화 상품: 실결제 전이라 테스트 DB 에서만 '테스트 지급'. 지급은 전부 우편.
create or replace function public.shop_buy(p_sku text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); p shop_products; mon date := public._shop_month(); today date := public._shop_day();
 pid bigint; g jsonb; doubled boolean := false; days int; s int; start_on date; it jsonb; k int;
begin
 perform public._shop_guard();
 perform public._shop_krw_guard();
 if uid is null then raise exception 'login required'; end if;
 if p_sku is null then raise exception 'invalid item'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
 perform pg_advisory_xact_lock(hashtextextended('payments:' || uid::text, 0));
 if (select count(*) from shop_purchases where user_id=uid and created_at > clock_timestamp() - interval '1 minute') >= 40
    or (select count(*) from shop_purchases where user_id=uid and created_at > clock_timestamp() - interval '1 day') >= 300 then
  raise exception 'rate limited';
 end if;
 select * into p from shop_products where sku=p_sku and active;
 if p.sku is null then raise exception 'invalid item'; end if;
 if p.month_max is not null and (select count(*) from shop_purchases x where x.user_id=uid and x.sku=p.sku and x.ym=mon) >= p.month_max then
  raise exception 'monthly limit';
 end if;
 if p.acct_max is not null and (select count(*) from shop_purchases x where x.user_id=uid and x.sku=p.sku) >= p.acct_max then
  raise exception 'account limit';
 end if;
 if coalesce((p.reward->>'pass')::boolean, false) and exists (select 1 from shop_passes x where x.user_id=uid and x.sku=p.sku and x.ends_on>=today and x.revoked_on is null) then
  raise exception 'pass active';
 end if;
 insert into shop_purchases (user_id, sku, ym) values (uid, p.sku, mon) returning id into pid;
 if coalesce((p.reward->>'pass')::boolean, false) then
  days := coalesce((p.reward->>'days')::int, 30);
  if days < 1 or days > 90 then raise exception 'invalid grant'; end if;
  select coalesce(max(x.seq),0)+1 into s from shop_passes x where x.user_id=uid and x.sku=p.sku;
  start_on := today;
  insert into shop_passes (user_id, sku, seq, starts_on, ends_on) values (uid, p.sku, s, start_on, start_on + (days - 1));
  perform public._shop_mail(uid, coalesce(p.reward->'first','{}'::jsonb), p.name||' 구매 보상', '상점에서 구매한 시즌패스 즉시 보상이에요. 매일 보상은 날짜별로 따로 와요.', 'shop:'||pid||':0');
  perform public._shop_pass_mail_sync(uid);
 else
  g := p.reward - 'first_double' - 'later' - 'pass' - 'days' - 'first' - 'daily';
  if coalesce((p.reward->>'first_double')::boolean, false)
     and not exists (select 1 from shop_purchases x where x.user_id=uid and x.sku=p.sku and x.first_bonus and x.id<>pid)
     and not public._shop_paid_before(uid, p.payment_sku) then
   doubled := true;
   g := g || jsonb_build_object('gem_paid', coalesce((g->>'gem_paid')::int,0)*2, 'gem_free', coalesce((g->>'gem_free')::int,0)*2);
   update shop_purchases set first_bonus=true where id=pid;
  end if;
  perform public._shop_mail(uid, g, p.name||case when doubled then ' (첫 구매 2배)' else '' end,
   case when p.reward ? 'later' then '상점 구매 1일차 보상이에요. 다음 보상은 날짜별로 와요.' else '상점에서 구매한 상품이에요.' end, 'shop:'||pid||':1');
  for it in select value from jsonb_array_elements(coalesce(p.reward->'later','[]'::jsonb)) loop
   k := (it->>'day')::int;
   if k is null or k < 2 or k > 31 then raise exception 'invalid grant'; end if;
   insert into shop_mail_queue (user_id, mail_key, deliver_on, title, body, payload)
   values (uid, 'shop:'||pid||':'||k, today + (k-1), p.name||' '||k||'일차 보상', '상점 구매 '||k||'일차 보상이에요.', public._shop_mail_payload(it->'grant'))
   on conflict do nothing;
  end loop;
 end if;
 return public.shop_status() || jsonb_build_object('bought', p.sku, 'mailed', true, 'first_bonus', doubled);
end $$;

-- 심연석 상점: 수량 선택(1..max_qty). 무료 심연석 먼저 차감(_gem_spend). 지급은 우편 1통.
create or replace function public.shop_gem_buy(p_sku text, p_qty int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); it shop_gem_items; q int := coalesce(p_qty, 1); g jsonb := '{}'::jsonb; k text; v jsonb; lid bigint; total int;
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
 select * into it from shop_gem_items where sku=p_sku and active;
 if it.sku is null then raise exception 'invalid item'; end if;
 if q < 1 or q > it.max_qty then raise exception 'invalid qty'; end if;
 if (select count(*) from shop_gem_log where user_id=uid and created_at > clock_timestamp() - interval '1 minute') >= 40
    or (select count(*) from shop_gem_log where user_id=uid and created_at > clock_timestamp() - interval '1 day') >= 300 then
  raise exception 'rate limited';
 end if;
 total := it.price_gem * q;
 perform public._gem_spend(uid, total, 'shop:' || it.sku, jsonb_build_object('qty', q, 'price', it.price_gem));
 insert into shop_gem_log (user_id, sku, qty, price) values (uid, it.sku, q, total) returning id into lid;
 for k, v in select key, value from jsonb_each(it.reward) loop
  if jsonb_typeof(v) = 'number' then g := g || jsonb_build_object(k, (v#>>'{}')::int * q); end if;
 end loop;
 perform public._shop_mail(uid, g, it.name||' ×'||q, '심연석 상점에서 구매한 상품이에요.', 'gemshop:'||lid);
 return public.shop_status() || jsonb_build_object('bought', it.sku, 'qty', q, 'spent', total, 'mailed', true);
end $$;

-- 장비 칸 구매: 오늘 칸, 칸당 하루 1회. 지급은 우편(가방이 꽉 차면 우편함에 남음).
create or replace function public.shop_gear_buy(p_slot int) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); today date := public._shop_day(); d shop_gear_daily; nm text;
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
 perform public._shop_gear_roll(uid);
 select * into d from shop_gear_daily where user_id=uid and day=today and slot_no=p_slot for update;
 if d.user_id is null then raise exception 'invalid item'; end if;
 if d.bought_at is not null then raise exception 'sold out'; end if;
 perform public._gem_spend(uid, d.price, 'shop:gear_' || lower(d.grade), jsonb_build_object('def', d.def_id, 'slot', d.slot_no));
 update shop_gear_daily set bought_at = clock_timestamp() where user_id=uid and day=today and slot_no=p_slot;
 select name into nm from gear_defs where id=d.def_id;
 perform public._shop_mail(uid, jsonb_build_object('gear', d.def_id), '장비 ('||d.grade||') '||coalesce(nm,''), '심연석 상점에서 구매한 장비예요.', 'gearshop:'||today||':'||p_slot);
 return public.shop_status() || jsonb_build_object('bought', d.def_id, 'slot', p_slot, 'mailed', true);
end $$;

revoke all on function public._shop_guard(), public._shop_krw_guard(), public._shop_day(), public._shop_month(), public._shop_mail_payload(jsonb), public._shop_pass_mail_payload(jsonb),
 public._shop_mail(uuid,jsonb,text,text,text), public._shop_queue_sync(uuid), public._shop_paid_before(uuid,text), public._shop_pass_refunded(uuid,text,integer),
 public._shop_pass_mail_sync(uuid), public._mail_sync(uuid), public._mail_clean_payload(jsonb), public._shop_gear_roll(uuid) from public, anon, authenticated;
revoke all on function public.mail_msg_claim(bigint), public.mail_claim_all(), public.shop_status(), public.shop_pass_days(), public.shop_pass_claim(),
 public.shop_buy(text), public.shop_gem_buy(text,integer), public.shop_gear_buy(integer) from public, anon;
grant execute on function public.mail_msg_claim(bigint), public.mail_claim_all(), public.shop_status(), public.shop_pass_days(), public.shop_pass_claim(),
 public.shop_buy(text), public.shop_gem_buy(text,integer), public.shop_gear_buy(integer) to authenticated;
notify pgrst, 'reload schema';
commit;
select 'shop v2 staging installed (sheet 68: pass 30d, packs, gem shop, gear 9 slots, popup store, all via mail)' as result;
