-- =====================================================================
-- 심연석 🔮 (유료 재화) 1단계 — Supabase SQL Editor 에서 실행. 여러 번 실행해도 안전
-- 선행: phaseE_1.sql(지갑) · phaseE_2.sql(행동력) · story_gacha.sql(소환권) · admin.sql · pvp.sql · pvp_tier.sql
-- 잔액: player_wallet.gem_paid(결제) + gem_free(무료). 화면에는 합계 하나. 사용은 무료 → 유료 순서
-- 쓰기는 전부 서버 함수로만: _gem_add / _gem_spend (클라이언트 호출 불가), 모든 변동은 gem_ledger 에 기록
--   gem_ledger.ref 는 유저별 고유 → 같은 보상(챕터·로그인·시즌 티어)·나중의 결제 주문이 두 번 들어가지 않음
-- 공개 RPC: gem_status() (챕터 첫 클리어·7일 연속 접속 보상 지급 포함) · gem_buy(item[, league, mode])
-- 관리자: admin_grant_gem(user, amount, reason) · admin_gem_ledger(user, limit)
-- 나중 결제: 결제 확인(Edge Function, service role)이 _gem_add(uid, 0, paid, 'iap', 'iap:<주문번호>', ...) 호출 → 환불은 같은 주문의 paid 만 회수
-- 확인용: select public.gem_status();
-- =====================================================================

-- 1) 잔액 (지갑에 열 추가)
alter table public.player_wallet add column if not exists gem_paid bigint not null default 0;
alter table public.player_wallet add column if not exists gem_free bigint not null default 0;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'player_wallet_gem_chk') then
    alter table public.player_wallet add constraint player_wallet_gem_chk check (gem_paid >= 0 and gem_free >= 0);
  end if;
end $$;

-- 2) 원장 (클라이언트 접근 불가 — 본인 기록은 gem_status 로만)
create table if not exists public.gem_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  d_free     int not null default 0,
  d_paid     int not null default 0,
  free_after bigint not null,
  paid_after bigint not null,
  reason     text not null check (char_length(reason) <= 40),   -- chapter_clear · login_7 · pvp_tier · pvp_streak · buy:<item> · admin · iap · refund
  ref        text not null default gen_random_uuid()::text,       -- 고유 참조 (chapter:3 · login:2026-10-27 · pvp_tier:open:1v1:2026-10-19 · iap:<주문>)
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, ref)
);
create index if not exists gem_ledger_user_idx on public.gem_ledger (user_id, created_at desc);
alter table public.gem_ledger enable row level security;
revoke all on public.gem_ledger from public, anon, authenticated;

-- 3) 상점 가격표 (한 곳에서 조정). step = 오늘 n번째 구매마다 가격 +step, daily_max = 하루 최대 (null = 무제한)
create table if not exists public.gem_shop (
  item      text primary key,
  ord       int not null default 0,
  price     int not null check (price > 0),
  step      int not null default 0 check (step >= 0),
  daily_max int,
  gives     jsonb not null,
  active    boolean not null default true
);
insert into public.gem_shop (item, ord, price, step, daily_max, gives) values
  ('ticket',   1,  150,  0, null, '{"tickets":1}'),
  ('pull10',   2, 1500,  0, null, '{"tickets":10}'),
  ('stamina',  3,  100, 50,    5, '{"stamina":"full"}'),
  ('pvp_try',  4,   50,  0,    3, '{"pvp_try":1}'),
  ('gold10k',  5,  100,  0, null, '{"gold":10000}')
on conflict (item) do update set ord = excluded.ord, price = excluded.price, step = excluded.step, daily_max = excluded.daily_max, gives = excluded.gives;
alter table public.gem_shop enable row level security;
revoke all on public.gem_shop from public, anon, authenticated;

-- 4) 연속 접속 (7일마다 +30)
create table if not exists public.gem_login (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  last_day date not null,
  streak   int not null default 1
);
alter table public.gem_login enable row level security;
revoke all on public.gem_login from public, anon, authenticated;

-- 5) 내부 도우미
create or replace function public._gem_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;
create or replace function public._gem_chapter_reward() returns int language sql immutable as $$ select 50 $$;
create or replace function public._gem_login_reward() returns int language sql immutable as $$ select 30 $$;

