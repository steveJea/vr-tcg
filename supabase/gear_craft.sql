-- ===== 장비 PR5: 강화 · 부옵션 재설정 · 분해 · 매각 =====
-- 선행: phaseE_1.sql(_wallet_add) · gear_v1.sql. 여러 번 실행해도 안전. 쓰기는 RPC 로만
-- · 강화 +1~+5 확정 성공, 비용 골드 1k·2k·4k·8k·15k + 가루 5·10·20·30·50 (v4 Page)
-- · 분해 → 장비 가루, 매각 → 골드 (v4 Page 표). 잠금·장착 장비는 불가 (하나라도 있으면 전체 거부)
-- · 재설정(부옵션 다시 굴리기): Page 에 값 없음 → 임시값 (gear_reroll_cost, 조절 가능)
-- · 표 값은 조절값: 다시 실행해도 덮어쓰지 않음 (on conflict do nothing)

create table if not exists public.gear_enhance_cost (plus int primary key check (plus between 1 and 5), gold int not null check (gold >= 0), dust int not null check (dust >= 0));
create table if not exists public.gear_salvage (tier int primary key check (tier between 1 and 7), dust int not null check (dust >= 0), gold int not null check (gold >= 0));
create table if not exists public.gear_reroll_cost (tier int primary key check (tier between 1 and 7), gold int not null check (gold >= 0), dust int not null check (dust >= 0));
insert into public.gear_enhance_cost (plus, gold, dust) values (1, 1000, 5), (2, 2000, 10), (3, 4000, 20), (4, 8000, 30), (5, 15000, 50) on conflict (plus) do nothing;
insert into public.gear_salvage (tier, dust, gold) values (1, 1, 100), (2, 2, 200), (3, 4, 500), (4, 8, 1000), (5, 15, 2000), (6, 30, 5000), (7, 60, 10000) on conflict (tier) do nothing;
insert into public.gear_reroll_cost (tier, gold, dust) values (3, 1000, 4), (4, 2000, 8), (5, 4000, 15), (6, 8000, 30), (7, 15000, 60) on conflict (tier) do nothing;   -- 임시값

do $$ declare t text; begin
  foreach t in array array['gear_enhance_cost', 'gear_salvage', 'gear_reroll_cost'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end $$;

-- 내 장비 한 개 (잠금 행)
create or replace function public._gear_mine(p_uid uuid, p_gear bigint) returns public.player_gear
language plpgsql security definer set search_path = public as $$
declare g player_gear;
begin
  if p_uid is null then raise exception 'login required'; end if;
  select * into g from player_gear where id = p_gear and user_id = p_uid for update;
  if not found then raise exception 'gear not found'; end if;
  return g;
end $$;
revoke all on function public._gear_mine(uuid, bigint) from public, anon, authenticated;

-- 가루 쓰기 (부족하면 예외)
create or replace function public._gear_dust_add(p_uid uuid, p_n bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare d bigint;
begin
  perform _gear_meta(p_uid);
  update player_gear_meta set dust = dust + p_n, updated_at = now() where user_id = p_uid and dust + p_n >= 0 returning dust into d;
  if d is null then raise exception 'not enough dust'; end if;
  return d;
end $$;
revoke all on function public._gear_dust_add(uuid, bigint) from public, anon, authenticated;

-- 강화: +1 (확정). 장착·잠금 상관없음
create or replace function public.gear_enhance(p_gear bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; c gear_enhance_cost; w jsonb; d bigint;
begin
  g := _gear_mine(uid, p_gear);
  if g.plus >= 5 then return jsonb_build_object('ok', false, 'reason', 'max plus'); end if;
  select * into c from gear_enhance_cost where plus = g.plus + 1;
  w := _wallet_add(uid, jsonb_build_object('gold', -c.gold), 'gear_enhance');   -- 부족하면 'not enough gold' (전체 롤백)
  d := _gear_dust_add(uid, -c.dust);
  update player_gear set plus = plus + 1 where id = g.id;
  return jsonb_build_object('ok', true, 'gear_id', g.id, 'plus', g.plus + 1, 'gold', c.gold, 'dust_used', c.dust, 'dust', d, 'wallet', w);
end $$;

-- 부옵션 재설정: 같은 개수로 다시 굴림 (부옵션 없는 1~2등급은 불가)
create or replace function public.gear_reroll(p_gear bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g player_gear; df gear_defs; c gear_reroll_cost; w jsonb; d bigint; o jsonb;
begin
  g := _gear_mine(uid, p_gear);
  select * into df from gear_defs where id = g.def_id;
  select * into c from gear_reroll_cost where tier = df.tier;
  if df.opt_count = 0 or c.tier is null then return jsonb_build_object('ok', false, 'reason', 'no options'); end if;
  w := _wallet_add(uid, jsonb_build_object('gold', -c.gold), 'gear_reroll');
  d := _gear_dust_add(uid, -c.dust);
  o := _gear_roll_opts(g.def_id);
  update player_gear set opts = o where id = g.id;
  return jsonb_build_object('ok', true, 'gear_id', g.id, 'opts', o, 'before', g.opts, 'gold', c.gold, 'dust_used', c.dust, 'dust', d, 'wallet', w);
end $$;

-- 분해·매각 공통 (여러 개). 잠금·장착·남의 장비가 하나라도 있으면 전체 거부
create or replace function public._gear_salvage(p_ids bigint[], p_sell boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; bad int; gold bigint; dust bigint; w jsonb := null; d bigint := null;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then return jsonb_build_object('ok', false, 'reason', 'empty'); end if;
  if cardinality(p_ids) > 200 then raise exception 'too many'; end if;
  perform 1 from player_gear where user_id = uid and id = any(p_ids) for update;
  select count(*), count(*) filter (where locked or equipped_card is not null) into n, bad from player_gear where user_id = uid and id = any(p_ids);
  if n <> (select count(distinct x) from unnest(p_ids) x) then return jsonb_build_object('ok', false, 'reason', 'not found'); end if;
  if bad > 0 then return jsonb_build_object('ok', false, 'reason', 'locked or equipped', 'count', bad); end if;
  select coalesce(sum(s.gold), 0), coalesce(sum(s.dust), 0) into gold, dust
    from player_gear g join gear_defs df on df.id = g.def_id join gear_salvage s on s.tier = df.tier where g.user_id = uid and g.id = any(p_ids);
  delete from player_gear where user_id = uid and id = any(p_ids);
  if p_sell then w := _wallet_add(uid, jsonb_build_object('gold', gold), 'gear_sell');
  else d := _gear_dust_add(uid, dust); end if;
  return jsonb_build_object('ok', true, 'count', n, 'gold', case when p_sell then gold else 0 end, 'dust_got', case when p_sell then 0 else dust end, 'dust', d, 'wallet', w);
end $$;
revoke all on function public._gear_salvage(bigint[], boolean) from public, anon, authenticated;
create or replace function public.gear_dismantle(p_ids bigint[]) returns jsonb language sql security definer set search_path = public as $$ select _gear_salvage(p_ids, false) $$;
create or replace function public.gear_sell(p_ids bigint[]) returns jsonb language sql security definer set search_path = public as $$ select _gear_salvage(p_ids, true) $$;

revoke all on function public.gear_enhance(bigint), public.gear_reroll(bigint), public.gear_dismantle(bigint[]), public.gear_sell(bigint[]) from public, anon;
grant execute on function public.gear_enhance(bigint), public.gear_reroll(bigint), public.gear_dismantle(bigint[]), public.gear_sell(bigint[]) to authenticated;
