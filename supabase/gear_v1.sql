-- ===== 장비 시스템 v1 (PR1: DB 기반만, UI 없음) =====
-- 설계: 장비 시스템 초안 v4 Page. 여러 번 실행해도 안전 (if not exists / on conflict / create or replace)
-- 의존: phaseE_1.sql (player_wallet, wallet_log), gem.sql (_gem_spend), story_progress (owned[].id)
-- 등급 tier: 1 낡은 · 2 일반 · 3 고급 · 4 희귀 · 5 영웅 · 6 전설 · 7 심연 (6·7 = 이벤트 전용, event_only)
-- 쓰기는 전부 security definer RPC. 테이블은 정의=모두 읽기, 보유=본인만 읽기, 직접 쓰기 불가

-- 1) 정의 테이블 -------------------------------------------------------------
create table if not exists public.gear_defs (
  id         text primary key,                       -- 예: weapon_4_2
  slot       text not null check (slot in ('weapon','armor','acc')),
  tier       int  not null check (tier between 1 and 7),
  name       text not null,
  icon       text not null,                          -- img/gear/{slot}_{tier}_{n}.webp
  main_stat  text not null check (main_stat in ('atk','hp','def','crit','evade','mp')),
  main_pct   numeric not null check (main_pct > 0),  -- 무기 ATK +2%..+14% 등
  opt_count  int  not null default 0 check (opt_count between 0 and 3),
  event_only boolean not null default false,
  raid_only  boolean not null default false
);
create table if not exists public.gear_opt_pool (       -- 랜덤 부옵션 범위 (slot별)
  slot text not null, opt text not null, min_v numeric not null, max_v numeric not null, min_tier int not null default 3,
  primary key (slot, opt)
);
create table if not exists public.gear_tier_gate (      -- 챕터·탑 대역 → 드롭 등급
  band       int primary key,                           -- 1..6
  ch_from    int not null, ch_to int not null, floor_from int not null, floor_to int not null,
  main_tier  int not null check (main_tier between 1 and 5),
  bonus_tier int not null check (bonus_tier between 1 and 5),
  bonus_pct  numeric not null check (bonus_pct between 0 and 100)
);
create table if not exists public.gear_drop_mode (      -- 난이도 모드 배율
  mode text primary key check (mode in ('normal','hard','hell','abyss')),
  bonus_mult numeric not null, up_pct numeric not null, sigil_frag_pct numeric not null
);
create table if not exists public.gear_mode_config (    -- 모드별 장비 효과 (사용자 조절값)
  mode text primary key check (mode in ('story','tower','raid','pvp','war','arcade')),
  gear_pct numeric not null check (gear_pct between 0 and 100),
  sigil_max_plus int not null check (sigil_max_plus between 0 and 5)
);
create table if not exists public.gear_slot_price (     -- 가방 확장 (10칸 단위, 보석)
  slots_from int primary key, slots_to int not null, gem int not null check (gem > 0)
);
create table if not exists public.gear_raid_rewards (   -- 토벌 보상표 (PR5에서 사용)
  id serial primary key, kind text not null check (kind in ('drop','clear_box','rank_box')),
  stage_from int not null default 0, stage_to int not null default 0, rank_from int not null default 0, rank_to int not null default 0,
  tier int not null check (tier between 1 and 5), up_tier int check (up_tier between 1 and 5), up_pct numeric not null default 0,
  qty int not null default 1, sigil_frags int not null default 0,
  unique (kind, stage_from, rank_from)
);
create table if not exists public.gear_event_grants (   -- 전설·심연은 여기 적힌 것만 지급 (PR7, 지금은 비어 있음)
  id serial primary key, event_key text not null, def_id text not null references public.gear_defs(id),
  starts_at timestamptz not null, ends_at timestamptz not null, note text,
  unique (event_key, def_id)
);
create table if not exists public.sigil_defs (
  card_id   text primary key,                          -- data/cards.csv id
  name      text not null,
  effects   int  not null check (effects in (1,2)),   -- SR 1, UR 이상 2
  steps     jsonb not null,                            -- [{plus:0, mods:{...}}, ... +5]
  icon      text not null
);
create table if not exists public.sigil_sources (       -- 인재별 조각 획득처 (최소 2곳)
  card_id text not null references public.sigil_defs(card_id), source text not null
    check (source in ('story_boss','raid_select','guild_shop','pvp_shop','event','exchange')),
  ref text, primary key (card_id, source)
);
create table if not exists public.sigil_cost (          -- 단계별 필요 조각: 제작 50, +1 30, +2 50, +3 80, +4 120, +5 200 = 530
  plus int primary key check (plus between 0 and 5), frags int not null check (frags > 0)
);