-- 증감 (양수 = 지급). p_ref 가 이미 있으면 아무것도 안 하고 null (중복 방지). 잔액 부족이면 'not enough gem' 예외 → 전체 롤백
create or replace function public._gem_add(p_uid uuid, p_free int, p_paid int, p_reason text, p_ref text, p_meta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w player_wallet; f bigint; p bigint;
begin
  if p_uid is null then raise exception 'login required'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if coalesce(p_free, 0) = 0 and coalesce(p_paid, 0) = 0 then return null; end if;
  insert into player_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into w from player_wallet where user_id = p_uid for update;
  if p_ref is not null and exists (select 1 from gem_ledger where user_id = p_uid and ref = p_ref) then return null; end if;
  f := w.gem_free + coalesce(p_free, 0); p := w.gem_paid + coalesce(p_paid, 0);
  if f < 0 or p < 0 then raise exception 'not enough gem'; end if;
  update player_wallet set gem_free = f, gem_paid = p, updated_at = now() where user_id = p_uid;
  insert into gem_ledger (user_id, d_free, d_paid, free_after, paid_after, reason, ref, meta)
  values (p_uid, coalesce(p_free, 0), coalesce(p_paid, 0), f, p, left(btrim(p_reason), 40), coalesce(p_ref, gen_random_uuid()::text), coalesce(p_meta, '{}'::jsonb));
  return jsonb_build_object('gem', f + p, 'free', f, 'paid', p, 'd_free', coalesce(p_free, 0), 'd_paid', coalesce(p_paid, 0));
end $$;

-- 사용: 무료 먼저, 모자라면 유료
create or replace function public._gem_spend(p_uid uuid, p_amount int, p_reason text, p_meta jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w player_wallet; fp int;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'invalid amount'; end if;
  insert into player_wallet (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into w from player_wallet where user_id = p_uid for update;
  if w.gem_free + w.gem_paid < p_amount then raise exception 'not enough gem'; end if;
  fp := least(w.gem_free, p_amount)::int;
  return _gem_add(p_uid, -fp, -(p_amount - fp), p_reason, null, p_meta);
end $$;

-- 오늘(KST) 이 상품을 몇 번 샀는지
create or replace function public._gem_bought(p_uid uuid, p_item text) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from gem_ledger where user_id = p_uid and reason = 'buy:' || p_item and created_at >= (_gem_day()::timestamp at time zone 'Asia/Seoul') $$;

-- 화면용 상태: 잔액 · 상점(오늘 가격·남은 횟수) · 최근 20건
create or replace function public._gem_json(p_uid uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w player_wallet;
begin
  select * into w from player_wallet where user_id = p_uid;
  return jsonb_build_object('ok', true, 'gem', coalesce(w.gem_free, 0) + coalesce(w.gem_paid, 0), 'free', coalesce(w.gem_free, 0), 'paid', coalesce(w.gem_paid, 0),
    'shop', (select coalesce(jsonb_agg(jsonb_build_object('item', s.item, 'price', s.price + s.step * least(b.n, coalesce(s.daily_max, b.n)), 'gives', s.gives,
                     'left', case when s.daily_max is null then null else greatest(0, s.daily_max - b.n) end) order by s.ord), '[]'::jsonb)
             from gem_shop s cross join lateral (select _gem_bought(p_uid, s.item) n) b where s.active),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('d', x.d_free + x.d_paid, 'after', x.free_after + x.paid_after, 'reason', x.reason, 'at', x.created_at) order by x.id desc), '[]'::jsonb)
            from (select * from gem_ledger where user_id = p_uid order by id desc limit 20) x),
    'login_streak', coalesce((select streak from gem_login where user_id = p_uid and last_day >= _gem_day() - 1), 0));
end $$;

-- 무료 획득 동기화: 챕터 첫 클리어(+50, 소급 포함) · 7일 연속 접속(+30). 반환 새로 받은 목록
create or replace function public._gem_sync(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare d jsonb; ch int; r jsonb; out jsonb := '[]'::jsonb; lg gem_login; today date := _gem_day();
begin
  select data into d from story_progress where user_id = p_uid;
  if d is not null then
    for ch in
      select c.chapter from story_phase_config c group by c.chapter
      having bool_and(case when jsonb_typeof(d->'cleared'->(c.chapter::text)) = 'array'
                           then (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase) or (d->'cleared'->(c.chapter::text)) @> to_jsonb(c.phase::text) else false end)
      order by c.chapter
    loop
      r := _gem_add(p_uid, _gem_chapter_reward(), 0, 'chapter_clear', 'chapter:' || ch, jsonb_build_object('chapter', ch));
      if r is not null then out := out || jsonb_build_array(jsonb_build_object('reason', 'chapter_clear', 'chapter', ch, 'gem', _gem_chapter_reward())); end if;
    end loop;
  end if;
  insert into gem_login (user_id, last_day, streak) values (p_uid, today - 1, 0) on conflict (user_id) do nothing;
  select * into lg from gem_login where user_id = p_uid for update;
  if lg.last_day < today then
    lg.streak := case when lg.last_day = today - 1 then lg.streak + 1 else 1 end;
    update gem_login set last_day = today, streak = lg.streak where user_id = p_uid;
    if lg.streak % 7 = 0 then
      r := _gem_add(p_uid, _gem_login_reward(), 0, 'login_7', 'login:' || today, jsonb_build_object('streak', lg.streak));
      if r is not null then out := out || jsonb_build_array(jsonb_build_object('reason', 'login_7', 'streak', lg.streak, 'gem', _gem_login_reward())); end if;
    end if;
  end if;
  return out;
end $$;
revoke all on function public._gem_add(uuid, int, int, text, text, jsonb), public._gem_spend(uuid, int, text, jsonb), public._gem_bought(uuid, text),
  public._gem_json(uuid), public._gem_sync(uuid) from public, anon, authenticated;

-- 6) 공개 RPC
-- 내 심연석 (+ 무료 획득 지급). 반환 { ok, gem, free, paid, shop, log, login_streak, granted:[...] }
create or replace function public.gem_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  g := _gem_sync(uid);
  return _gem_json(uid) || jsonb_build_object('granted', g);
end $$;

-- 구매. 가격·지급량은 서버 표(gem_shop)가 기준 (클라이언트는 상품 키만 보냄). pvp_try 는 리그·모드 필요
-- 오류: invalid item · daily limit · not enough gem · stamina full · (pvp) invalid league/mode
create or replace function public.gem_buy(p_item text, p_league text default null, p_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s gem_shop; n int; price int; res jsonb := '{}'::jsonb; ps player_state; mx int; t int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('gem:' || uid::text));
  select * into s from gem_shop where item = p_item and active;
  if s.item is null then raise exception 'invalid item'; end if;
  n := _gem_bought(uid, s.item);
  if s.daily_max is not null and n >= s.daily_max then raise exception 'daily limit'; end if;
  price := s.price + s.step * n;
  -- 지급 조건 먼저 확인 (실패하면 심연석도 안 빠짐)
  if s.item = 'stamina' then
    ps := _player_sync(uid); mx := _stamina_max(ps.level);
    if ps.stamina >= mx then raise exception 'stamina full'; end if;
  elsif s.item = 'pvp_try' then
    perform _pvp_ok(p_league, p_mode);
  end if;
  perform _gem_spend(uid, price, 'buy:' || s.item, jsonb_build_object('price', price, 'gives', s.gives) || case when s.item = 'pvp_try' then jsonb_build_object('league', p_league, 'mode', p_mode) else '{}'::jsonb end);
  if s.gives ? 'tickets' then
    insert into story_gacha (user_id, last_draw) values (uid, _gem_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (s.gives->>'tickets')::int, updated_at = now() where user_id = uid returning tickets into t;
    res := res || jsonb_build_object('tickets', t);
  end if;
  if s.gives ? 'gold' then res := res || jsonb_build_object('wallet', _wallet_add(uid, jsonb_build_object('gold', (s.gives->>'gold')::int), 'gem_buy')); end if;
  if s.gives ? 'stamina' then res := res || jsonb_build_object('stamina', _player_stamina_add(uid, mx)); end if;
  if s.gives ? 'pvp_try' then
    insert into pvp_bonus_tries (user_id, league, mode, day, n) values (uid, p_league, p_mode, _pvp_day(), 1)
      on conflict (user_id, league, mode, day) do update set n = pvp_bonus_tries.n + 1;
    res := res || jsonb_build_object('pvp_extra', _pvp_extra(uid, p_league, p_mode));
  end if;
  return _gem_json(uid) || res || jsonb_build_object('item', s.item, 'price', price);
end $$;
revoke all on function public.gem_status(), public.gem_buy(text, text, text) from public, anon;
grant execute on function public.gem_status(), public.gem_buy(text, text, text) to authenticated;

-- 7) 지갑 상태에 심연석 추가 (합계 gem + 내역 분리)
create or replace function public.wallet_status() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); w player_wallet;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into w from player_wallet where user_id = uid;
  return jsonb_build_object('ok', true, 'gold', coalesce(w.gold, 0), 'blood', coalesce(w.blood, 0), 'shard', coalesce(w.shard, 0), 'soul', coalesce(w.soul, 0),
    'gem', coalesce(w.gem_free, 0) + coalesce(w.gem_paid, 0), 'gem_free', coalesce(w.gem_free, 0), 'gem_paid', coalesce(w.gem_paid, 0));
