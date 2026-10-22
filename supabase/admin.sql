-- =====================================================================
-- 관리자 페이지 (admin.html) 용 RPC — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 관리자: stevejean77@gmail.com 한 명. 판정은 전부 서버에서 (security definer 함수 안에서 매번 확인)
--   1) 호출자 JWT 의 email = 관리자 이메일
--   2) auth.users 에서 auth.uid() 의 email 도 같고, 이메일 인증(email_confirmed_at)이 끝났어야 함
--   둘 중 하나라도 아니면 'forbidden' 예외. anon(비로그인) 에게는 실행 권한 자체가 없음
-- 클라이언트는 anon 키 + 본인 세션만 사용. service_role 키는 쓰지 않음
-- 확인용: select public.admin_check();  → 관리자 { admin:true, email } / 그 외 { admin:false }
-- =====================================================================

-- 관리자 작업 기록 (소환권 지급 등). 클라이언트에서 직접 읽기/쓰기 불가 (정책 없음 + 권한 회수)
create table if not exists public.admin_log (
  id          bigint generated always as identity primary key,
  admin_id    uuid not null,
  admin_email text not null,
  action      text not null check (char_length(action) <= 40),
  target_user uuid references auth.users(id) on delete set null,
  amount      int,
  reason      text check (char_length(reason) <= 200),
  before_val  int,
  after_val   int,
  created_at  timestamptz not null default now()
);
create index if not exists admin_log_created_idx on public.admin_log (created_at desc);
alter table public.admin_log enable row level security;
revoke all on public.admin_log from public, anon, authenticated;

-- 관리자 판정 (내부용, 직접 호출 불가)
create or replace function public._is_admin() returns boolean language sql stable security definer set search_path = public, auth as $$
  select auth.uid() is not null
     and lower(coalesce(auth.jwt()->>'email', '')) = 'stevejean77@gmail.com'
     and exists (select 1 from auth.users u
                  where u.id = auth.uid()
                    and lower(u.email) = 'stevejean77@gmail.com'
                    and u.email_confirmed_at is not null)
$$;
revoke all on function public._is_admin() from public, anon, authenticated;

create or replace function public._admin_guard() returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public._is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
end $$;
revoke all on function public._admin_guard() from public, anon, authenticated;

-- 0) 확인용 (관리자 아니면 false. 예외 없음) — 새 RPC 확인은 이걸로
create or replace function public.admin_check() returns jsonb language plpgsql security definer set search_path = public, auth as $$
begin
  if public._is_admin() then return jsonb_build_object('admin', true, 'email', auth.jwt()->>'email'); end if;
  return jsonb_build_object('admin', false);
end $$;
revoke all on function public.admin_check() from public, anon;
grant execute on function public.admin_check() to authenticated;

-- 1) 가입 유저 목록 (구글 로그인: 이메일, 이름, 가입/마지막 로그인) + 소환권·카드 수·아케이드 전적
create or replace function public.admin_list_users(p_search text default null, p_limit int default 100, p_offset int default 0)
returns table (id uuid, email text, name text, provider text, created_at timestamptz, last_sign_in_at timestamptz,
               nickname text, tickets int, cards int, wins int, losses int, draws int)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return query
  select u.id, u.email::text,
         coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name')::text,
         coalesce(u.raw_app_meta_data->>'provider', '')::text,
         u.created_at, u.last_sign_in_at,
         p.nickname, coalesce(g.tickets, 0),
         coalesce(jsonb_array_length(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end), 0),
         (select count(*)::int from public.matches m where m.user_id = u.id and m.result = 'win'),
         (select count(*)::int from public.matches m where m.user_id = u.id and m.result = 'lose'),
         (select count(*)::int from public.matches m where m.user_id = u.id and m.result = 'draw')
    from auth.users u
    left join public.profiles p on p.id = u.id
    left join public.story_gacha g on g.user_id = u.id
    left join public.story_progress sp on sp.user_id = u.id
   where p_search is null or p_search = ''
      or u.email ilike '%' || p_search || '%'
      or coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '') ilike '%' || p_search || '%'
      or coalesce(p.nickname, '') ilike '%' || p_search || '%'
   order by u.created_at desc
   limit greatest(1, least(coalesce(p_limit, 100), 500)) offset greatest(0, coalesce(p_offset, 0));