-- 2) 보유 테이블 -------------------------------------------------------------
create table if not exists public.player_gear (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  def_id      text not null references public.gear_defs(id),
  plus        int  not null default 0 check (plus between 0 and 5),
  opts        jsonb not null default '[]'::jsonb,
  locked      boolean not null default false,
  equipped_card text,                                  -- story_progress owned[].id
  source      text not null,
  created_at  timestamptz not null default now()
);
create index if not exists player_gear_user on public.player_gear (user_id);
create unique index if not exists player_gear_one_slot on public.player_gear (user_id, equipped_card, (split_part(def_id, '_', 1))) where equipped_card is not null;
create table if not exists public.player_gear_meta (
  user_id uuid primary key references auth.users(id) on delete cascade,
  slots   int not null default 100 check (slots between 100 and 200),
  dust    bigint not null default 0 check (dust >= 0),   -- 장비 가루 (분해 재료)
  updated_at timestamptz not null default now()
);
create table if not exists public.player_sigils (
  user_id uuid not null references auth.users(id) on delete cascade,
  card_id text not null references public.sigil_defs(card_id),
  plus    int check (plus between 0 and 5),              -- null = 아직 제작 전 (조각만 있음)
  frags   int not null default 0 check (frags >= 0),
  primary key (user_id, card_id)
);
create table if not exists public.player_mail (          -- 우편함 (기존 우편함 없음 → 신설). 7일 보관
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('gear','sigil_frag','gold','gem')),
  payload jsonb not null, reason text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  claimed_at timestamptz
);
create index if not exists player_mail_user on public.player_mail (user_id) where claimed_at is null;

-- 3) RLS ---------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['gear_defs','gear_opt_pool','gear_tier_gate','gear_drop_mode','gear_mode_config','gear_slot_price','gear_raid_rewards','sigil_defs','sigil_sources','sigil_cost'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
  foreach t in array array['player_gear','player_gear_meta','player_sigils','player_mail'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_own', t);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid())', t || '_own', t);
  end loop;
end $$;
alter table public.gear_event_grants enable row level security;          -- 이벤트 표는 클라이언트 비공개
revoke all on public.gear_event_grants from public, anon, authenticated;

-- 4) 내부 함수 ---------------------------------------------------------------
create or replace function public._gear_meta(p_uid uuid) returns public.player_gear_meta
language plpgsql security definer set search_path = public as $$
declare m player_gear_meta;
begin
  insert into player_gear_meta (user_id) values (p_uid) on conflict (user_id) do nothing;
  select * into m from player_gear_meta where user_id = p_uid for update;
  return m;
end $$;

-- 랜덤 부옵션
create or replace function public._gear_roll_opts(p_def text) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare d gear_defs; r jsonb := '[]'::jsonb; o record;
begin
  select * into d from gear_defs where id = p_def;
  for o in select * from gear_opt_pool where slot = d.slot and min_tier <= d.tier order by random() limit d.opt_count loop
    r := r || jsonb_build_array(jsonb_build_object('opt', o.opt, 'v', round((o.min_v + random() * (o.max_v - o.min_v))::numeric, 1)));
  end loop;
  return r;
end $$;