end $$;
revoke all on function public.wallet_status() from public, anon;
grant execute on function public.wallet_status() to authenticated;

-- 8) 관리자: 무료 심연석 지급(+)/회수(−) · 원장 보기
create or replace function public.admin_grant_gem(p_user uuid, p_amount int, p_reason text) returns jsonb language plpgsql volatile security definer set search_path = public, auth as $$
declare bef bigint; res jsonb;
begin
  perform public._admin_guard();
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then raise exception 'amount must be ±1..1000000'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not exists (select 1 from auth.users where id = p_user) then raise exception 'no such user'; end if;
  select coalesce(gem_free, 0) + coalesce(gem_paid, 0) into bef from player_wallet where user_id = p_user;
  bef := coalesce(bef, 0);
  res := public._gem_add(p_user, p_amount, 0, 'admin', null, jsonb_build_object('by', auth.jwt()->>'email', 'memo', left(btrim(p_reason), 200)));
  insert into public.admin_log (admin_id, admin_email, action, target_user, amount, reason, before_val, after_val)
  values (auth.uid(), auth.jwt()->>'email', 'grant_gem', p_user, p_amount, left(btrim(p_reason), 200), least(bef, 2147483647)::int, least((res->>'gem')::bigint, 2147483647)::int);
  return jsonb_build_object('ok', true, 'before', bef, 'after', (res->>'gem')::bigint, 'free', (res->>'free')::bigint, 'paid', (res->>'paid')::bigint);
