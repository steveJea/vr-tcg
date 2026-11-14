-- STAGING ONLY · 시즌패스 매일 보상 → 우편함 지급 (운영 실행 금지)
-- 선행: seasonpass_31_staging.sql (그리고 mail_v2 / ur_ticket_mail_staging / shop_bm_staging). 이 파일 전체를 한 번 실행. 재실행 안전.
-- 동작: 우편함 목록·안 읽음 배지를 불러올 때(_mail_sync) 지난번 이후 ~ 오늘(KST)까지 날짜마다 우편 1통 생성.
--   고유키 pass:sku:회차:날짜 (unique index) → 중복 생성 불가. 보관 기한 없음(infinity). 직접 받은 날은 우편 생성 안 함.
--   기존 직접 받기(shop_pass_claim)는 더 이상 보상을 주지 않고 우편 생성만 함 → 이중 지급 차단.
--   환불 승인(admin_shop_pass_revoke 또는 주문 cancel_status=refunded) 이후 날짜는 생성 중단, 이미 보낸 우편은 그대로.
--   우편 첨부에 행동력(stamina) 추가, 우편함 '모두 받기'(mail_claim_all). 보상량 변경 없음.
-- 기존 우편 함수는 덮어쓰지 않고 *_base_pass_v1 로 이름만 바꿔 그대로 호출 (래퍼). ur_ticket_mail_staging.sql 을 다시 돌리면 이 파일도 다시 실행.
begin;
do $guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: season pass mail staging only'; end if;
 if to_regclass('public.player_mail') is null or to_regclass('public.shop_passes') is null or to_regclass('public.payment_orders') is null
    or to_regprocedure('public.shop_pass_days()') is null or to_regprocedure('public._mail_sync(uuid)') is null
    or to_regprocedure('public.mail_msg_claim(bigint)') is null or to_regprocedure('public._mail_clean_payload(jsonb)') is null
    or to_regprocedure('public._player_stamina_add(uuid,integer)') is null then
   raise exception 'STOP: install mail_v2 + ur_ticket_mail + shop BM + seasonpass_31 first'; end if;
end $guard$;

alter table public.player_mail add column if not exists pass_key text;
create unique index if not exists player_mail_pass_uniq on public.player_mail (user_id, pass_key) where pass_key is not null;
alter table public.shop_passes add column if not exists revoked_on date;

-- 기존 함수 보존: 래퍼가 아니면 *_base_pass_v1 로 이름 변경 (이미 래핑됐으면 건너뜀, 원본이 다시 설치됐으면 새 원본으로 교체).
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

-- 패스 daily 보상 → 우편 첨부 형식 (값 그대로). gem_free → gem(무료 심연석).
create or replace function public._shop_pass_mail_payload(d jsonb) returns jsonb language sql immutable set search_path=pg_catalog,public as $$
 select jsonb_strip_nulls(jsonb_build_object(
  'tickets', nullif(coalesce((d->>'tickets')::int,0),0),
  'gem', nullif(coalesce((d->>'gem_free')::int,0),0),
  'stamina', nullif(coalesce((d->>'stamina')::int,0),0),
  'cur', nullif(jsonb_strip_nulls(jsonb_build_object('gold',nullif(coalesce((d->>'gold')::int,0),0),'blood',nullif(coalesce((d->>'blood')::int,0),0),'shard',nullif(coalesce((d->>'shard')::int,0),0))),'{}'::jsonb)))
$$;

-- 지난 날 ~ 오늘 우편 생성. 직접 받은 날 · 환불 중단일 이후 · 환불된 주문은 제외.
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
   and not exists (select 1 from payment_orders o where o.user_id=sp.user_id and o.product_id=sp.sku and o.receipt->>'seq'=sp.seq::text and o.cancel_status='refunded')
 on conflict (user_id, pass_key) where pass_key is not null do nothing;
 get diagnostics n = row_count;
 return n;
end $$;

create or replace function public._mail_sync(p_uid uuid) returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 -- pass-mail-wrapper: 전체 우편 복사(원본) + 시즌패스 날짜별 우편
 perform public._mail_sync_base_pass_v1(p_uid);
 perform public._shop_pass_mail_sync(p_uid);
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

create or replace function public.mail_msg_claim(p_id bigint) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); ml player_mail; v int; r jsonb; st int;
begin
 -- pass-mail-wrapper: 원본 받기 + 행동력. 같은 트랜잭션, 같은 행 잠금 → 한 번만.
 if uid is null then raise exception 'login required'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||uid::text));
 select * into ml from player_mail where id=p_id and user_id=uid and claimed_at is null and expires_at>now() for update;
 v := coalesce((ml.payload->>'stamina')::int, 0);
 r := public._mail_msg_claim_base_pass_v1(p_id);
 if coalesce((r->>'ok')::boolean,false) and v > 0 then
  st := public._player_stamina_add(uid, v);
  r := r || jsonb_build_object('got', coalesce(r->'got','{}'::jsonb) || jsonb_build_object('stamina', v), 'stamina', st);
 end if;
 return r;
end $$;

