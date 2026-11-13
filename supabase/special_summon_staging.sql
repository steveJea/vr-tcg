-- STAGING ONLY (cuyqchmdcnsgzkwyclji). Single atomic DO block for SQL Editor; idempotent, no save/balance resets.
-- Requires story gacha + premium UR. If shop BM exists, ticket_10/45/160/220 then grant special tickets. No SQL is executed automatically.
-- Production file is for the later approved release only. Initial banner starts 2026-11-13 KST, no end date yet.
-- v2 pity: UR 50 (any UR resets) + pickup after 2 non-pickup URs. Safe over v1 install (add-only columns, counters recomputed once from log).
do $install$
declare v2 boolean;
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
  raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only'; end if;
 if to_regclass('public.story_card_pool') is null or to_regclass('public.story_premium_ur') is null or to_regclass('public.story_gacha_log') is null
    or to_regprocedure('public._story_lock(uuid)') is null or to_regprocedure('public._story_owned(jsonb)') is null
    or to_regprocedure('public._story_new_card(text)') is null or to_regprocedure('public._story_save(uuid,jsonb)') is null then
  raise exception 'install story gacha and premium UR first'; end if;
-- ===== SPECIAL SUMMON =====

create table if not exists public.special_banners (
 id text primary key, pickup_id text not null references public.story_card_pool(id),
 starts_at timestamptz not null, ends_at timestamptz, active boolean not null default true,
 pity_limit int not null check(pity_limit between 1 and 10000), rates jsonb not null,
 check(ends_at is null or ends_at > starts_at)
);
create table if not exists public.special_wallet (
 user_id uuid primary key references auth.users(id) on delete cascade,
 tickets int not null default 0 check(tickets>=0)
);
create table if not exists public.special_pity (
 user_id uuid not null references auth.users(id) on delete cascade,
 banner_id text not null references public.special_banners(id), misses int not null default 0 check(misses>=0),
 primary key(user_id,banner_id)
);
create table if not exists public.special_summon_log (
 id bigint generated always as identity primary key, user_id uuid not null references auth.users(id) on delete cascade,
 banner_id text not null references public.special_banners(id), card_id text not null, grade text not null,
 guaranteed boolean not null, created_at timestamptz not null default now()
);
-- v2 (2026-11-13): misses = pulls since last UR (any UR). off_urs = non-pickup URs since last pickup.
v2 := not exists(select 1 from information_schema.columns where table_schema='public' and table_name='special_pity' and column_name='off_urs');
alter table public.special_banners add column if not exists pickup_after int not null default 2 check(pickup_after between 0 and 100);
alter table public.special_pity add column if not exists off_urs int not null default 0 check(off_urs>=0);
alter table public.special_summon_log add column if not exists guarantee text;
if v2 then   -- v1 pity rows counted pulls since last pickup: recompute both counters from the log once (no row deleted)
 update public.special_pity p set
  misses=(select count(*) from public.special_summon_log l where l.user_id=p.user_id and l.banner_id=p.banner_id
    and l.id>coalesce((select max(x.id) from public.special_summon_log x where x.user_id=p.user_id and x.banner_id=p.banner_id and x.grade='ULTRA RARE'),0)),
  off_urs=(select count(*) from public.special_summon_log l join public.special_banners sb on sb.id=l.banner_id where l.user_id=p.user_id and l.banner_id=p.banner_id
    and l.grade='ULTRA RARE' and l.card_id<>sb.pickup_id
    and l.id>coalesce((select max(x.id) from public.special_summon_log x where x.user_id=p.user_id and x.banner_id=p.banner_id and x.card_id=sb.pickup_id),0));
end if;
alter table public.special_banners enable row level security;
alter table public.special_wallet enable row level security;
alter table public.special_pity enable row level security;
alter table public.special_summon_log enable row level security;
-- RPC only: no client writes (including own tickets/pity). Own rows read-only.
revoke all on public.special_banners,public.special_wallet,public.special_pity,public.special_summon_log from public,anon,authenticated;
if not exists(select 1 from pg_policies where schemaname='public' and tablename='special_wallet' and policyname='special_wallet_own') then
 create policy special_wallet_own on public.special_wallet for select to authenticated using(user_id=auth.uid()); end if;