end $$;
create or replace function public.admin_gem_ledger(p_user uuid, p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare w player_wallet;
begin
  perform public._admin_guard();
  select * into w from player_wallet where user_id = p_user;
  return jsonb_build_object('gem', coalesce(w.gem_free, 0) + coalesce(w.gem_paid, 0), 'free', coalesce(w.gem_free, 0), 'paid', coalesce(w.gem_paid, 0),
    'log', coalesce((select jsonb_agg(jsonb_build_object('d_free', x.d_free, 'd_paid', x.d_paid, 'free_after', x.free_after, 'paid_after', x.paid_after, 'reason', x.reason, 'ref', x.ref, 'meta', x.meta, 'at', x.created_at) order by x.id desc)
                     from (select * from gem_ledger where user_id = p_user order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 500)) x), '[]'::jsonb));
end $$;
revoke all on function public.admin_grant_gem(uuid, int, text), public.admin_gem_ledger(uuid, int) from public, anon;
grant execute on function public.admin_grant_gem(uuid, int, text), public.admin_gem_ledger(uuid, int) to authenticated;


-- 9) PvP 연동 (pvp.sql / pvp_tier.sql 과 같은 정의 — 이 파일만 실행해도 되도록 복사. tools/test_gem_sql.mjs 가 일치 확인)
--    추가 도전권(pvp_bonus_tries) · 시즌 티어/10연승 보상에 심연석
-- 추가 도전권 (gem.sql 의 심연석 구매로 늘어남). 오늘(KST) 리그·모드별 추가 횟수
create table if not exists public.pvp_bonus_tries (
  user_id uuid not null references auth.users(id) on delete cascade, league text not null, mode text not null, day date not null,
  n int not null default 0 check (n >= 0), primary key (user_id, league, mode, day));
alter table public.pvp_bonus_tries enable row level security;
revoke all on public.pvp_bonus_tries from public, anon, authenticated;
create or replace function public._pvp_extra(p_uid uuid, p_league text, p_mode text) returns int language sql stable security definer set search_path = public as $$
  select coalesce((select n from pvp_bonus_tries where user_id = p_uid and league = p_league and mode = p_mode and day = (now() at time zone 'Asia/Seoul')::date), 0) $$;
