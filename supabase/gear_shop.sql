-- ===== 장비 PR7: 조직 상점(충성) · PvP 상점(혼) — 증표 조각 · 장비 상자 · 장비 가루 =====
-- 선행: guild.sql(guild_shop · 충성) · phaseE_1.sql(지갑: 혼 = soul) · gear_v1/gear_drops/gear_sigil.sql. 여러 번 실행해도 안전
-- · 재화: 조직 상점 = 기존 충성(loyalty_wallet), PvP 상점 = 기존 혼(player_wallet.soul). 새 재화 없음
-- · v4 Page: 조직 상점 임유리 조각 주 3개 / PvP 상점 민홍기·최윤희 조각 주 3개 + 월 1회 선택 5개
-- · 장비 상자는 영웅까지 (전설·심연 없음). 상자는 우편함으로 → 열 때 슬롯 선택, 가방이 꽉 차면 못 엶 (PR4 와 같음)
-- · 가격·상자·가루 상품은 임시값. 표 값은 다시 실행해도 덮어쓰지 않음

-- 1) 조직 상점 상품 추가 (기존 guild_shop 표) ------------------------------------
insert into public.guild_shop (item, ord, price, gives, limit_kind, limit_n, min_level) values
  ('sigil_yuri', 10, 150,  '{"sigil":{"card":"10325","n":1}}', 'week', 3, 1),
  ('gbox_adv',   11, 400,  '{"gear_box":{"tier":3,"up_tier":4,"up_pct":10}}', 'week', 2, 1),
  ('gbox_rare',  12, 1200, '{"gear_box":{"tier":4,"up_tier":5,"up_pct":5}}', 'week', 1, 3),
  ('gdust10',    13, 100,  '{"dust":10}', 'day', 1, 1)
on conflict (item) do nothing;