-- 장비 지급 (유일한 생성 경로). 영웅(5) 초과는 이벤트 지급표에 있을 때만
-- p_to_mail=true 면 가방이 꽉 차도 우편함으로. false 면 꽉 찼을 때 'bag full' 예외 (소탕·탑은 시작 전에 막음)
create or replace function public._gear_grant(p_uid uuid, p_def text, p_source text, p_to_mail boolean default false, p_event text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d gear_defs; m player_gear_meta; n int; gid bigint;
begin
  if p_uid is null then raise exception 'login required'; end if;
  select * into d from gear_defs where id = p_def;
  if not found then raise exception 'unknown gear'; end if;
  if d.tier > 5 or d.event_only then
    if p_source <> 'event' or p_event is null or not exists (
      select 1 from gear_event_grants e where e.event_key = p_event and e.def_id = p_def and now() between e.starts_at and e.ends_at)
    then raise exception 'tier above hero is event only'; end if;
  end if;
  m := _gear_meta(p_uid);
  select count(*) into n from player_gear where user_id = p_uid;
  if n >= m.slots then
    if not p_to_mail then raise exception 'bag full'; end if;
    insert into player_mail (user_id, kind, payload, reason) values (p_uid, 'gear', jsonb_build_object('def_id', p_def, 'source', p_source, 'event', p_event), p_source);
    return jsonb_build_object('ok', true, 'mail', true);
  end if;
  insert into player_gear (user_id, def_id, opts, source, locked)
    values (p_uid, p_def, _gear_roll_opts(p_def), p_source, d.tier >= 6) returning id into gid;
  return jsonb_build_object('ok', true, 'gear_id', gid);
end $$;

-- 드롭 등급 결정 (소탕·탑). 결과는 항상 1..5. 모드 보너스도 영웅에서 멈춤
create or replace function public._gear_roll_tier(p_chapter int, p_floor int, p_mode text default 'normal') returns int
language plpgsql volatile security definer set search_path = public as $$
declare g gear_tier_gate; dm gear_drop_mode; t int;
begin
  select * into g from gear_tier_gate
    where (p_chapter is not null and p_chapter between ch_from and ch_to) or (p_floor is not null and p_floor between floor_from and floor_to)
    order by band desc limit 1;
  if not found then select * into g from gear_tier_gate order by band limit 1; end if;
  select * into dm from gear_drop_mode where mode = coalesce(p_mode, 'normal');
  if not found then select * into dm from gear_drop_mode where mode = 'normal'; end if;
  t := g.main_tier;
  if random() * 100 < g.bonus_pct * dm.bonus_mult then t := g.bonus_tier; end if;
  if random() * 100 < dm.up_pct then t := t + 1; end if;
  return least(t, 5);
end $$;

-- 장비 1개 드롭 (슬롯 랜덤). 영웅 초과는 _gear_grant 에서도 다시 거부
create or replace function public._gear_drop(p_uid uuid, p_chapter int, p_floor int, p_mode text, p_source text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t int; did text;
begin
  t := _gear_roll_tier(p_chapter, p_floor, p_mode);
  select id into did from gear_defs where tier = t and not event_only and not raid_only order by random() limit 1;
  return _gear_grant(p_uid, did, p_source, false, null);
end $$;

revoke all on function public._gear_meta(uuid), public._gear_roll_opts(text), public._gear_grant(uuid, text, text, boolean, text),
  public._gear_roll_tier(int, int, text), public._gear_drop(uuid, int, int, text, text) from public, anon, authenticated;

-- 5) 공개 RPC (authenticated) ------------------------------------------------
-- 내 장비·증표·가방·우편 요약
create or replace function public.gear_status() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m player_gear_meta; nx gear_slot_price;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _gear_meta(uid);
  select * into nx from gear_slot_price where slots_from = m.slots + 1;
  return jsonb_build_object(
    'slots', m.slots, 'dust', m.dust,
    'count', (select count(*) from player_gear where user_id = uid),
    'next_expand', case when nx.slots_from is null then null else jsonb_build_object('to', nx.slots_to, 'gem', nx.gem) end,
    'gear', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'def', g.def_id, 'plus', g.plus, 'opts', g.opts, 'locked', g.locked, 'card', g.equipped_card) order by g.id)
                      from player_gear g where g.user_id = uid), '[]'::jsonb),
    'sigils', coalesce((select jsonb_agg(jsonb_build_object('card', s.card_id, 'plus', s.plus, 'frags', s.frags)) from player_sigils s where s.user_id = uid), '[]'::jsonb),
    'mail', (select count(*) from player_mail where user_id = uid and claimed_at is null and expires_at > now()));
end $$;

