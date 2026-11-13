-- @@ 1. UR 확정권 보유 수 (소환권과 같은 행)
alter table public.story_gacha add column if not exists ur_tickets int not null default 0 check (ur_tickets >= 0)
-- @@ 2. 전체 우편: 보낸 시각 이전 가입자만 받기
alter table public.mail_broadcast add column if not exists existing_only boolean not null default false
-- @@ 3. 첨부 검증: UR 확정권(ur_tickets 0..10) 추가
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
  v := coalesce((p->>'ur_tickets')::int, 0);
  if v < 0 or v > 10 then raise exception 'ur_tickets must be 0..10'; end if;
  if v > 0 then r := r || jsonb_build_object('ur_tickets', v); end if;
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
end $$
-- @@ 4. 전체 우편 → 내 우편함 복사: existing_only 우편은 보낸 시각 이전에 가입한 계정만
create or replace function public._mail_sync(p_uid uuid) returns void language sql security definer set search_path = public as $$
  insert into player_mail (user_id, kind, payload, reason, title, body, broadcast_id, created_at, expires_at)
  select p_uid, 'msg', b.payload, 'admin_broadcast', b.title, b.body, b.id, b.created_at, b.expires_at
    from mail_broadcast b where b.expires_at > now()
     and (not b.existing_only or exists (select 1 from auth.users u where u.id = p_uid and u.created_at <= b.created_at))
  on conflict (user_id, broadcast_id) where broadcast_id is not null do nothing $$
-- @@ 5. 메시지 우편 받기: UR 확정권 지급 추가
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
  if coalesce((p->>'tickets')::int, 0) > 0 or coalesce((p->>'ur_tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + coalesce((p->>'tickets')::int, 0), ur_tickets = ur_tickets + coalesce((p->>'ur_tickets')::int, 0), updated_at = now() where user_id = uid;
    if coalesce((p->>'tickets')::int, 0) > 0 then got := got || jsonb_build_object('tickets', (p->>'tickets')::int); end if;
    if coalesce((p->>'ur_tickets')::int, 0) > 0 then got := got || jsonb_build_object('ur_tickets', (p->>'ur_tickets')::int); end if;
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
end $$
-- @@ 6. 관리자 전체 우편: p_existing_only (기본 false = 예전과 같음)
drop function if exists public.admin_mail_broadcast(text, text, jsonb, int)
-- @@ 7
create or replace function public.admin_mail_broadcast(p_title text, p_body text, p_payload jsonb, p_days int default 7, p_existing_only boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = public, auth as $$
declare pl jsonb; bid bigint;
begin
  perform public._admin_guard();
  if coalesce(btrim(p_title), '') = '' or char_length(p_title) > 60 then raise exception 'title 1..60'; end if;
  if char_length(coalesce(p_body, '')) > 1000 then raise exception 'body too long'; end if;
  if p_days is null or p_days < 1 or p_days > 30 then raise exception 'days must be 1..30'; end if;
  pl := public._mail_clean_payload(p_payload);
  insert into public.mail_broadcast (title, body, payload, created_by, expires_at, existing_only)
    values (btrim(p_title), nullif(btrim(coalesce(p_body, '')), ''), pl, auth.jwt()->>'email', now() + make_interval(days => p_days), coalesce(p_existing_only, false)) returning id into bid;
  insert into public.admin_log (admin_id, admin_email, action, amount, reason, meta)
    values (auth.uid(), auth.jwt()->>'email', 'mail_broadcast', p_days, left(btrim(p_title), 200), pl || jsonb_build_object('broadcast_id', bid, 'existing_only', coalesce(p_existing_only, false)));
  return jsonb_build_object('ok', true, 'broadcast_id', bid, 'existing_only', coalesce(p_existing_only, false));
end $$
-- @@ 8. 보낸 전체 우편 목록에 existing_only
create or replace function public.admin_mail_broadcasts(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'payload', b.payload, 'created_at', b.created_at, 'expires_at', b.expires_at, 'existing_only', b.existing_only,
      'claimed', (select count(*) from player_mail m where m.broadcast_id = b.id and m.claimed_at is not null)) order by b.id desc)
    from (select * from mail_broadcast order by id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) b), '[]'::jsonb);
end $$
-- @@ 9. UR 확정권 보유 수
create or replace function public.story_ur_tickets() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ur_tickets', coalesce((select ur_tickets from story_gacha where user_id = uid), 0));
end $$
-- @@ 10. UR 확정권 사용: 고급 소환 UR 목록(story_premium_ur, 11명) 중 1명 무작위. 중복 허용. 뽑기 기록 → 갤러리·획득 기록은 기존 트리거
create or replace function public.story_ur_ticket_draw() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; t int; cid text; d jsonb; e jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  insert into story_gacha (user_id, last_draw) values (uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  select ur_tickets, tickets into n, t from story_gacha where user_id = uid for update;
  if coalesce(n, 0) < 1 then return jsonb_build_object('ok', false, 'reason', 'ur_tickets', 'ur_tickets', coalesce(n, 0)); end if;
  select p.id into cid from story_card_pool p join story_premium_ur w on w.id = p.id where p.grade = 'ULTRA RARE' order by random() limit 1;
  if cid is null then raise exception 'empty UR pool'; end if;
  d := _story_lock(uid);
  e := _story_new_card(cid);
  d := _story_save(uid, jsonb_set(d, '{owned}', _story_owned(d) || jsonb_build_array(e)));
  insert into story_gacha_log (user_id, card_id, grade, kind) values (uid, cid, 'ULTRA RARE', 'ur_ticket');
  update story_gacha set ur_tickets = ur_tickets - 1, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'cards', jsonb_build_array(jsonb_build_object('card_id', cid, 'uid', e->>'uid', 'grade', 'ULTRA RARE')), 'ur_tickets', n - 1, 'tickets', t);
end $$
-- @@ 11. 권한
revoke all on function public._mail_clean_payload(jsonb), public._mail_sync(uuid) from public, anon, authenticated
-- @@ 12
revoke all on function public.admin_mail_broadcast(text, text, jsonb, int, boolean), public.admin_mail_broadcasts(int), public.mail_msg_claim(bigint), public.story_ur_tickets(), public.story_ur_ticket_draw() from public, anon
-- @@ 13
grant execute on function public.admin_mail_broadcast(text, text, jsonb, int, boolean), public.admin_mail_broadcasts(int), public.mail_msg_claim(bigint), public.story_ur_tickets(), public.story_ur_ticket_draw() to authenticated