grant select on public.special_wallet to authenticated;
if not exists(select 1 from pg_policies where schemaname='public' and tablename='special_pity' and policyname='special_pity_own') then
 create policy special_pity_own on public.special_pity for select to authenticated using(user_id=auth.uid()); end if;
grant select on public.special_pity to authenticated;
if not exists(select 1 from pg_policies where schemaname='public' and tablename='special_summon_log' and policyname='special_summon_log_own') then
 create policy special_summon_log_own on public.special_summon_log for select to authenticated using(user_id=auth.uid()); end if;
grant select on public.special_summon_log to authenticated;
insert into public.special_banners(id,pickup_id,starts_at,ends_at,pity_limit,rates)
values('hajihye-20261113','10440','2026-11-13 00:00:00+09',null,50,'{"NORMAL":5000,"RARE":3000,"HIGH RARE":1000,"SUPER RARE":800,"pickup":100,"other_ur":100}')
on conflict(id) do nothing; -- rerun never resets event dates/config/pity
execute $ddl$create or replace function public._special_banner_json(b public.special_banners) returns jsonb
language sql stable security definer set search_path=pg_catalog,public as $fn$
 select jsonb_build_object('banner_id',b.id,'pickup_id',b.pickup_id,'pickup_name',(select name from public.story_card_pool where id=b.pickup_id),
 'starts_at',b.starts_at,'ends_at',b.ends_at,'pity',b.pity_limit,'pickup_after',b.pickup_after,'rates',b.rates,
 'open',b.active and now()>=b.starts_at and (b.ends_at is null or now()<b.ends_at)) $fn$;$ddl$;
execute $ddl$create or replace function public.special_summon_status(p_banner text default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $fn$
declare u uuid:=auth.uid(); b public.special_banners; t int; m int; o int;
begin
 if u is null then raise exception 'login required'; end if;
 if p_banner is null then
  select * into b from public.special_banners where active order by starts_at desc,id limit 1;
 else select * into b from public.special_banners where id=p_banner; end if;
 if b.id is null then return jsonb_build_object('ok',false,'reason','preparing'); end if;
 select tickets into t from public.special_wallet where user_id=u;
 select misses,off_urs into m,o from public.special_pity where user_id=u and banner_id=b.id;
 return jsonb_build_object('ok',true,'tickets',coalesce(t,0),'misses',coalesce(m,0),'off_urs',coalesce(o,0),'banner',public._special_banner_json(b),
  'pool',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'grade',p.grade) order by p.id),'[]'::jsonb)
    from public.story_card_pool p where p.grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE') and coalesce(p.gacha,true)),
  'premium_ur',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'grade',p.grade) order by p.id),'[]'::jsonb)
    from public.story_card_pool p join public.story_premium_ur w on w.id=p.id where p.grade='ULTRA RARE'));
end $fn$;$ddl$;
execute $ddl$create or replace function public._special_grade(r double precision, rates jsonb) returns text
language plpgsql immutable set search_path=pg_catalog,public as $fn$
declare k text; acc int:=0; total int:=0; v int;
begin
 foreach k in array array['NORMAL','RARE','HIGH RARE','SUPER RARE','pickup','other_ur'] loop
  v:=(rates->>k)::int; if v is null or v<0 then raise exception 'invalid rates'; end if; total:=total+v;
 end loop;
 if total<>10000 or r is null or r<0 or r>=1 then raise exception 'invalid rates'; end if;
 foreach k in array array['NORMAL','RARE','HIGH RARE','SUPER RARE','pickup','other_ur'] loop
  acc:=acc+(rates->>k)::int; if r*10000<acc then return k; end if;
 end loop; raise exception 'invalid rates';
