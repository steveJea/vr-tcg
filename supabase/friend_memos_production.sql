-- =====================================================================
-- 2026-11-20 친구 1:1 쪽지 (1단계). 우편(player_mail)과 분리된 memos 표.
-- 차단(player_blocks) · 신고(chat_reports) · 뮤트/정지(chat_mutes).
-- 기능 플래그 friend_memos 는 기본 OFF. 꺼져 있어도 관리자(stevejean77@gmail.com)는 테스트 가능.
-- 아직 실행하지 마세요. 오늘(2026-11-20) 실섭 업데이트(PR #676 / release/2026-11-20)에 넣지 않습니다.
-- PRODUCTION ONLY (htarwisgkkphutxxnuak). system_identifier 7692130048193495360.
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7692130048193495360' then
    raise exception 'STOP: friend_memos is production htarwisgkkphutxxnuak only; staging forbidden';
  end if;
end $guard$;

-- 1) 표
create table if not exists public.feature_flags (
  key        text primary key check (char_length(key) between 1 and 40),
  enabled    boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by text
);
insert into public.feature_flags (key, enabled) values ('friend_memos', false)
  on conflict (key) do nothing;

create table if not exists public.player_blocks (
  blocker    uuid not null references auth.users(id) on delete cascade,
  blocked    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
create index if not exists player_blocks_blocked_idx on public.player_blocks (blocked);

create table if not exists public.memos (
  id         bigint generated always as identity primary key,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 200),
  created_at timestamptz not null default now(),
  read_at    timestamptz,
  hidden_at  timestamptz,
  deleted_at timestamptz,
  check (from_user <> to_user)
);
create index if not exists memos_inbox_idx on public.memos (to_user, created_at desc)
  where hidden_at is null and deleted_at is null;
create index if not exists memos_sent_idx on public.memos (from_user, created_at desc)
  where hidden_at is null and deleted_at is null;
create index if not exists memos_created_idx on public.memos (created_at);
create index if not exists memos_unread_idx on public.memos (to_user)
  where read_at is null and hidden_at is null and deleted_at is null;

create table if not exists public.chat_reports (
  id         bigint generated always as identity primary key,
  memo_id    bigint not null references public.memos(id) on delete cascade,
  reporter   uuid not null references auth.users(id) on delete cascade,
  reason     text not null check (char_length(reason) between 1 and 200),
  status     text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid,
  note       text,
  unique (memo_id, reporter)
);
create index if not exists chat_reports_status_idx on public.chat_reports (status, created_at desc);
create index if not exists chat_reports_memo_idx on public.chat_reports (memo_id);

create table if not exists public.chat_mutes (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('mute', 'suspend')),
  until      timestamptz,
  reason     text not null check (char_length(reason) between 1 and 200),
  created_at timestamptz not null default now(),
  created_by uuid,
  lifted_at  timestamptz,
  lifted_by  uuid
);
create index if not exists chat_mutes_active_idx on public.chat_mutes (user_id)
  where lifted_at is null;

alter table public.feature_flags enable row level security;
alter table public.player_blocks enable row level security;
alter table public.memos enable row level security;
alter table public.chat_reports enable row level security;
alter table public.chat_mutes enable row level security;
revoke all on public.feature_flags, public.player_blocks, public.memos, public.chat_reports, public.chat_mutes
  from public, anon, authenticated;

-- 2) 내부 도우미
create or replace function public._memo_day() returns date language sql stable as $$
  select (timezone('Asia/Seoul', now()))::date
$$;

create or replace function public._memo_norm(p text) returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(p, '')), '[\s_.\-0-9]', '', 'g')
$$;

create or replace function public._memo_flag_on() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select enabled from feature_flags where key = 'friend_memos'), false)
$$;

create or replace function public._memo_admin() returns boolean language sql stable security definer set search_path = public, auth as $$
  select public._is_admin()
$$;

-- 일반 유저: 플래그 ON 일 때만. 관리자는 플래그가 꺼져 있어도 테스트 가능.
create or replace function public._memo_available() returns boolean language sql stable security definer set search_path = public, auth as $$
  select auth.uid() is not null and (public._memo_admin() or public._memo_flag_on())