-- 가방 확장 10칸 (보석)
create or replace function public.gear_expand() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m player_gear_meta; p gear_slot_price; g jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  m := _gear_meta(uid);
  select * into p from gear_slot_price where slots_from = m.slots + 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'max'); end if;
  g := _gem_spend(uid, p.gem, 'gear_expand', jsonb_build_object('to', p.slots_to));
  update player_gear_meta set slots = p.slots_to, updated_at = now() where user_id = uid;
  return jsonb_build_object('ok', true, 'slots', p.slots_to, 'gem', p.gem, 'wallet', g);
exception when others then
  if sqlerrm = 'not enough gem' then return jsonb_build_object('ok', false, 'reason', 'gem', 'need', p.gem); end if;
  raise;
end $$;

-- 잠금
create or replace function public.gear_lock(p_gear bigint, p_locked boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  update player_gear set locked = coalesce(p_locked, false) where id = p_gear and user_id = uid;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- 장착 (같은 인재 같은 슬롯에 있던 장비는 자동 해제). 인재는 story_progress.owned 에 있어야 함
create or replace function public.gear_equip(p_gear bigint, p_card text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; sl text;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into g from player_gear where id = p_gear and user_id = uid for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if not exists (select 1 from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o
                 where sp.user_id = uid and o->>'id' = p_card) then
    return jsonb_build_object('ok', false, 'reason', 'card not owned'); end if;
  sl := split_part(g.def_id, '_', 1);
  update player_gear set equipped_card = null where user_id = uid and equipped_card = p_card and split_part(def_id, '_', 1) = sl and id <> p_gear;
  update player_gear set equipped_card = p_card where id = p_gear;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.gear_unequip(p_gear bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  update player_gear set equipped_card = null where id = p_gear and user_id = uid;
  return jsonb_build_object('ok', found);
end $$;

-- 우편 목록
create or replace function public.mail_list() returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'payload', payload, 'reason', reason, 'expires_at', expires_at) order by id)
    from player_mail where user_id = uid and claimed_at is null and expires_at > now()), '[]'::jsonb);
end $$;

-- 우편 받기 (지금은 장비만. 가방이 차 있으면 거부)
create or replace function public.mail_claim(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); ml player_mail; d gear_defs; m player_gear_meta; n int; gid bigint;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into ml from player_mail where id = p_id and user_id = uid and claimed_at is null and expires_at > now() for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if ml.kind <> 'gear' then return jsonb_build_object('ok', false, 'reason', 'unsupported'); end if;
  m := _gear_meta(uid);
  select count(*) into n from player_gear where user_id = uid;
  if n >= m.slots then return jsonb_build_object('ok', false, 'reason', 'bag full'); end if;
  select * into d from gear_defs where id = ml.payload->>'def_id';
  -- 우편은 지급 시점에 이미 검사됨. 그래도 영웅 초과는 이벤트 우편만 허용
  if d.tier > 5 and coalesce(ml.payload->>'source', '') <> 'event' then return jsonb_build_object('ok', false, 'reason', 'event only'); end if;
  insert into player_gear (user_id, def_id, opts, source, locked) values (uid, d.id, _gear_roll_opts(d.id), 'mail:' || ml.reason, d.tier >= 6) returning id into gid;
  update player_mail set claimed_at = now() where id = p_id;
  return jsonb_build_object('ok', true, 'gear_id', gid);
end $$;

revoke all on function public.gear_status(), public.gear_expand(), public.gear_lock(bigint, boolean), public.gear_equip(bigint, text),
  public.gear_unequip(bigint), public.mail_list(), public.mail_claim(bigint) from public, anon;
grant execute on function public.gear_status(), public.gear_expand(), public.gear_lock(bigint, boolean), public.gear_equip(bigint, text),
  public.gear_unequip(bigint), public.mail_list(), public.mail_claim(bigint) to authenticated;