end $fn$;$ddl$;
execute $ddl$create or replace function public.special_summon_draw(p_banner text,p_count int) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $fn$
declare u uuid:=auth.uid(); b public.special_banners; t int; m int; o int; i int; bucket text; g text; cid text;
 d jsonb; owned jsonb; e jsonb; out jsonb:='[]'::jsonb; forced boolean; why text; pw int; ow int;
begin
 if u is null then raise exception 'login required'; end if;
 if p_count is null or p_count not in (1,10) then raise exception 'invalid count'; end if;
 -- Same gem lock as shop grants; wallet serializes single/ten-pull and every banner for this user.
 perform pg_advisory_xact_lock(hashtext('gem:'||u::text));
 select * into b from public.special_banners where id=p_banner for share;
 if b.id is null or not b.active or now()<b.starts_at or (b.ends_at is not null and now()>=b.ends_at) then
  return jsonb_build_object('ok',false,'reason','closed'); end if;
 perform public._special_grade(0,b.rates); -- fail closed invalid config, including pity-only pulls
 pw:=(b.rates->>'pickup')::int; ow:=(b.rates->>'other_ur')::int;
 if not exists(select 1 from public.story_card_pool where id=b.pickup_id and grade='ULTRA RARE') then raise exception 'invalid pickup'; end if;
 insert into public.special_wallet(user_id) values(u) on conflict do nothing;
 select tickets into t from public.special_wallet where user_id=u for update;
 if t<p_count then return jsonb_build_object('ok',false,'reason','special_tickets','tickets',t); end if;
 insert into public.special_pity(user_id,banner_id) values(u,b.id) on conflict do nothing;
 select misses,off_urs into m,o from public.special_pity where user_id=u and banner_id=b.id for update;
 d:=public._story_lock(u); owned:=public._story_owned(d);
 for i in 1..p_count loop
  -- UR 천장: UR 없이 pity_limit-1 회 → 이번은 UR 확정. 어떤 UR인지는 평소 비율(pickup:other_ur).
  why:=null; forced:=m>=b.pity_limit-1;
  bucket:=public._special_grade(random(),b.rates);
  if forced and bucket not in ('pickup','other_ur') then
   why:='ur_pity'; bucket:=case when pw+ow=0 or random()*(pw+ow)<pw then 'pickup' else 'other_ur' end;
  elsif forced then why:='ur_pity'; end if;
  -- 픽업 확정: 픽업 아닌 UR pickup_after 번 뒤 다음 UR은 픽업
  if bucket='other_ur' and o>=b.pickup_after then bucket:='pickup'; why:='pickup'; end if;
  cid:=null;
  if bucket='pickup' then cid:=b.pickup_id; g:='ULTRA RARE';
  elsif bucket='other_ur' then
   g:='ULTRA RARE';
   select p.id into cid from public.story_card_pool p join public.story_premium_ur w on w.id=p.id
    where p.grade=g and p.id<>b.pickup_id order by random() limit 1;
  else
   g:=bucket; select p.id into cid from public.story_card_pool p where p.grade=g and coalesce(p.gacha,true) order by random() limit 1;
  end if;
  if cid is null then raise exception 'empty pool for %',bucket; end if;
  if g='ULTRA RARE' then m:=0; if cid=b.pickup_id then o:=0; else o:=o+1; end if; else m:=m+1; end if;
  e:=public._story_new_card(cid); owned:=owned||jsonb_build_array(e);
  out:=out||jsonb_build_array(jsonb_build_object('card_id',cid,'uid',e->>'uid','grade',g,'guaranteed',why is not null,'guarantee',why));
  insert into public.special_summon_log(user_id,banner_id,card_id,grade,guaranteed,guarantee) values(u,b.id,cid,g,why is not null,why);
  insert into public.story_gacha_log(user_id,card_id,grade,kind) values(u,cid,g,'special');
 end loop;
 perform public._story_save(u,jsonb_set(d,'{owned}',owned));
 update public.special_wallet set tickets=t-p_count where user_id=u;
 update public.special_pity set misses=m,off_urs=o where user_id=u and banner_id=b.id;
 return jsonb_build_object('ok',true,'cards',out,'tickets',t-p_count,'misses',m,'off_urs',o,'banner',public._special_banner_json(b));
