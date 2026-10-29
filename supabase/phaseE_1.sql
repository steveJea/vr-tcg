-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 wallet_status 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- =====================================================================
-- 단계 E-1: 지갑(재화) — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 재화: gold(골드) · blood(순수한 피) · shard(이상한 조각) · soul(각성자의 혼)
-- 소환권은 기존 story_gacha.tickets 그대로 (이 파일은 건드리지 않음)
-- 쓰기는 전부 서버 함수(_wallet_add)로만. 클라이언트는 본인 지갑 읽기(wallet_status)만 가능
-- 획득처(스토리·퀘스트 드롭, 분해 수익)와 사용처는 이후 단계(E-2~)에서 _wallet_add 를 호출해 연결
-- 선행: admin.sql (관리자 지급 함수가 _admin_guard / admin_log 사용)
-- 확인용: select public.wallet_status();  → { ok:true, gold, blood, shard, soul }
-- =====================================================================

-- 1) 지갑
create table if not exists public.player_wallet (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  gold       bigint not null default 0 check (gold  >= 0),
  blood      bigint not null default 0 check (blood >= 0),
  shard      bigint not null default 0 check (shard >= 0),
  soul       bigint not null default 0 check (soul  >= 0),
  updated_at timestamptz not null default now()
);
alter table public.player_wallet enable row level security;
revoke all on public.player_wallet from public, anon, authenticated;
grant select on public.player_wallet to authenticated;
drop policy if exists "wallet_read_own" on public.player_wallet;
create policy "wallet_read_own" on public.player_wallet for select using (auth.uid() = user_id);

-- 2) 재화 변동 기록 (획득·사용 추적용, 클라이언트 접근 불가)
create table if not exists public.wallet_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  delta      jsonb not null,           -- {"gold":120,"blood":-30}
  after      jsonb not null,           -- 변동 후 잔액
  reason     text not null check (char_length(reason) <= 60),   -- 'story_clear', 'dismantle', 'card_levelup', 'admin' ...
  created_at timestamptz not null default now()
);
create index if not exists wallet_log_user_idx on public.wallet_log (user_id, created_at desc);
alter table public.wallet_log enable row level security;
revoke all on public.wallet_log from public, anon, authenticated;

-- 3) 내부 도우미: 재화 증감 (음수 = 사용). 잔액 부족이면 'not enough <key>' 예외 → 호출한 RPC 전체가 롤백
--    p_delta 키는 gold/blood/shard/soul 만, 값은 정수. 0 은 무시. 반환: 변동 후 잔액
create or replace function public._wallet_add(p_uid uuid, p_delta jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v jsonb; w player_wallet; g bigint; b bigint; s bigint; o bigint; clean jsonb := '{}'::jsonb; res jsonb;
begin
  if p_uid is null then raise exception 'login required'; end if;
  if jsonb_typeof(p_delta) <> 'object' then raise exception 'invalid delta'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  for k, v in select * from jsonb_each(p_delta) loop
    if k not in ('gold', 'blood', 'shard', 'soul') then raise exception 'invalid currency: %', k; end if;
    if jsonb_typeof(v) <> 'number' or v::text ~ '[.eE]' then raise exception 'invalid amount'; end if;
    if v::bigint <> 0 then clean := clean || jsonb_build_object(k, v::bigint); end if;
  end loop;
  insert into player_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into w from player_wallet where user_id = p_uid for update;
  g := w.gold  + coalesce((clean->>'gold')::bigint, 0);
  b := w.blood + coalesce((clean->>'blood')::bigint, 0);
  s := w.shard + coalesce((clean->>'shard')::bigint, 0);
  o := w.soul  + coalesce((clean->>'soul')::bigint, 0);
  if g < 0 then raise exception 'not enough gold'; end if;
  if b < 0 then raise exception 'not enough blood'; end if;
  if s < 0 then raise exception 'not enough shard'; end if;
  if o < 0 then raise exception 'not enough soul'; end if;
  res := jsonb_build_object('gold', g, 'blood', b, 'shard', s, 'soul', o);
  if clean <> '{}'::jsonb then
    update player_wallet set gold = g, blood = b, shard = s, soul = o, updated_at = now() where user_id = p_uid;
    insert into wallet_log (user_id, delta, after, reason) values (p_uid, clean, res, left(btrim(p_reason), 60));
  end if;
  return res;
end $$;
revoke all on function public._wallet_add(uuid, jsonb, text) from public, anon, authenticated;

-- 4) 공개 RPC: 내 지갑 (행이 없으면 0). 탐침(probe) 겸용
create or replace function public.wallet_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); w player_wallet;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into w from player_wallet where user_id = uid;
  return jsonb_build_object('ok', true, 'gold', coalesce(w.gold, 0), 'blood', coalesce(w.blood, 0), 'shard', coalesce(w.shard, 0), 'soul', coalesce(w.soul, 0));
end $$;
revoke all on function public.wallet_status() from public, anon;
grant execute on function public.wallet_status() to authenticated;

-- 5) 관리자: 유저 지갑 조회 / 재화 지급·회수 (admin_log 에 기록, 관리자 판정은 서버 _admin_guard)
create or replace function public.admin_user_wallet(p_user uuid) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare w player_wallet;
begin
  perform public._admin_guard();
  select * into w from player_wallet where user_id = p_user;
  return jsonb_build_object('gold', coalesce(w.gold, 0), 'blood', coalesce(w.blood, 0), 'shard', coalesce(w.shard, 0), 'soul', coalesce(w.soul, 0),
    'log', coalesce((select jsonb_agg(x order by x.created_at desc) from (select delta, after, reason, created_at from wallet_log where user_id = p_user order by created_at desc limit 50) x), '[]'::jsonb));
end $$;
revoke all on function public.admin_user_wallet(uuid) from public, anon;
grant execute on function public.admin_user_wallet(uuid) to authenticated;

-- p_amount: −1,000,000 ~ 1,000,000 (0 제외, 음수 = 회수). 반환 { ok, key, before, after, wallet }
create or replace function public.admin_grant_currency(p_user uuid, p_key text, p_amount int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare bef bigint; res jsonb;
begin
  perform public._admin_guard();
  if p_key not in ('gold', 'blood', 'shard', 'soul') then raise exception 'invalid currency'; end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'amount must be ±1..1000000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  select case p_key when 'gold' then gold when 'blood' then blood when 'shard' then shard else soul end into bef from player_wallet where user_id = p_user;
  bef := coalesce(bef, 0);
  res := public._wallet_add(p_user, jsonb_build_object(p_key, p_amount), 'admin');
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_' || p_key, p_user, p_amount, left(btrim(p_reason), 200), least(bef, 2147483647)::int, least((res->>p_key)::bigint, 2147483647)::int);
  return jsonb_build_object('ok', true, 'key', p_key, 'before', bef, 'after', (res->>p_key)::bigint, 'wallet', res);
end $$;
revoke all on function public.admin_grant_currency(uuid, text, int, text) from public, anon;
grant execute on function public.admin_grant_currency(uuid, text, int, text) to authenticated;