-- 공통 지급: 상자(우편) · 증표 조각 · 가루. 나머지 키는 그대로 남겨 돌려줌
create or replace function public._shop_give_gear(p_uid uuid, p_gives jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb := '{}'::jsonb; b jsonb; mid bigint; t int;
begin
  if p_gives ? 'gear_box' then
    b := p_gives->'gear_box'; t := (b->>'tier')::int;
    if t < 1 or t > 5 or coalesce((b->>'up_tier')::int, 0) > 5 then raise exception 'box tier out of range'; end if;   -- 영웅까지
    insert into player_mail (user_id, kind, payload, reason, expires_at)
      values (p_uid, 'box', jsonb_build_object('tier', t, 'up_tier', (b->>'up_tier')::int, 'up_pct', coalesce((b->>'up_pct')::numeric, 0)), p_reason, now() + interval '14 days') returning id into mid;
    insert into gear_drop_log (user_id, source, def_id, mail_id, kind, seen) values (p_uid, p_reason, 'box_' || t, mid, 'box', true);
    res := res || jsonb_build_object('box_mail', mid);
  end if;
  if p_gives ? 'sigil' then
    if p_gives->'sigil' ? 'pick' then
      insert into player_mail (user_id, kind, payload, reason, expires_at)
        values (p_uid, 'sigil_frag', jsonb_build_object('n', (p_gives->'sigil'->>'n')::int, 'pick', p_gives->'sigil'->>'pick'), p_reason, now() + interval '14 days') returning id into mid;
      res := res || jsonb_build_object('sigil_mail', mid);
    else
      insert into player_sigils (user_id, card_id, plus, frags) values (p_uid, p_gives->'sigil'->>'card', null, (p_gives->'sigil'->>'n')::int)
        on conflict (user_id, card_id) do update set frags = player_sigils.frags + excluded.frags;
      res := res || jsonb_build_object('sigil', p_gives->'sigil');
    end if;
  end if;
  if p_gives ? 'dust' then res := res || jsonb_build_object('dust', _gear_dust_add(p_uid, (p_gives->>'dust')::int)); end if;
  return res;
end $$;
revoke all on function public._shop_give_gear(uuid, jsonb, text) from public, anon, authenticated;

-- guild.sql 의 guild_shop_buy 그대로 + 장비 상품
create or replace function public.guild_shop_buy(p_item text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m guild_members; s guild_shop; lv int; t int; res jsonb := '{}'::jsonb; w jsonb;
begin
  m := _guild_me(uid);
  if m.user_id is null then raise exception 'not in guild'; end if;
  perform pg_advisory_xact_lock(hashtext('guilduser:' || uid::text));
  select * into s from guild_shop where item = p_item and active;
  if s.item is null then raise exception 'invalid item'; end if;
  select level into lv from guilds where id = m.guild_id;
  if lv < s.min_level then raise exception 'guild level required %', s.min_level; end if;
  if _guild_shop_left(uid, s) = 0 or (s.limit_kind = 'once' and exists (select 1 from guild_titles where user_id = uid and title = s.gives->>'title')) then raise exception 'limit reached'; end if;
  perform _loyalty_add(uid, -s.price, 'shop:' || s.item, null, jsonb_build_object('gives', s.gives));
  if s.gives ? 'tickets' then
    insert into story_gacha (user_id, last_draw) values (uid, _guild_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (s.gives->>'tickets')::int, updated_at = now() where user_id = uid returning tickets into t;
    res := res || jsonb_build_object('tickets', t);
  end if;
  w := s.gives - 'tickets' - 'stamina' - 'title' - 'gear_box' - 'sigil' - 'dust';
  if w <> '{}'::jsonb then res := res || jsonb_build_object('wallet', _wallet_add(uid, w, 'guild_shop')); end if;
  if s.gives ? 'stamina' then res := res || jsonb_build_object('stamina', _player_stamina_add(uid, (s.gives->>'stamina')::int)); end if;
  if s.gives ? 'title' then insert into guild_titles (user_id, title) values (uid, s.gives->>'title') on conflict do nothing; end if;
  res := res || _shop_give_gear(uid, s.gives, 'guild_shop');   -- 장비 PR7
  return res || jsonb_build_object('ok', true, 'item', s.item, 'loyalty', (select balance from loyalty_wallet where user_id = uid));
end $$;
revoke all on function public.guild_shop_buy(text) from public, anon;
grant execute on function public.guild_shop_buy(text) to authenticated;

-- 2) PvP 상점 (혼) ------------------------------------------------------------
create table if not exists public.pvp_shop (
  item text primary key, ord int not null default 0, price int not null check (price > 0), gives jsonb not null,
  limit_grp text,                                                    -- 같은 묶음끼리 한도 공유 (예: 증표 조각 주 3개)
  limit_kind text check (limit_kind in ('day', 'week', 'month')), limit_n int, active boolean not null default true
);
insert into public.pvp_shop (item, ord, price, gives, limit_grp, limit_kind, limit_n) values
  ('sigil_min',   1, 10, '{"sigil":{"card":"10118","n":1}}', 'sigil_week', 'week', 3),
  ('sigil_yun',   2, 10, '{"sigil":{"card":"10415","n":1}}', 'sigil_week', 'week', 3),
  ('sigil_pick5', 3, 40, '{"sigil":{"pick":"pvp_shop","n":5}}', 'sigil_month', 'month', 1),
  ('gbox_rare',   4, 30, '{"gear_box":{"tier":4,"up_tier":5,"up_pct":5}}', 'gbox_rare', 'week', 1),
  ('gdust10',     5, 5,  '{"dust":10}', 'gdust10', 'day', 1)
on conflict (item) do nothing;
create table if not exists public.pvp_shop_log (
  id bigint generated always as identity primary key, user_id uuid not null references auth.users(id) on delete cascade,
  item text not null, grp text not null, price int not null, created_at timestamptz not null default now()
);
create index if not exists pvp_shop_log_user on public.pvp_shop_log (user_id, grp, created_at desc);
alter table public.pvp_shop enable row level security;
revoke all on public.pvp_shop from public, anon, authenticated;
grant select on public.pvp_shop to authenticated;
drop policy if exists pvp_shop_read on public.pvp_shop;
create policy pvp_shop_read on public.pvp_shop for select to authenticated using (true);
alter table public.pvp_shop_log enable row level security;
revoke all on public.pvp_shop_log from public, anon, authenticated;
grant select on public.pvp_shop_log to authenticated;
drop policy if exists pvp_shop_log_own on public.pvp_shop_log;
create policy pvp_shop_log_own on public.pvp_shop_log for select to authenticated using (user_id = auth.uid());

-- 남은 횟수 (KST 기준 하루·주(월요일)·달)
create or replace function public._pvp_shop_left(p_uid uuid, s pvp_shop) returns int language sql stable security definer set search_path = public as $$
  select case when s.limit_kind is null then null else greatest(0, s.limit_n - (select count(*)::int from pvp_shop_log l
    where l.user_id = p_uid and l.grp = coalesce(s.limit_grp, s.item)
      and l.created_at >= (date_trunc(s.limit_kind, now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'))) end $$;
revoke all on function public._pvp_shop_left(uuid, pvp_shop) from public, anon, authenticated;

create or replace function public.pvp_shop_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return jsonb_build_object('ok', true, 'soul', coalesce((select soul from player_wallet where user_id = uid), 0),
    'items', coalesce((select jsonb_agg(jsonb_build_object('item', s.item, 'price', s.price, 'gives', s.gives, 'grp', coalesce(s.limit_grp, s.item), 'limit_kind', s.limit_kind, 'limit_n', s.limit_n,
      'left', _pvp_shop_left(uid, s)) order by s.ord) from pvp_shop s where s.active), '[]'::jsonb));
end $$;

create or replace function public.pvp_shop_buy(p_item text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s pvp_shop; w jsonb; res jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('pvpshop:' || uid::text));
  select * into s from pvp_shop where item = p_item and active;
  if s.item is null then raise exception 'invalid item'; end if;
  if _pvp_shop_left(uid, s) = 0 then raise exception 'limit reached'; end if;
  w := _wallet_add(uid, jsonb_build_object('soul', -s.price), 'pvp_shop:' || s.item);   -- 부족하면 'not enough soul'
  insert into pvp_shop_log (user_id, item, grp, price) values (uid, s.item, coalesce(s.limit_grp, s.item), s.price);
  res := _shop_give_gear(uid, s.gives, 'pvp_shop');
  return res || jsonb_build_object('ok', true, 'item', s.item, 'wallet', w, 'left', _pvp_shop_left(uid, s));
end $$;
revoke all on function public.pvp_shop_status(), public.pvp_shop_buy(text) from public, anon;
grant execute on function public.pvp_shop_status(), public.pvp_shop_buy(text) to authenticated;