end $fn$;$ddl$;
if to_regclass('public.shop_products') is not null and to_regprocedure('public._shop_apply(uuid,jsonb,text,text)') is not null then
execute $ddl$create or replace function public._shop_apply(p_uid uuid, p_grant jsonb, p_reason text, p_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g jsonb := coalesce(p_grant, '{}'::jsonb);
 n_paid int := coalesce((g->>'gem_paid')::int, 0);
 n_free int := coalesce((g->>'gem_free')::int, 0);
 n_special int := coalesce((g->>'special_tickets')::int, 0);
 n_tickets int := coalesce((g->>'tickets')::int, 0);
 n_stamina int := coalesce((g->>'stamina')::int, 0);
 n_gold int := coalesce((g->>'gold')::int, 0);
 n_blood int := coalesce((g->>'blood')::int, 0);
 n_shard int := coalesce((g->>'shard')::int, 0);
 out jsonb := '{}'::jsonb; w jsonb; t int; st int; delta jsonb := '{}'::jsonb;
begin
 if p_uid is null then raise exception 'login required'; end if;
 if n_special < 0 or n_special > 100000 then raise exception 'invalid grant'; end if;
 if n_paid < 0 or n_free < 0 or n_tickets < 0 or n_stamina < 0 or n_gold < 0 or n_blood < 0 or n_shard < 0 then raise exception 'invalid grant'; end if;
 if n_paid > 100000 or n_free > 100000 or n_tickets > 100000 or n_stamina > 100000 then raise exception 'invalid grant'; end if;
 if n_gold > 10000000 or n_blood > 10000000 or n_shard > 10000000 then raise exception 'invalid grant'; end if;
 if n_paid <> 0 or n_free <> 0 then
  w := _gem_add(p_uid, n_free, n_paid, left(p_reason, 40), p_ref, g);
  out := out || jsonb_build_object('gem', w);
 end if;
 if n_gold <> 0 then delta := delta || jsonb_build_object('gold', n_gold); end if;
 if n_blood <> 0 then delta := delta || jsonb_build_object('blood', n_blood); end if;
 if n_shard <> 0 then delta := delta || jsonb_build_object('shard', n_shard); end if;
 if delta <> '{}'::jsonb then
  w := _wallet_add(p_uid, delta, left(p_reason, 60));
  out := out || jsonb_build_object('wallet', w);
 end if;
 if n_tickets <> 0 then
  insert into story_gacha (user_id, last_draw) values (p_uid, (now() at time zone 'Asia/Seoul')::date - 1) on conflict (user_id) do nothing;
  update story_gacha set tickets = story_gacha.tickets + n_tickets, updated_at = now() where user_id = p_uid returning tickets into t;
  out := out || jsonb_build_object('tickets', t);
 end if;
 if n_special <> 0 then
  insert into public.special_wallet(user_id) values(p_uid) on conflict do nothing;
  update public.special_wallet set tickets=tickets+n_special where user_id=p_uid returning tickets into t;
  out:=out||jsonb_build_object('special_tickets',t);
 end if;
 if n_stamina <> 0 then
  st := _player_stamina_add(p_uid, n_stamina);
  out := out || jsonb_build_object('stamina', st);
 end if;
 return out;
end $$;$ddl$;
-- Only these four SKU grants change currency. Prices, quantities, limits, passes and past grants stay untouched.
update public.shop_products set reward=jsonb_build_object('special_tickets',(reward->>'tickets')::int)
 where sku in ('ticket_10','ticket_45','ticket_160','ticket_220') and reward ? 'tickets';
revoke all on function public._shop_apply(uuid,jsonb,text,text) from public,anon,authenticated;
end if;
revoke all on function public._special_banner_json(public.special_banners),public._special_grade(double precision,jsonb) from public,anon,authenticated;
revoke all on function public.special_summon_status(text),public.special_summon_draw(text,int) from public,anon;
grant execute on function public.special_summon_status(text),public.special_summon_draw(text,int) to authenticated;
end $install$;
notify pgrst, 'reload schema';
