-- 닉네임: 직접 정하기 · 2~12자 · 중복 금지(대소문자 무시). 여러 번 실행해도 안전.
-- 화면(랭킹·PvP·친구·조직 등)은 원래 profiles.nickname 을 쓰므로 이름 표시는 그대로 이 값을 따라감.
-- nick_set = 본인이 직접 정했는지. false 면 로그인 때 닉네임 짓기 창이 뜸 (기존 구글 이름은 그때까지 임시 표시).

alter table public.profiles add column if not exists nick_set boolean not null default false;

-- 직접 정한 닉네임끼리 중복 금지 (대소문자·앞뒤 공백 무시). 구글 이름(임시)은 기존 중복이 있어서 제외
create unique index if not exists profiles_nick_unique on public.profiles (lower(btrim(nickname))) where nick_set;

-- 클라이언트는 아바타만 직접 고칠 수 있음. 닉네임은 set_nickname() 으로만
revoke update on public.profiles from authenticated, anon;
grant update (avatar_url, updated_at) on public.profiles to authenticated;
revoke insert on public.profiles from authenticated, anon;
grant insert (id, nickname, avatar_url) on public.profiles to authenticated;

-- set_nickname 밖에서 닉네임이 바뀌면(관리자 초기화 등) '직접 정함' 표시를 풀어서 다시 짓게 함
create or replace function public._profiles_nick_guard() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.nick_rpc', true), '') <> '1' then
    if tg_op = 'INSERT' then new.nick_set := false;
    elsif new.nickname is distinct from old.nickname or new.nick_set is distinct from old.nick_set then new.nick_set := false; end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_nick_guard on public.profiles;
create trigger profiles_nick_guard before insert or update on public.profiles for each row execute function public._profiles_nick_guard();

-- 검사 (쓸 수 있는지만): ok / short / long / bad / taken
create or replace function public._nick_check(p text, uid uuid) returns text language sql stable security definer set search_path = public as $$
  select case
    when p is null or char_length(btrim(p)) < 2 then 'short'
    when char_length(btrim(p)) > 12 then 'long'
    when btrim(p) !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ _.\-]+$' or btrim(p) ~ '\s\s' then 'bad'
    when exists (select 1 from profiles x where lower(btrim(x.nickname)) = lower(btrim(p)) and x.id <> coalesce(uid, '00000000-0000-0000-0000-000000000000'::uuid)) then 'taken'
    else 'ok' end
$$;

create or replace function public.nickname_check(p_nick text) returns text
language sql stable security definer set search_path = public as $$ select public._nick_check(p_nick, auth.uid()) $$;

create or replace function public.set_nickname(p_nick text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text := btrim(p_nick); r text;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('nick:' || lower(n)));
  r := _nick_check(n, uid);
  if r <> 'ok' then raise exception 'nick %', r; end if;
  perform set_config('app.nick_rpc', '1', true);
  insert into profiles (id, nickname, nick_set) values (uid, n, true)
    on conflict (id) do update set nickname = n, nick_set = true, updated_at = now();
  perform set_config('app.nick_rpc', '', true);
  return jsonb_build_object('ok', true, 'nickname', n);
exception when unique_violation then raise exception 'nick taken';
end $$;

revoke all on function public._nick_check(text, uuid) from public, anon, authenticated;
revoke all on function public.nickname_check(text), public.set_nickname(text) from public;
grant execute on function public.nickname_check(text) to authenticated;
grant execute on function public.set_nickname(text) to authenticated;