-- 우편함 '모두 받기': 첨부 있는 메시지 우편만 (장비 가방 꽉 차면 그 우편은 남김). 1회 최대 200통.
create or replace function public.mail_claim_all() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); m record; r jsonb; k text; x jsonb; tot jsonb := '{}'::jsonb; cur jsonb := '{}'::jsonb; n int := 0; skip int := 0; gear int := 0; w jsonb;
begin
 if uid is null then raise exception 'login required'; end if;
 perform public._mail_sync(uid);
 for m in select id from player_mail where user_id=uid and kind='msg' and claimed_at is null and expires_at>now() and payload<>'{}'::jsonb order by id limit 200 loop
  r := public.mail_msg_claim(m.id);
  if not coalesce((r->>'ok')::boolean,false) then skip := skip+1; continue; end if;
  n := n+1; if r ? 'wallet' and r->'wallet' <> 'null'::jsonb then w := r->'wallet'; end if;
  for k, x in select key, value from jsonb_each(coalesce(r->'got','{}'::jsonb)) loop
   if k in ('gem','tickets','ur_tickets','stamina') then tot := tot || jsonb_build_object(k, coalesce((tot->>k)::int,0) + (x#>>'{}')::int);
   elsif k='cur' then select cur || coalesce(jsonb_object_agg(e.key, coalesce((cur->>e.key)::bigint,0) + (e.value#>>'{}')::bigint),'{}'::jsonb) into cur from jsonb_each(x) e;
   elsif k='gear_id' then gear := gear+1; end if;
  end loop;
 end loop;
 if cur <> '{}'::jsonb then tot := tot || jsonb_build_object('cur', cur); end if;
 if gear > 0 then tot := tot || jsonb_build_object('gear', gear); end if;
 return jsonb_build_object('ok', true, 'claimed', n, 'skipped', skip, 'got', tot, 'wallet', w);
end $$;

-- 예전 '오늘 받기'는 더 이상 지급하지 않음: 우편만 생성 (구버전 화면 호환).
create or replace function public.shop_pass_claim() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare uid uuid := auth.uid(); n int;
begin
 perform public._shop_guard();
 if uid is null then raise exception 'login required'; end if;
 n := public._shop_pass_mail_sync(uid);
 return public.shop_status() || jsonb_build_object('claimed', '[]'::jsonb, 'mailed', n, 'via', 'mail');
end $$;

-- 달력: claimed = 받음(직접 받은 날 + 우편 받은 날), sent = 우편함에 있음, mail_pending = 안 받은 패스 우편 수.
create or replace function public.shop_pass_days() returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid := auth.uid();
begin
 perform public._shop_guard();
 if u is null then raise exception 'login required'; end if;
 perform public._shop_pass_mail_sync(u);
 return jsonb_build_object('today', public._shop_day(), 'via', 'mail',
  'mail_pending', (select count(*) from player_mail where user_id=u and pass_key is not null and claimed_at is null and expires_at>now()),
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

-- 환불 승인 후: 오늘부터 우편 생성 중단 (이미 보낸 우편은 그대로). 주문번호로 지정. 관리자 전용.
create or replace function public.admin_shop_pass_revoke(p_order text) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare o payment_orders; s int; d date := public._shop_day();
begin
 perform public._admin_guard();
 select * into o from payment_orders where order_id=p_order for update;
 if not found or o.product_id not in ('pass_1','pass_2','pass_3') or o.status<>'paid' then raise exception 'order not found'; end if;
 perform pg_advisory_xact_lock(hashtext('gem:'||o.user_id::text));
 s := (o.receipt->>'seq')::int;
 update shop_passes set revoked_on = least(coalesce(revoked_on, d), d) where user_id=o.user_id and sku=o.product_id and seq=s;
 if not found then raise exception 'pass not found'; end if;
 return jsonb_build_object('ok', true, 'order', o.order_id, 'sku', o.product_id, 'seq', s, 'revoked_on', d);
end $$;

revoke all on function public._shop_pass_mail_payload(jsonb), public._shop_pass_mail_sync(uuid), public._mail_sync(uuid), public._mail_clean_payload(jsonb) from public, anon, authenticated;
revoke all on function public.mail_msg_claim(bigint), public.mail_claim_all(), public.shop_pass_claim(), public.shop_pass_days(), public.admin_shop_pass_revoke(text) from public, anon;
grant execute on function public.mail_msg_claim(bigint), public.mail_claim_all(), public.shop_pass_claim(), public.shop_pass_days(), public.admin_shop_pass_revoke(text) to authenticated;

-- 이미 산 스테이징 패스: 시작일 ~ 오늘 중 직접 받지 않은 날을 지금 우편으로 생성.
do $backfill$
declare u uuid; total int := 0;
begin
 for u in select distinct user_id from public.shop_passes loop total := total + public._shop_pass_mail_sync(u); end loop;
 raise notice 'season pass mail backfill: % mails', total;
end $backfill$;
notify pgrst, 'reload schema';
commit;
select 'season pass mail installed (lazy daily mail, no expiry)' as result;