-- 6) 시드 데이터 -------------------------------------------------------------
insert into gear_defs (id, slot, tier, name, icon, main_stat, main_pct, opt_count, event_only, raid_only)
select v.id, v.slot, v.tier, v.name, 'img/gear/' || v.id || '.webp', v.ms, v.pct, v.oc, v.tier >= 6, false
from (values
  ('weapon_1_1','weapon',1,'녹슨 쇠파이프','atk',2,0),('weapon_1_2','weapon',1,'나무 배트','atk',2,0),('weapon_1_3','weapon',1,'각목','atk',2,0),
  ('weapon_2_1','weapon',2,'쇠파이프','atk',4,0),('weapon_2_2','weapon',2,'알루미늄 야구배트','atk',4,0),('weapon_2_3','weapon',2,'커터칼','atk',4,0),
  ('weapon_3_1','weapon',3,'강철 야구배트','atk',6,1),('weapon_3_2','weapon',3,'삼단봉','atk',6,1),('weapon_3_3','weapon',3,'너클봉','atk',6,1),
  ('weapon_4_1','weapon',4,'낫','atk',8,1),('weapon_4_2','weapon',4,'사시미','atk',8,1),('weapon_4_3','weapon',4,'체인','atk',8,1),
  ('weapon_5_1','weapon',5,'스턴건','atk',10,2),('weapon_5_2','weapon',5,'전기봉','atk',10,2),('weapon_5_3','weapon',5,'제작 강철 너클봉','atk',10,2),
  ('weapon_6_1','weapon',6,'전기톱','atk',12,2),('weapon_6_2','weapon',6,'권총','atk',12,2),('weapon_6_3','weapon',6,'환도','atk',12,2),
  ('weapon_7_1','weapon',7,'심연의 낫','atk',14,3),('weapon_7_2','weapon',7,'검은 권총','atk',14,3),('weapon_7_3','weapon',7,'혼이 담긴 사시미','atk',14,3),
  ('armor_1_1','armor',1,'닳은 교복','hp',2,0),('armor_1_2','armor',1,'늘어난 트레이닝복','def',2,0),
  ('armor_2_1','armor',2,'교복','hp',4,0),('armor_2_2','armor',2,'트레이닝복','def',4,0),('armor_2_3','armor',2,'후드티','hp',4,0),
  ('armor_3_1','armor',3,'가죽자켓','def',6,1),('armor_3_2','armor',3,'야상 점퍼','hp',6,1),('armor_3_3','armor',3,'작업복','def',6,1),
  ('armor_4_1','armor',4,'라이더 자켓','def',8,1),('armor_4_2','armor',4,'검은 정장','hp',8,1),('armor_4_3','armor',4,'롱코트','hp',8,1),
  ('armor_5_1','armor',5,'방검조끼','def',10,2),('armor_5_2','armor',5,'가죽 코트','hp',10,2),('armor_5_3','armor',5,'전술 점퍼','def',10,2),
  ('armor_6_1','armor',6,'방탄조끼','def',12,2),('armor_6_2','armor',6,'주문 정장','hp',12,2),('armor_6_3','armor',6,'두리 방상 점퍼','def',12,2),
  ('armor_7_1','armor',7,'심연 정장','hp',14,3),('armor_7_2','armor',7,'심연 가죽자켓','def',14,3),
  ('acc_1_1','acc',1,'플라스틱 선글라스','crit',1,0),('acc_1_2','acc',1,'고무줄 팔찌','evade',1,0),
  ('acc_2_1','acc',2,'선글라스','crit',2,0),('acc_2_2','acc',2,'은반지','evade',2,0),('acc_2_3','acc',2,'손목시계','mp',2,0),
  ('acc_3_1','acc',3,'너클','crit',3,1),('acc_3_2','acc',3,'무전기','mp',3,1),('acc_3_3','acc',3,'은목걸이','evade',3,1),
  ('acc_4_1','acc',4,'금목걸이','crit',4,1),('acc_4_2','acc',4,'금반지','evade',4,1),('acc_4_3','acc',4,'호출기','mp',4,1),
  ('acc_5_1','acc',5,'금시계','crit',5,2),('acc_5_2','acc',5,'대포폰','mp',5,2),('acc_5_3','acc',5,'장미 문신 패치','evade',5,2),
  ('acc_6_1','acc',6,'두꺼운 금목걸이','crit',6,2),('acc_6_2','acc',6,'암호 무전기','mp',6,2),('acc_6_3','acc',6,'조직 배지','evade',6,2),
  ('acc_7_1','acc',7,'심연의 금목걸이','crit',7,3),('acc_7_2','acc',7,'검은 너클','crit',7,3),('acc_7_3','acc',7,'심연 선글라스','evade',7,3)
) v(id, slot, tier, name, ms, pct, oc)
on conflict (id) do update set slot = excluded.slot, tier = excluded.tier, name = excluded.name, icon = excluded.icon,
  main_stat = excluded.main_stat, main_pct = excluded.main_pct, opt_count = excluded.opt_count, event_only = excluded.event_only;

