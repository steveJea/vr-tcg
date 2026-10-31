-- =====================================================================
-- 우편 v2: 관리자 선물·메시지 우편 (개인 / 전체)  — SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: admin.sql, gem.sql, phaseE_1.sql, gear_v1.sql, gear_drops.sql
-- 기존 player_mail(장비·상자·증표 조각) 데이터는 건드리지 않음 (컬럼 추가 + kind 'msg' 허용만)
--
-- 구조
--  * 개인 우편: player_mail 에 kind='msg' 한 줄
--  * 전체 우편: mail_broadcast 에 한 줄만 저장. 유저가 우편함/뱃지를 열 때 _mail_sync 가
--    자기 몫을 player_mail 로 복사 (unique(user_id, broadcast_id) → 중복 지급 불가)
--    → 유저 수만큼 insert 하지 않음. 보낸 뒤 가입한 유저도 만료 전이면 받음
--  * 첨부(payload): { gem, tickets, cur:{gold,blood,shard,soul}, gear:"def_id" }
--  * 받기: 행 잠금(for update) + claimed_at 한 번만 → 원자적·중복 불가
-- =====================================================================

alter table public.admin_log add column if not exists meta jsonb;
alter table public.player_mail add column if not exists title text;
alter table public.player_mail add column if not exists body text;
alter table public.player_mail add column if not exists broadcast_id bigint;
alter table public.player_mail add column if not exists read_at timestamptz;
alter table public.player_mail drop constraint if exists player_mail_kind_check;
alter table public.player_mail add constraint player_mail_kind_check check (kind in ('gear', 'box', 'sigil_frag', 'gold', 'gem', 'msg'));
create unique index if not exists player_mail_bc_uniq on public.player_mail (user_id, broadcast_id) where broadcast_id is not null;

create table if not exists public.mail_broadcast (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 60),
  body text check (char_length(body) <= 1000),
  payload jsonb not null default '{}'::jsonb,
  created_by text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
alter table public.mail_broadcast enable row level security;
revoke all on public.mail_broadcast from public, anon, authenticated;

-- 첨부 검증 (내부)
create or replace function public._mail_clean_payload(p jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb := '{}'::jsonb; c jsonb := '{}'::jsonb; k text; v int; g text;
begin
  p := coalesce(p, '{}'::jsonb);
  v := coalesce((p->>'gem')::int, 0);
  if v < 0 or v > 1000000 then raise exception 'gem must be 0..1000000'; end if;
  if v > 0 then r := r || jsonb_build_object('gem', v); end if;
  v := coalesce((p->>'tickets')::int, 0);
  if v < 0 or v > 1000 then raise exception 'tickets must be 0..1000'; end if;
  if v > 0 then r := r || jsonb_build_object('tickets', v); end if;
  for k in select jsonb_object_keys(coalesce(p->'cur', '{}'::jsonb)) loop
    if k not in ('gold', 'blood', 'shard', 'soul') then raise exception 'invalid currency: %', k; end if;
    v := coalesce((p->'cur'->>k)::int, 0);
    if v < 0 or v > 1000000 then raise exception 'currency must be 0..1000000'; end if;
    if v > 0 then c := c || jsonb_build_object(k, v); end if;
  end loop;
  if c <> '{}'::jsonb then r := r || jsonb_build_object('cur', c); end if;
  g := nullif(btrim(coalesce(p->>'gear', '')), '');
  if g is not null then
    if not exists (select 1 from gear_defs where id = g and tier <= 5 and not coalesce(event_only, false)) then raise exception 'invalid gear (영웅 이하·일반 장비만)'; end if;
    r := r || jsonb_build_object('gear', g);
  end if;
  return r;
end $$;
revoke all on function public._mail_clean_payload(jsonb) from public, anon, authenticated;

-- 전체 우편 → 내 우편함으로 복사 (내부)
create or replace function public._mail_sync(p_uid uuid) returns void language sql security definer set search_path = public as $$
  insert into player_mail (user_id, kind, payload, reason, title, body, broadcast_id, created_at, expires_at)
  select p_uid, 'msg', b.payload, 'admin_broadcast', b.title, b.body, b.id, b.created_at, b.expires_at
    from mail_broadcast b where b.expires_at > now()
  on conflict (user_id, broadcast_id) where broadcast_id is not null do nothing $$;
revoke all on function public._mail_sync(uuid) from public, anon, authenticated;

-- 관리자: 한 명에게
create or replace function public.admin_mail_send(p_user uuid, p_title text, p_body text, p_payload jsonb, p_days int default 7) returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare pl jsonb; mid bigint;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_title), '') = '' or char_length(p_title) > 60 then raise exception 'title 1..60'; end if;
  if char_length(coalesce(p_body, '')) > 1000 then raise exception 'body too long'; end if;
  if p_days is null or p_days < 1 or p_days > 30 then raise exception 'days must be 1..30'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  pl := public._mail_clean_payload(p_payload);
  insert into public.player_mail (user_id, kind, payload, reason, title, body, expires_at)
    values (p_user, 'msg', pl, 'admin', btrim(p_title), nullif(btrim(coalesce(p_body, '')), ''), now() + make_interval(days => p_days)) returning id into mid;
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, meta)
    values (auth.uid(), auth.jwt()->>'email', 'mail_send', p_user, p_days, left(btrim(p_title), 200), pl || jsonb_build_object('mail_id', mid));
  return jsonb_build_object('ok', true, 'mail_id', mid);