$$;

create or replace function public._memo_blocked(p1 uuid, p2 uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from player_blocks
    where (blocker = p1 and blocked = p2) or (blocker = p2 and blocked = p1)
  )
$$;

create or replace function public._memo_sanction(p_uid uuid) returns text language sql stable security definer set search_path = public as $$
  select kind from chat_mutes
   where user_id = p_uid and lifted_at is null and (until is null or until > now())
   order by case kind when 'suspend' then 0 else 1 end, created_at desc
   limit 1
$$;

create or replace function public._memo_text_ok(p_text text) returns text language plpgsql stable security definer set search_path = public as $$
declare t text := btrim(coalesce(p_text, ''));
begin
  if char_length(t) < 1 then raise exception 'empty body'; end if;
  if char_length(t) > 200 then raise exception 'body too long'; end if;
  if exists (
    select 1 from nick_banned b
    where char_length(b.word) > 0 and position(b.word in public._memo_norm(t)) > 0
  ) then raise exception 'bad word'; end if;
  return t;
end $$;

create or replace function public._memo_card(p uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select public._friend_card(p)
$$;

revoke all on function public._memo_day(), public._memo_norm(text), public._memo_flag_on(), public._memo_admin(),
  public._memo_available(), public._memo_blocked(uuid, uuid), public._memo_sanction(uuid),
  public._memo_text_ok(text), public._memo_card(uuid) from public, anon, authenticated;

-- 3) 플레이어 RPC
create or replace function public.memo_status() returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); av boolean; un int := 0; san text;
begin
  if uid is null then raise exception 'login required'; end if;
  av := public._memo_available();
  san := public._memo_sanction(uid);
  if av then
    select count(*)::int into un from memos
     where to_user = uid and read_at is null and hidden_at is null and deleted_at is null;
  end if;
  return jsonb_build_object(
    'ok', true,
    'enabled', av,
    'flag', public._memo_flag_on(),
    'admin', public._memo_admin(),
    'unread', un,
    'sanction', san
  );
end $$;

create or replace function public.memo_unread() returns int language plpgsql stable security definer set search_path = public, auth as $$
begin
  return coalesce((public.memo_status()->>'unread')::int, 0);
end $$;

create or replace function public.memo_list(p_box text, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); lim int := least(greatest(coalesce(p_limit, 50), 1), 100); box text := lower(btrim(coalesce(p_box, 'inbox')));
begin
  if uid is null then raise exception 'login required'; end if;
  if not public._memo_available() then raise exception 'feature off'; end if;
  if box not in ('inbox', 'sent') then raise exception 'bad box'; end if;
  return jsonb_build_object('ok', true, 'box', box, 'items', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', m.id,
      'from', public._memo_card(m.from_user),
      'to', public._memo_card(m.to_user),
      'body', m.body,
      'created_at', m.created_at,
      'read', m.read_at is not null,
      'mine', m.from_user = uid
    ) order by m.id desc)
    from (
      select * from memos
       where hidden_at is null and deleted_at is null
         and ((box = 'inbox' and to_user = uid) or (box = 'sent' and from_user = uid))
       order by id desc
       limit lim
    ) m
  ), '[]'::jsonb));
end $$;

create or replace function public.memo_send(p_user uuid, p_body text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); t text; san text; mid bigint; day0 timestamptz;
begin
  if uid is null then raise exception 'login required'; end if;
  if not public._memo_available() then raise exception 'feature off'; end if;
  if p_user is null or p_user = uid then raise exception 'invalid user'; end if;
  if not exists (select 1 from profiles where id = p_user) then raise exception 'invalid user'; end if;
  if not public._is_friend(uid, p_user) then raise exception 'not friends'; end if;
  if public._memo_blocked(uid, p_user) then raise exception 'blocked'; end if;
  san := public._memo_sanction(uid);
  if san = 'suspend' then raise exception 'suspended'; end if;
  if san = 'mute' then raise exception 'muted'; end if;
  t := public._memo_text_ok(p_body);
  perform pg_advisory_xact_lock(hashtext('memo-send:' || uid::text));
  if exists (select 1 from memos where from_user = uid and created_at > now() - interval '1 second') then
    raise exception 'rate second';
  end if;
  if (select count(*) from memos where from_user = uid and created_at > now() - interval '1 minute') >= 10 then
    raise exception 'rate minute';
  end if;
  day0 := (public._memo_day())::timestamp at time zone 'Asia/Seoul';
  if (select count(*) from memos where from_user = uid and to_user = p_user and created_at >= day0) >= 20 then
    raise exception 'rate daily';
  end if;
  insert into memos (from_user, to_user, body) values (uid, p_user, t) returning id into mid;
  return jsonb_build_object('ok', true, 'id', mid);
