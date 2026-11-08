-- Kakao/email-less profile compatibility: staging cuyqchmdcnsgzkwyclji ONLY.
-- Additive/idempotent. No existing rows, nicknames, UUIDs, progress, or rewards are changed.
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass and tgname = 'profiles_nick_guard' and not tgisinternal and tgenabled <> 'D') then
    raise exception 'STOP: nickname.sql setup is required first';
  end if;
end $guard$;
-- PROFILE_PATCH_BEGIN
-- Empty-email OAuth accounts can have an empty initial nickname. Preserve nick_set rules.
create or replace function public._profiles_nick_guard() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.nick_rpc', true), '') <> '1' then
    if new.nickname is null or btrim(new.nickname) = '' then new.nickname := '플레이어'; end if;
    if tg_op = 'INSERT' then new.nick_set := false;
    elsif new.nickname is distinct from old.nickname or new.nick_set is distinct from old.nick_set then new.nick_set := false; end if;
  end if;
  return new;
end $$;
-- PROFILE_PATCH_END
commit;