revoke all on function public._pvp_extra(uuid, text, text) from public, anon, authenticated;
create or replace function public.pvp_start(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; me pvp_ratings; mine jsonb := '[]'::jsonb; d record;
        opp uuid; oname text; orat int; osnap jsonb := '[]'::jsonb; seed bigint; ex numeric; dw int; dl int; aid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('pvp:' || uid::text));
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  if used >= 10 + _pvp_extra(uid, p_league, p_mode) then raise exception 'no attempts left'; end if;
  if (select count(*) from pvp_decks where user_id = uid and league = p_league and mode = p_mode) < n then raise exception 'deck required'; end if;
  for d in select * from pvp_decks where user_id = uid and league = p_league and mode = p_mode order by slot loop
    mine := mine || jsonb_build_array(_pvp_snap(uid, d.uids, p_league)->'cards');
  end loop;
  me := _pvp_rating(uid, p_league, p_mode);
  -- 상대: 덱을 다 등록한 다른 유저 중 레이팅이 가까운 쪽 (약간의 무작위)
  select x.user_id, coalesce(r.rating, 1000) into opp, orat from (
      select user_id from pvp_decks where league = p_league and mode = p_mode and user_id <> uid group by user_id having count(*) >= n) x
    left join pvp_ratings r on r.user_id = x.user_id and r.league = p_league and r.mode = p_mode and r.season = _pvp_season()
    order by abs(coalesce(r.rating, 1000) - me.rating) + random() * 60 limit 1;
  if opp is not null then
    select coalesce(jsonb_agg(snap order by slot), '[]'::jsonb) into osnap from pvp_decks where user_id = opp and league = p_league and mode = p_mode and slot < n;
    select coalesce(nickname, '플레이어') into oname from profiles where id = opp;
    oname := coalesce(oname, '플레이어');
  else
    -- 상대 없음: 내 덱 거울 봇 (레벨 -10%)
    select coalesce(jsonb_agg((select coalesce(jsonb_agg(c || jsonb_build_object('level', greatest(1, round(coalesce((c->>'level')::int, 1) * 0.9)::int), 'boost', '{}'::jsonb)), '[]'::jsonb)
                               from jsonb_array_elements(dk) c)), '[]'::jsonb) into osnap from jsonb_array_elements(mine) dk;
    oname := '봇'; orat := me.rating;
  end if;
  ex := 1 / (1 + power(10, (orat - me.rating) / 400.0));
  dw := greatest(1, round(32 * (1 - ex))::int); dl := greatest(1, round(32 * ex)::int);
  if opp is null then dw := greatest(1, dw / 2); dl := greatest(1, dl / 2); end if;   -- 봇전은 절반
  seed := floor(random() * 2147483647)::bigint;
  insert into pvp_attempts (user_id, league, mode, season, day, opp_user, opp_name, seed, my_snap, opp_snap, my_rating, opp_rating, dw, dl)
  values (uid, p_league, p_mode, _pvp_season(), _pvp_day(), opp, oname, seed, mine, osnap, me.rating, orat, dw, dl) returning id into aid;
  update pvp_ratings set rating = rating - dl, losses = losses + 1, updated_at = now() where user_id = uid and league = p_league and mode = p_mode and season = _pvp_season();
  if opp is not null then perform _pvp_rating(opp, p_league, p_mode);
    update pvp_ratings set rating = rating + dl / 2, def_wins = def_wins + 1, updated_at = now() where user_id = opp and league = p_league and mode = p_mode and season = _pvp_season(); end if;
  return jsonb_build_object('id', aid, 'seed', seed, 'me', mine, 'opp', osnap, 'opp_name', oname, 'opp_rating', orat, 'rating', me.rating, 'dw', dw, 'dl', dl, 'left', 9 + _pvp_extra(uid, p_league, p_mode) - used, 'bot', opp is null);