end $$;

create or replace function public.memo_read(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  if not public._memo_available() then raise exception 'feature off'; end if;
  update memos set read_at = now()
   where id = p_id and to_user = uid and read_at is null and hidden_at is null and deleted_at is null;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.player_block(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  if not public._memo_available() then raise exception 'feature off'; end if;
  if p_user is null or p_user = uid then raise exception 'invalid user'; end if;
  if not exists (select 1 from profiles where id = p_user) then raise exception 'invalid user'; end if;
  insert into player_blocks (blocker, blocked) values (uid, p_user) on conflict do nothing;
  return jsonb_build_object('ok', true, 'state', 'blocked');
end $$;

create or replace function public.player_unblock(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  if not public._memo_available() then raise exception 'feature off'; end if;
  delete from player_blocks where blocker = uid and blocked = p_user;
  if not found then raise exception 'not blocked'; end if;
  return jsonb_build_object('ok', true, 'state', 'none');
end $$;

create or replace function public.player_blocks() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  if not public._memo_available() then raise exception 'feature off'; end if;
  return jsonb_build_object('ok', true, 'items', coalesce((
    select jsonb_agg(public._memo_card(b.blocked) || jsonb_build_object('at', b.created_at) order by b.created_at desc)
    from player_blocks b where b.blocker = uid
  ), '[]'::jsonb));
end $$;

create or replace function public.chat_report(p_memo_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := auth.uid(); m memos; rsn text;
begin
  if uid is null then raise exception 'login required'; end if;
  if not public._memo_available() then raise exception 'feature off'; end if;
  rsn := btrim(coalesce(p_reason, ''));
  if char_length(rsn) < 1 or char_length(rsn) > 200 then raise exception 'bad reason'; end if;
  select * into m from memos where id = p_memo_id and (from_user = uid or to_user = uid);
  if m.id is null then raise exception 'memo not found'; end if;
  if m.from_user = uid then raise exception 'own memo'; end if;
  insert into chat_reports (memo_id, reporter, reason) values (m.id, uid, rsn)
    on conflict (memo_id, reporter) do nothing;
  if not found then raise exception 'already reported'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- 4) 관리자 RPC
create or replace function public.admin_feature_flag_get() returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return jsonb_build_object('ok', true, 'flags', coalesce((
    select jsonb_agg(jsonb_build_object('key', key, 'enabled', enabled, 'updated_at', updated_at, 'updated_by', updated_by) order by key)
    from feature_flags
  ), '[]'::jsonb));
end $$;

create or replace function public.admin_feature_flag_set(p_key text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare k text := btrim(coalesce(p_key, '')); was boolean;
begin
  perform public._admin_guard();
  if k <> 'friend_memos' then raise exception 'unknown flag'; end if;
  select enabled into was from feature_flags where key = k;
  insert into feature_flags (key, enabled, updated_at, updated_by)
    values (k, coalesce(p_enabled, false), now(), auth.jwt()->>'email')
    on conflict (key) do update set enabled = excluded.enabled, updated_at = now(), updated_by = excluded.updated_by;
  insert into admin_log (admin_id, admin_email, action, amount, reason, before_val, after_val)
    values (auth.uid(), auth.jwt()->>'email', 'flag_set', case when p_enabled then 1 else 0 end, k,
            case when was then 1 else 0 end, case when p_enabled then 1 else 0 end);
  return jsonb_build_object('ok', true, 'key', k, 'enabled', coalesce(p_enabled, false));
end $$;

create or replace function public.admin_chat_reports(p_status text default 'open', p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
declare st text := lower(btrim(coalesce(p_status, 'open'))); lim int := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  perform public._admin_guard();
  if st not in ('open', 'reviewed', 'dismissed', 'all') then raise exception 'bad status'; end if;
  return jsonb_build_object('ok', true, 'items', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'memo_id', r.memo_id, 'reason', r.reason, 'status', r.status, 'created_at', r.created_at,
      'reporter', public._memo_card(r.reporter),
      'from', public._memo_card(m.from_user),
      'to', public._memo_card(m.to_user),
      'body', m.body, 'hidden', m.hidden_at is not null, 'deleted', m.deleted_at is not null,
      'memo_at', m.created_at, 'note', r.note
    ) order by r.id desc)
    from (select * from chat_reports where (st = 'all' or status = st) order by id desc limit lim) r
    join memos m on m.id = r.memo_id
  ), '[]'::jsonb));
end $$;

create or replace function public.admin_chat_report_review(p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare st text := lower(btrim(coalesce(p_status, '')));
begin
  perform public._admin_guard();
  if st not in ('reviewed', 'dismissed') then raise exception 'bad status'; end if;
  update chat_reports set status = st, reviewed_at = now(), reviewed_by = auth.uid(), note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id;
  if not found then raise exception 'report not found'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_memo_hide(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare rsn text := btrim(coalesce(p_reason, '')); m memos;
begin
  perform public._admin_guard();
  if char_length(rsn) < 1 then raise exception 'bad reason'; end if;
  select * into m from memos where id = p_id;
  if m.id is null then raise exception 'memo not found'; end if;
  update memos set hidden_at = coalesce(hidden_at, now()) where id = p_id;
  insert into admin_log (admin_id, admin_email, action, target_user, reason)
    values (auth.uid(), auth.jwt()->>'email', 'memo_hide', m.from_user, left(rsn, 200));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_memo_delete(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare rsn text := btrim(coalesce(p_reason, '')); m memos;
begin
  perform public._admin_guard();
  if char_length(rsn) < 1 then raise exception 'bad reason'; end if;
  select * into m from memos where id = p_id;
  if m.id is null then raise exception 'memo not found'; end if;
  update memos set deleted_at = coalesce(deleted_at, now()), hidden_at = coalesce(hidden_at, now()) where id = p_id;
  insert into admin_log (admin_id, admin_email, action, target_user, reason)
    values (auth.uid(), auth.jwt()->>'email', 'memo_delete', m.from_user, left(rsn, 200));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_chat_mute(p_user uuid, p_kind text, p_hours int, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare k text := lower(btrim(coalesce(p_kind, 'mute'))); rsn text := btrim(coalesce(p_reason, '')); until_at timestamptz;
begin
  perform public._admin_guard();
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then raise exception 'invalid user'; end if;
  if k not in ('mute', 'suspend') then raise exception 'bad kind'; end if;
  if char_length(rsn) < 1 then raise exception 'bad reason'; end if;
  if p_hours is not null and (p_hours < 1 or p_hours > 8760) then raise exception 'bad hours'; end if;
  until_at := case when p_hours is null then null else now() + make_interval(hours => p_hours) end;
  update chat_mutes set lifted_at = now(), lifted_by = auth.uid()
   where user_id = p_user and lifted_at is null;
  insert into chat_mutes (user_id, kind, until, reason, created_by)
    values (p_user, k, until_at, left(rsn, 200), auth.uid());
  insert into admin_log (admin_id, admin_email, action, target_user, amount, reason)
    values (auth.uid(), auth.jwt()->>'email', case when k = 'suspend' then 'chat_suspend' else 'chat_mute' end,
            p_user, p_hours, left(rsn, 200));
  return jsonb_build_object('ok', true, 'kind', k, 'until', until_at);
end $$;

create or replace function public.admin_chat_lift(p_user uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare rsn text := btrim(coalesce(p_reason, '')); n int;
begin
  perform public._admin_guard();
  if p_user is null then raise exception 'invalid user'; end if;
  if char_length(rsn) < 1 then raise exception 'bad reason'; end if;
  update chat_mutes set lifted_at = now(), lifted_by = auth.uid()
   where user_id = p_user and lifted_at is null;
  get diagnostics n = row_count;
  insert into admin_log (admin_id, admin_email, action, target_user, amount, reason)
    values (auth.uid(), auth.jwt()->>'email', 'chat_lift', p_user, n, left(rsn, 200));
  return jsonb_build_object('ok', true, 'lifted', n);
end $$;

create or replace function public.admin_chat_user(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  if p_user is null then raise exception 'invalid user'; end if;
  return jsonb_build_object('ok', true, 'user', public._memo_card(p_user),
    'sanction', public._memo_sanction(p_user),
    'mutes', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'until', until, 'reason', reason,
        'created_at', created_at, 'lifted_at', lifted_at) order by id desc)
      from (select * from chat_mutes where user_id = p_user order by id desc limit 20) x
    ), '[]'::jsonb));
end $$;

-- 5) 보관 만료 (30일, 신고된 쪽지는 남김). 인증 유저에게는 열지 않음.
create or replace function public.memo_purge_expired() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from memos m
   where m.created_at < now() - interval '30 days'
     and not exists (select 1 from chat_reports r where r.memo_id = m.id);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;

create or replace function public.friend_memos_install_ok() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ok',
      to_regclass('public.memos') is not null
      and to_regclass('public.player_blocks') is not null
      and to_regclass('public.chat_reports') is not null
      and to_regclass('public.chat_mutes') is not null
      and to_regclass('public.feature_flags') is not null
      and to_regprocedure('public.memo_status()') is not null
      and to_regprocedure('public.memo_send(uuid, text)') is not null
      and to_regprocedure('public.memo_list(text, integer)') is not null
      and to_regprocedure('public.player_block(uuid)') is not null
      and to_regprocedure('public.chat_report(bigint, text)') is not null
      and to_regprocedure('public.admin_feature_flag_set(text, boolean)') is not null
      and to_regprocedure('public.admin_chat_reports(text, integer)') is not null
      and to_regprocedure('public.admin_memo_hide(bigint, text)') is not null
      and to_regprocedure('public.admin_memo_delete(bigint, text)') is not null
      and to_regprocedure('public.admin_chat_mute(uuid, text, integer, text)') is not null
      and to_regprocedure('public.admin_chat_lift(uuid, text)') is not null
      and exists (select 1 from feature_flags where key = 'friend_memos'),
    'flag_on', coalesce((select enabled from feature_flags where key = 'friend_memos'), false),
    'flag', 'friend_memos'
  )
$$;

revoke all on function public.memo_status(), public.memo_unread(), public.memo_list(text, integer), public.memo_send(uuid, text),
  public.memo_read(bigint), public.player_block(uuid), public.player_unblock(uuid), public.player_blocks(),
  public.chat_report(bigint, text),
  public.admin_feature_flag_get(), public.admin_feature_flag_set(text, boolean),
  public.admin_chat_reports(text, integer), public.admin_chat_report_review(bigint, text, text),
  public.admin_memo_hide(bigint, text), public.admin_memo_delete(bigint, text),
  public.admin_chat_mute(uuid, text, integer, text), public.admin_chat_lift(uuid, text), public.admin_chat_user(uuid),
  public.memo_purge_expired(), public.friend_memos_install_ok()
  from public, anon;

grant execute on function public.memo_status(), public.memo_unread(), public.memo_list(text, integer), public.memo_send(uuid, text),
  public.memo_read(bigint), public.player_block(uuid), public.player_unblock(uuid), public.player_blocks(),
  public.chat_report(bigint, text),
  public.admin_feature_flag_get(), public.admin_feature_flag_set(text, boolean),
  public.admin_chat_reports(text, integer), public.admin_chat_report_review(bigint, text, text),
  public.admin_memo_hide(bigint, text), public.admin_memo_delete(bigint, text),
  public.admin_chat_mute(uuid, text, integer, text), public.admin_chat_lift(uuid, text), public.admin_chat_user(uuid),
  public.friend_memos_install_ok()
  to authenticated;

revoke all on function public.memo_purge_expired() from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