insert into gear_opt_pool (slot, opt, min_v, max_v, min_tier) values
  ('weapon','crit_dmg',3,10,3),('weapon','elem_dmg',2,8,3),('weapon','crit',1,3,3),
  ('armor','dmg_reduce',1,5,3),('armor','debuff_resist',3,10,3),('armor','evade',1,3,3),
  ('acc','mp_regen',1,5,3),('acc','kill_mp',2,6,3),('acc','cooldown',1,1,6)
on conflict (slot, opt) do update set min_v = excluded.min_v, max_v = excluded.max_v, min_tier = excluded.min_tier;

insert into gear_tier_gate (band, ch_from, ch_to, floor_from, floor_to, main_tier, bonus_tier, bonus_pct) values
  (1, 0, 5, 1, 29, 1, 2, 20), (2, 6, 10, 30, 59, 2, 3, 10), (3, 11, 15, 60, 89, 2, 4, 2),
  (4, 16, 20, 90, 119, 3, 4, 5), (5, 21, 25, 120, 149, 3, 5, 1), (6, 26, 30, 150, 100000, 4, 5, 3)
on conflict (band) do update set ch_from = excluded.ch_from, ch_to = excluded.ch_to, floor_from = excluded.floor_from, floor_to = excluded.floor_to,
  main_tier = excluded.main_tier, bonus_tier = excluded.bonus_tier, bonus_pct = excluded.bonus_pct;

insert into gear_drop_mode (mode, bonus_mult, up_pct, sigil_frag_pct) values
  ('normal', 1, 0, 15), ('hard', 1.5, 0.5, 20), ('hell', 2, 1, 25), ('abyss', 2.5, 2, 30)
on conflict (mode) do update set bonus_mult = excluded.bonus_mult, up_pct = excluded.up_pct, sigil_frag_pct = excluded.sigil_frag_pct;

insert into gear_mode_config (mode, gear_pct, sigil_max_plus) values
  ('story', 100, 5), ('tower', 100, 5), ('raid', 100, 5), ('pvp', 50, 3), ('war', 50, 3), ('arcade', 0, 0)
on conflict (mode) do nothing;   -- 사용자 조절값: 다시 실행해도 덮어쓰지 않음

insert into gear_slot_price (slots_from, slots_to, gem) values
  (101, 110, 100), (111, 120, 100), (121, 130, 150), (131, 140, 150), (141, 150, 200),
  (151, 160, 200), (161, 170, 400), (171, 180, 400), (181, 190, 1000), (191, 200, 1000)
on conflict (slots_from) do update set slots_to = excluded.slots_to, gem = excluded.gem;

insert into gear_raid_rewards (kind, stage_from, stage_to, rank_from, rank_to, tier, up_tier, up_pct, qty, sigil_frags) values
  ('drop', 1, 3, 0, 0, 3, 4, 10, 1, 0), ('drop', 4, 6, 0, 0, 4, null, 0, 1, 0), ('drop', 7, 99, 0, 0, 4, 5, 5, 1, 0),
  ('clear_box', 1, 6, 0, 0, 4, null, 0, 1, 0), ('clear_box', 7, 99, 0, 0, 4, 5, 15, 1, 0),
  ('rank_box', 0, 0, 1, 1, 5, null, 0, 1, 6), ('rank_box', 0, 0, 2, 3, 4, 5, 20, 2, 4),
  ('rank_box', 0, 0, 4, 10, 4, null, 0, 1, 3), ('rank_box', 0, 0, 11, 100000, 3, null, 0, 1, 2)
on conflict (kind, stage_from, rank_from) do nothing;

insert into sigil_cost (plus, frags) values (0, 50), (1, 30), (2, 50), (3, 80), (4, 120), (5, 200)
on conflict (plus) do update set frags = excluded.frags;