end $$;
revoke all on function public.pvp_start(text, text) from public, anon;
grant execute on function public.pvp_start(text, text) to authenticated;
create or replace function public._pvp_grant(p_uid uuid, p_rw jsonb, p_reason text, p_league text, p_mode text, p_season date) returns void
language plpgsql security definer set search_path = public as $$
declare w jsonb := p_rw - 'tickets' - 'title' - 'gem';
begin
  if w <> '{}'::jsonb then perform _wallet_add(p_uid, w, p_reason); end if;
  if coalesce((p_rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (p_uid, _pvp_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (p_rw->>'tickets')::int, updated_at = now() where user_id = p_uid;
  end if;
  if coalesce((p_rw->>'gem')::int, 0) > 0 and to_regprocedure('public._gem_add(uuid,integer,integer,text,text,jsonb)') is not null then   -- 심연석 (gem.sql)
    perform _gem_add(p_uid, (p_rw->>'gem')::int, 0, p_reason, case when p_reason = 'pvp_tier' then 'pvp_tier:' || p_league || ':' || p_mode || ':' || p_season end, jsonb_build_object('league', p_league, 'mode', p_mode, 'season', p_season));
  end if;
  if p_rw ? 'title' then
    insert into pvp_titles (user_id, title, league, mode, season) values (p_uid, p_rw->>'title', p_league, p_mode, p_season) on conflict do nothing;
  end if;
end $$;
revoke all on function public._pvp_grant(uuid, jsonb, text, text, text, date) from public, anon, authenticated;
create or replace function public.pvp_status(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; r pvp_ratings; decks jsonb; prev pvp_ratings; pend jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  r := _pvp_rating(uid, p_league, p_mode);
  select coalesce(jsonb_agg(jsonb_build_object('slot', slot, 'uids', uids, 'cost', cost) order by slot), '[]'::jsonb) into decks
    from pvp_decks where user_id = uid and league = p_league and mode = p_mode;
  select * into prev from pvp_ratings where user_id = uid and league = p_league and mode = p_mode and season = _pvp_season() - 7;
  if prev.user_id is not null and prev.wins + prev.losses >= 3
     and not exists (select 1 from pvp_tier_claims where user_id = uid and league = p_league and mode = p_mode and season = prev.season) then
    pend := jsonb_build_object('season', prev.season, 'rating', prev.rating, 'tier', _pvp_tier(prev.rating));
  end if;
  return jsonb_build_object('left', greatest(0, 10 + _pvp_extra(uid, p_league, p_mode) - used), 'max', 10 + _pvp_extra(uid, p_league, p_mode), 'rating', r.rating, 'wins', r.wins, 'losses', r.losses,
    'def_wins', r.def_wins, 'def_losses', r.def_losses, 'decks', decks, 'need', n,
    'season', _pvp_season(), 'season_end', ((_pvp_season() + 7)::timestamp at time zone 'Asia/Seoul'),
    'tier', _pvp_tier(r.rating), 'streak', _pvp_streak(uid, p_league, p_mode, _pvp_season()),
    'abyss', exists (select 1 from pvp_titles where user_id = uid and title = 'abyss'),
    'tiers', (select jsonb_agg(jsonb_build_object('tier', tier, 'min', min_rating, 'reward', reward) order by ord) from pvp_tier_table),
    'streaks', (select jsonb_agg(jsonb_build_object('n', s.n, 'reward', s.reward) order by s.n) from pvp_streak_table s),
    'pending', pend);
end $$;
revoke all on function public.pvp_status(text, text) from public, anon;
grant execute on function public.pvp_status(text, text) to authenticated;
insert into public.pvp_tier_table (tier, ord, min_rating, reward) values
  ('bronze',   0,    0, '{"gold":200}'),
  ('silver',   1,  950, '{"gold":400,"shard":5,"gem":50}'),
  ('gold',     2, 1050, '{"gold":800,"soul":5,"tickets":3,"gem":100}'),
  ('platinum', 3, 1150, '{"gold":1500,"soul":10,"tickets":5,"gem":200}'),
  ('diamond',  4, 1250, '{"gold":2500,"soul":20,"tickets":10,"gem":400}'),
  ('abyss',    5, 1400, '{"gold":4000,"soul":35,"tickets":20,"gem":1000,"title":"abyss"}')
on conflict (tier) do update set ord = excluded.ord, min_rating = excluded.min_rating, reward = excluded.reward;
insert into public.pvp_streak_table (n, reward) values
  (3, '{"gold":300}'), (5, '{"gold":600,"soul":5}'), (10, '{"gold":1500,"soul":15,"tickets":3,"gem":30}')
on conflict (n) do update set reward = excluded.reward;