end $$;

-- 관리자: 전체
create or replace function public.admin_mail_broadcast(p_title text, p_body text, p_payload jsonb, p_days int default 7) returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare pl jsonb; bid bigint;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_title), '') = '' or char_length(p_title) > 60 then raise exception 'title 1..60'; end if;
  if char_length(coalesce(p_body, '')) > 1000 then raise exception 'body too long'; end if;
  if p_days is null or p_days < 1 or p_days > 30 then raise exception 'days must be 1..30'; end if;
  pl := public._mail_clean_payload(p_payload);
  insert into public.mail_broadcast (title, body, payload, created_by, expires_at)
    values (btrim(p_title), nullif(btrim(coalesce(p_body, '')), ''), pl, auth.jwt()->>'email', now() + make_interval(days => p_days)) returning id into bid;
  insert into public.admin_log (admin_id, admin_email, action, amount, reason, meta)
    values (auth.uid(), auth.jwt()->>'email', 'mail_broadcast', p_days, left(btrim(p_title), 200), pl || jsonb_build_object('broadcast_id', bid));
  return jsonb_build_object('ok', true, 'broadcast_id', bid);
end $$;

-- 관리자: 보낸 전체 우편 목록 (+받은 수)
create or replace function public.admin_mail_broadcasts(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'payload', b.payload, 'created_at', b.created_at, 'expires_at', b.expires_at,
      'claimed', (select count(*) from player_mail m where m.broadcast_id = b.id and m.claimed_at is not null)) order by b.id desc)
    from (select * from mail_broadcast order by id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) b), '[]'::jsonb);
end $$;

-- 우편 목록 (기존 mail_list 대체: 전체 우편 동기화 + 제목/본문/읽음 포함, 기존 필드 유지)
create or replace function public.mail_list() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform _mail_sync(uid);
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'payload', payload, 'reason', reason, 'expires_at', expires_at,
      'title', title, 'body', body, 'read', read_at is not null, 'created_at', created_at) order by (kind = 'msg') desc, id desc)
    from player_mail where user_id = uid and claimed_at is null and expires_at > now()), '[]'::jsonb);
end $$;

-- 뱃지용: 안 받은 우편 수 (메시지는 안 읽은 것만 = 읽었어도 첨부 남았으면 셈)
create or replace function public.mail_unread() returns int
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return 0; end if;
  perform _mail_sync(uid);
  return (select count(*) from player_mail where user_id = uid and claimed_at is null and expires_at > now()
    and (kind <> 'msg' or read_at is null or payload <> '{}'::jsonb))::int;
end $$;

-- 메시지 우편 받기/확인: 첨부 전부 한 번에 (원자적). 첨부 없으면 확인 = 삭제
create or replace function public.mail_msg_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; p jsonb; k text; gid bigint; d gear_defs; w jsonb; got jsonb := '{}'::jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found or ml.kind <> 'msg' then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  p := coalesce(ml.payload, '{}'::jsonb);
  if p ? 'gear' and _gear_bag_full(uid) then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  if coalesce((p->>'gem')::int, 0) > 0 then
    perform _gem_add(uid, (p->>'gem')::int, 0, 'mail', 'mail:' || ml.id, jsonb_build_object('mail_id', ml.id, 'broadcast_id', ml.broadcast_id));
    got := got || jsonb_build_object('gem', (p->>'gem')::int);
  end if;
  if coalesce((p->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p->>'tickets')::int, updated_at = now() where user_id = uid;
    got := got || jsonb_build_object('tickets', (p->>'tickets')::int);
  end if;
  if p ? 'cur' and p->'cur' <> '{}'::jsonb then
    w := _wallet_add(uid, p->'cur', 'mail');
    got := got || jsonb_build_object('cur', p->'cur');
  end if;
  if p ? 'gear' then
    select * into d from gear_defs where id = p->>'gear';
    if found then
      insert into player_gear (user_id, def_id, opts, source, locked) values (uid, d.id, _gear_roll_opts(d.id), 'mail:admin', false) returning id into gid;
      got := got || jsonb_build_object('gear_id', gid, 'def_id', d.id);
    end if;
  end if;
  update player_mail set claimed_at = now(), read_at = coalesce(read_at, now()) where id = ml.id;
  return jsonb_build_object('ok', true, 'got', got, 'wallet', w);
end $$;

-- 읽음 표시 (열어봤을 때)
create or replace function public.mail_read(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  update player_mail set read_at = now() where id = p_id and user_id = auth.uid() and kind = 'msg' and read_at is null;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.admin_mail_send(uuid, text, text, jsonb, int), public.admin_mail_broadcast(text, text, jsonb, int), public.admin_mail_broadcasts(int),
  public.mail_list(), public.mail_unread(), public.mail_msg_claim(bigint), public.mail_read(bigint) from public, anon;
grant execute on function public.admin_mail_send(uuid, text, text, jsonb, int), public.admin_mail_broadcast(text, text, jsonb, int), public.admin_mail_broadcasts(int),
  public.mail_list(), public.mail_unread(), public.mail_msg_claim(bigint), public.mail_read(bigint) to authenticated;

-- 확인: select public.mail_unread();  /  select id, title, expires_at from public.mail_broadcast order by id desc;