insert into sigil_defs (card_id, name, effects, icon, steps) values
('10118', '무답무용', 1, 'img/gear/sigil_10118.webp', '[
 {"plus":0,"skill":"무답무용","hit_pct":35,"hits":6,"bleed_pct":40},
 {"plus":1,"skill":"무답무용","hit_pct":40,"hits":6,"bleed_pct":45},
 {"plus":2,"skill":"무답무용","hit_pct":40,"hits":7,"bleed_pct":50,"cooldown":3},
 {"plus":3,"skill":"무답무용","hit_pct":45,"hits":7,"bleed_pct":60,"cooldown":3},
 {"plus":4,"skill":"무답무용","hit_pct":50,"hits":7,"bleed_pct":70,"cooldown":3},
 {"plus":5,"skill":"무답무용","hit_pct":50,"hits":7,"bleed_pct":70,"cooldown":3,"vs_bleed_dmg_pct":30,"on_kill_extra_hits":3}]'::jsonb),
('10415', '제발 그냥 가줘', 1, 'img/gear/sigil_10415.webp', '[
 {"plus":0,"skill":"제발 그냥 가줘","cooldown":6,"mp":75,"fallback_hp_pct":40},
 {"plus":1,"skill":"제발 그냥 가줘","cooldown":6,"mp":70,"fallback_hp_pct":50},
 {"plus":2,"skill":"제발 그냥 가줘","cooldown":5,"mp":65,"fallback_hp_pct":50,"also":{"skill":"나 좀 내버려둬","cooldown":4}},
 {"plus":3,"skill":"제발 그냥 가줘","cooldown":4,"mp":60,"fallback_hp_pct":60,"also":{"skill":"나 좀 내버려둬","cooldown":4}},
 {"plus":4,"skill":"제발 그냥 가줘","cooldown":4,"mp":55,"fallback_hp_pct":60,"also":{"skill":"나 좀 내버려둬","cooldown":4,"duration":2}},
 {"plus":5,"skill":"제발 그냥 가줘","cooldown":3,"mp":50,"fallback_hp_pct":60,"targets":2,"also":{"skill":"나 좀 내버려둬","cooldown":4,"duration":2}}]'::jsonb),
('10325', '피어난 키스', 2, 'img/gear/sigil_10325.webp', '[
 {"plus":0,"a":{"skill":"천천히 찢는 사랑","hit_pct":55,"hits":2,"bleed_pct":70},"b":{"hp_pct":[10,15],"cap":[160,240],"cc_pct":40}},
 {"plus":1,"a":{"skill":"천천히 찢는 사랑","hit_pct":60,"hits":2,"bleed_pct":75},"b":{"hp_pct":[10,15],"cap":[180,270],"cc_pct":45}},
 {"plus":2,"a":{"skill":"천천히 찢는 사랑","hit_pct":50,"hits":3,"bleed_pct":80},"b":{"hp_pct":[12,18],"cap":[200,300],"cc_pct":50}},
 {"plus":3,"a":{"skill":"천천히 찢는 사랑","hit_pct":55,"hits":3,"bleed_pct":80,"bleed_dmg_pct":8},"b":{"hp_pct":[12,18],"cap":[200,300],"cc_pct":50,"mp":35}},
 {"plus":4,"a":{"skill":"천천히 찢는 사랑","hit_pct":60,"hits":3,"bleed_pct":90,"bleed_dmg_pct":8},"b":{"hp_pct":[14,20],"cap":[230,340],"cc_pct":55,"mp":35}},
 {"plus":5,"a":{"skill":"천천히 찢는 사랑","hit_pct":65,"hits":3,"bleed_pct":100,"bleed_dmg_pct":8,"vs_bleed_dmg_pct":30},"b":{"hp_pct":[15,22],"cap":[230,340],"cc_pct":60,"mp":35,"cc_then_bleed":true}}]'::jsonb)
on conflict (card_id) do update set name = excluded.name, effects = excluded.effects, icon = excluded.icon, steps = excluded.steps;

insert into sigil_sources (card_id, source, ref) values
  ('10118','story_boss',null),('10118','raid_select',null),('10118','pvp_shop',null),('10118','exchange',null),
  ('10415','story_boss',null),('10415','raid_select',null),('10415','pvp_shop',null),('10415','exchange',null),
  ('10325','story_boss',null),('10325','raid_select',null),('10325','guild_shop',null),('10325','exchange',null)
on conflict do nothing;
