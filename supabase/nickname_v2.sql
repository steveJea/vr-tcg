-- 닉네임 v2: 금지어 · 두 번째 변경부터 심연석 200개. nickname.sql · gem.sql 다음에 실행. 여러 번 실행해도 안전.

-- 1) 금지어 (공백·기호 빼고 소문자로 비교, 단어가 포함되면 막음). 형님이 표에 줄을 더하거나 지워서 관리 가능
create table if not exists public.nick_banned (word text primary key check (word = lower(word) and char_length(word) between 1 and 20));
alter table public.nick_banned enable row level security;
revoke all on public.nick_banned from anon, authenticated;
insert into public.nick_banned (word) values
  ('시발'),('씨발'),('씨바'),('씨팔'),('시팔'),('쓰발'),('ㅅㅂ'),('ㅆㅂ'),('ㅅㅍ'),('병신'),('븅신'),('빙신'),('ㅂㅅ'),('좆'),('존나'),('졸라'),('ㅈㄴ'),
  ('개새'),('새끼'),('색기'),('ㅅㄲ'),('지랄'),('ㅈㄹ'),('미친놈'),('미친년'),('미친새'),('엠창'),('느금'),('니미'),('니애미'),('애미'),('애비'),('에미'),
  ('섹스'),('보지'),('자지'),('창녀'),('걸레'),('꼴린'),('따먹'),('강간'),('한남'),('김치녀'),('틀딱'),('운영자'),('관리자'),('운영진'),
  ('fuck'),('fuk'),('shit'),('bitch'),('asshole'),('dick'),('pussy'),('cunt'),('nigger'),('nigga'),('faggot'),('slut'),('whore'),
  ('porn'),('rape'),('admin'),('operator'),('gamemaster')
on conflict do nothing;

create or replace function public._nick_norm(p text) returns text language sql immutable as $$
  select regexp_replace(lower(coalesce(p, '')), '[\s_.\-0-9]', '', 'g') $$;

-- 2) 검사: ok / short / long / bad / banned / taken
create or replace function public._nick_check(p text, uid uuid) returns text language sql stable security definer set search_path = public as $$
  select case
    when p is null or char_length(btrim(p)) < 2 then 'short'
    when char_length(btrim(p)) > 12 then 'long'
    when btrim(p) !~ '^[0-9A-Za-z가-힣ㄱ-ㅎㅏ-ㅣ _.\-]+$' or btrim(p) ~ '\s\s' then 'bad'
    when exists (select 1 from nick_banned b where position(b.word in _nick_norm(p)) > 0) then 'banned'
    when exists (select 1 from profiles x where lower(btrim(x.nickname)) = lower(btrim(p)) and x.id <> coalesce(uid, '00000000-0000-0000-0000-000000000000'::uuid)) then 'taken'
    else 'ok' end
$$;
revoke all on function public._nick_check(text, uuid), public._nick_norm(text) from public, anon, authenticated;

-- 3) 변경: 처음(아직 직접 안 정함)은 무료, 이미 정한 뒤 바꾸면 심연석 200 (무료분 먼저, 같은 트랜잭션에서 차감)
create or replace function public._nick_price() returns int language sql immutable as $$ select 200 $$;
create or replace function public.set_nickname(p_nick text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n text := btrim(p_nick); r text; was boolean; old text; cost int := 0; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('nick:' || lower(n)));
  select nick_set, nickname into was, old from profiles where id = uid for update;
  if coalesce(was, false) and old = n then raise exception 'nick same'; end if;
  r := _nick_check(n, uid);
  if r <> 'ok' then raise exception 'nick %', r; end if;
  if coalesce(was, false) then
    cost := _nick_price();
    begin g := _gem_spend(uid, cost, 'nickname', jsonb_build_object('from', old, 'to', n));
    exception when others then if sqlerrm ~ 'not enough' then raise exception 'nick gem'; else raise; end if; end;
  end if;
  perform set_config('app.nick_rpc', '1', true);
  insert into profiles (id, nickname, nick_set) values (uid, n, true)
    on conflict (id) do update set nickname = n, nick_set = true, updated_at = now();
  perform set_config('app.nick_rpc', '', true);
  return jsonb_build_object('ok', true, 'nickname', n, 'cost', cost);
exception when unique_violation then raise exception 'nick taken';
end $$;
revoke all on function public.set_nickname(text) from public, anon;
grant execute on function public.set_nickname(text) to authenticated;

-- 4) 로그인 안 한 사람(anon)은 닉네임 함수 못 씀 (Supabase 기본 권한이 anon 에게도 줘서 명시적으로 회수)
revoke execute on function public.nickname_check(text), public.set_nickname(text) from anon;
revoke execute on function public._nick_check(text, uuid), public._nick_norm(text), public._nick_price() from public, anon, authenticated;
grant execute on function public.nickname_check(text) to authenticated;