end $$;
revoke all on function public.admin_list_users(text, int, int) from public, anon;
grant execute on function public.admin_list_users(text, int, int) to authenticated;

-- 2) 유저 상세: 보유 카드(스토리 owned) · 리더 · 스토리 진행 · 소환권 · 아케이드 전적 · 최근 판 · 갤러리
create or replace function public.admin_user_detail(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare u record; d jsonb; r jsonb;
begin
  perform public._admin_guard();
  select id, email, created_at, last_sign_in_at, raw_user_meta_data into u from auth.users where id = p_user;
  if u.id is null then raise exception 'no such user'; end if;
  select data into d from public.story_progress where user_id = p_user;
  d := coalesce(d, '{}'::jsonb);
  r := jsonb_build_object(
    'id', u.id, 'email', u.email, 'name', coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name'),
    'created_at', u.created_at, 'last_sign_in_at', u.last_sign_in_at,
    'nickname', (select nickname from public.profiles where id = p_user),
    'owned', coalesce(d->'owned', '[]'::jsonb), 'leader', d->'leader', 'starter', d->'starter',
    'cleared', coalesce(d->'cleared', '{}'::jsonb), 'points', coalesce(d->'points', '0'::jsonb),
    'tickets', coalesce((select tickets from public.story_gacha where user_id = p_user), 0),
    'record', (select jsonb_build_object('wins', count(*) filter (where result = 'win'), 'losses', count(*) filter (where result = 'lose'), 'draws', count(*) filter (where result = 'draw'))
                 from public.matches where user_id = p_user),
    'recent', coalesce((select jsonb_agg(x order by x.created_at desc) from (select result, reason, turns, damage, mvp_name, created_at from public.matches where user_id = p_user order by created_at desc limit 20) x), '[]'::jsonb),
    'gallery', (select jsonb_build_object('cards', count(*), 'mvp', coalesce(sum(mvp_count), 0)) from public.gallery where user_id = p_user)
  );
  return r;
end $$;
revoke all on function public.admin_user_detail(uuid) from public, anon;
grant execute on function public.admin_user_detail(uuid) to authenticated;

-- 3) 소환권 지급 (1~1000장, 사유 필수). admin_log 에 기록. 반환 { ok, tickets, before }
create or replace function public.admin_grant_tickets(p_user uuid, p_amount int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare b int; a int;
begin
  perform public._admin_guard();
  if p_amount is null or p_amount < 1 or p_amount > 1000 then raise exception 'amount must be 1..1000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  insert into public.story_gacha (user_id, last_draw) values (p_user, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  select tickets into b from public.story_gacha where user_id = p_user for update;
  update public.story_gacha set tickets = tickets + p_amount, updated_at = now() where user_id = p_user returning tickets into a;
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_tickets', p_user, p_amount, left(btrim(p_reason), 200), b, a);
  return jsonb_build_object('ok', true, 'tickets', a, 'before', b);
end $$;
revoke all on function public.admin_grant_tickets(uuid, int, text) from public, anon;
grant execute on function public.admin_grant_tickets(uuid, int, text) to authenticated;

-- 4) 유저 뽑기 기록 (매일 뽑기 + 소환권 뽑기)
create or replace function public.admin_gacha_log(p_user uuid, p_limit int default 200)
returns table (id bigint, card_id text, grade text, kind text, created_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return query select l.id, l.card_id, l.grade, l.kind, l.created_at from public.story_gacha_log l
    where l.user_id = p_user order by l.created_at desc limit greatest(1, least(coalesce(p_limit, 200), 1000));
end $$;
revoke all on function public.admin_gacha_log(uuid, int) from public, anon;
grant execute on function public.admin_gacha_log(uuid, int) to authenticated;

-- 5) 관리자 작업 기록 보기
create or replace function public.admin_logs(p_limit int default 100)
returns table (id bigint, admin_email text, action text, target_user uuid, target_email text, amount int, reason text, before_val int, after_val int, created_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  return query select l.id, l.admin_email, l.action, l.target_user, u.email::text, l.amount, l.reason, l.before_val, l.after_val, l.created_at
    from public.admin_log l left join auth.users u on u.id = l.target_user
    order by l.created_at desc limit greatest(1, least(coalesce(p_limit, 100), 1000));
end $$;
revoke all on function public.admin_logs(int) from public, anon;
grant execute on function public.admin_logs(int) to authenticated;
