-- ⚠ 다시 돌리지 마세요, 최신 아님 (일부): 이 파일의 _pvp_extra, _pvp_snap, pvp_rankings, pvp_report, pvp_start, pvp_status 는 뒤 파일에서 다시 정의됨. 이 파일을 다시 돌리면 예전 것으로 되돌아가요. supabase/README.md 참고
-- ===== 비동기 PvP (리그: 무제한 open / HR급 이하 hr · 모드: 1v1 / 3v3 · 주간 시즌 · 하루 10회) =====
-- 실행: Supabase SQL Editor 에서 전체 실행. 여러 번 실행해도 안전(idempotent).
-- 서버 권한: 덱 소유·등급·코스트 검사, 상대 선택, seed 발급, 하루 횟수, 레이팅 계산은 모두 SECURITY DEFINER RPC 에서.
-- 남는 신뢰 구멍: 전투 계산은 브라우저(js/pvp-core.js)에서 하고 결과(승패)를 보고함 → 서버가 seed·양쪽 스냅샷을 저장하므로
--   tools/pvp_verify.mjs 로 나중에 다시 돌려 조작을 찾을 수 있음(verified 컬럼). 실시간 차단은 아님.

-- 0) 카드 메타 (등급·코스트) — data/cards.csv 에서 생성. 카드 추가 시 이 블록만 다시 생성해 실행
create table if not exists public.pvp_card_meta (id text primary key, grade text not null, cost int not null default 0);
alter table public.pvp_card_meta enable row level security;
drop policy if exists pvp_card_meta_read on public.pvp_card_meta;
create policy pvp_card_meta_read on public.pvp_card_meta for select using (true);
insert into public.pvp_card_meta (id, grade, cost) values
('10118','SUPER RARE',43),
('10019','RARE',17),
('10018','RARE',17),
('10299','HIGH RARE',26),
('10074','NORMAL',5),
('10080','NORMAL',5),
('10445','NORMAL',7),
('10375','NORMAL',6),
('10051','ULTRA RARE',48),
('10404','NORMAL',8),
('10049','NORMAL',14),
('10048','NORMAL',14),
('10189','SUPER RARE',45),
('10060','MYTHIC RARE',62),
('10071','NORMAL',10),
('10086','NORMAL',8),
('10169','NORMAL',14),
('10137','HIGH RARE',30),
('10138','HIGH RARE',26),
('10020','RARE',23),
('10463','HIGH RARE',30),
('10228','RARE',24),
('10453','NORMAL',6),
('10293','RARE',25),
('10010','NORMAL',13),
('10380','RARE',24),
('10114','NORMAL',7),
('10401','NORMAL',12),
('10315','NORMAL',10),
('10026','NORMAL',11),
('10191','NORMAL',10),
('10469','NORMAL',12),
('10001','NORMAL',10),
('10183','SUPER RARE',37),
('10064','NORMAL',7),
('10444','NORMAL',5),
('10279','NORMAL',5),
('10225','RARE',23),
('10431','NORMAL',8),
('10332','NORMAL',13),
('10201','NORMAL',6),
('10346','NORMAL',11),
('10275','NORMAL',11),
('10124','RARE',21),
('10134','RARE',20),
('10037','NORMAL',12),
('10031','NORMAL',6),
('10180','RARE',17),
('10390','NORMAL',12),
('10027','NORMAL',6),
('10033','NORMAL',11),
('10353','NORMAL',10),
('10244','NORMAL',12),
('10245','NORMAL',11),
('10292','HIGH RARE',28),
('10076','NORMAL',7),
('10045','SUPER RARE',45),
('10409','NORMAL',7),
('10407','RARE',23),
('10036','HIGH RARE',29),
('10075','NORMAL',9),
('10173','NORMAL',11),
('10406','HIGH RARE',27),
('10328','NORMAL',15),
('10329','SUPER RARE',37),
('10098','RARE',18),
('10187','RARE',17),
('10319','RARE',16),
('10081','HIGH RARE',32),
('10252','NORMAL',11),
('10298','HIGH RARE',29),
('10125','NORMAL',15),
('10025','SUPER RARE',37),
('10035','HIGH RARE',28),
('10112','SUPER RARE',36),
('10270','RARE',16),
('10069','NORMAL',13),
('10088','NORMAL',11),
('10004','NORMAL',9),
('10420','RARE',18),
('10408','RARE',19),
('10205','HIGH RARE',33),
('10139','NORMAL',6),
('10347','RARE',22),
('10023','NORMAL',6),
('10448','NORMAL',11),
('10067','SUPER RARE',38),
('10005','NORMAL',8),
('10276','RARE',20),
('10259','RARE',21),
('10386','RARE',24),
('10105','RARE',22),
('10077','HIGH RARE',32),
('10212','NORMAL',5),
('10065','HIGH RARE',25),
('10008','NORMAL',11),
('10425','HIGH RARE',29),
('10107','NORMAL',10),
('10032','NORMAL',8),
('10142','NORMAL',5),
('10089','RARE',22),
('10094','NORMAL',7),
('10350','HIGH RARE',35),
('10366','NORMAL',13),
('10016','RARE',18),
('10385','RARE',16),
('10474','NORMAL',13),
('10287','RARE',18),
('10182','RARE',16),
('10136','HIGH RARE',27),
('10209','NORMAL',7),
('10170','NORMAL',10),
('10128','NORMAL',6),
('10433','HIGH RARE',26),
('10374','HIGH RARE',32),
('10218','NORMAL',14),
('10441','NORMAL',6),
('10349','RARE',16),
('10314','NORMAL',6),
('10337','NORMAL',6),
('10038','NORMAL',7),
('10365','NORMAL',12),
('10278','RARE',23),
('10251','NORMAL',14),
('10109','SUPER RARE',42),
('10017','HIGH RARE',30),
('10015','HIGH RARE',32),
('10028','NORMAL',7),
('10181','SUPER RARE',35),
('10333','SUPER RARE',43),
('10054','ULTRA RARE',46),
('10046','RARE',22),
('10066','NORMAL',12),
('10195','RARE',15),
('10283','NORMAL',14),
('10284','RARE',20),
('10321','SUPER RARE',38),
('10320','NORMAL',5),
('10371','HIGH RARE',28),
('10345','RARE',19),
('10021','RARE',20),
('10424','RARE',21),
('10398','RARE',16),
('10318','NORMAL',13),
('10458','RARE',18),
('10464','RARE',19),
('10233','NORMAL',9),
('10034','NORMAL',14),
('10171','NORMAL',13),
('10119','NORMAL',9),
('10226','RARE',16),
('10307','RARE',16),
('10402','NORMAL',7),
('10009','NORMAL',14),
('10055','NORMAL',7),
('10013','SUPER RARE',39),
('10313','NORMAL',15),
('10106','NORMAL',6),
('10316','NORMAL',12),
('10416','NORMAL',11),
('10057','NORMAL',5),
('10220','NORMAL',13),
('10340','NORMAL',11),
('10309','HIGH RARE',25),
('10070','SUPER RARE',39),
('10113','NORMAL',7),
('10364','NORMAL',10),
('10410','NORMAL',9),
('10419','HIGH RARE',25),
('10053','ULTRA RARE',45),
('10176','ULTRA RARE',49),
('10200','SUPER RARE',38),
('10234','RARE',16),
('10123','HIGH RARE',29),
('10304','ULTRA RARE',51),
('10435','ULTRA RARE',50),
('10434','NORMAL',9),
('10430','NORMAL',9),
('10379','NORMAL',14),
('10325','ULTRA RARE',46),
('10260','NORMAL',13),
('10300','RARE',20),
('10462','RARE',15),
('10072','HIGH RARE',26),
('10256','RARE',21),
('10115','RARE',19),
('10348','NORMAL',8),
('10339','NORMAL',8),
('10394','HIGH RARE',25),
('10047','HIGH RARE',27),
('10188','HIGH RARE',34),
('10132','RARE',21),
('10087','HIGH RARE',29),
('10202','RARE',19),
('10184','NORMAL',8),
('10103','RARE',19),
('10265','RARE',25),
('10266','RARE',18),
('10465','SUPER RARE',43),
('10466','RARE',22),
('10002','NORMAL',9),
('10289','NORMAL',9),
('10083','NORMAL',5),
('10079','NORMAL',11),
('10338','HIGH RARE',34),
('10336','HIGH RARE',34),
('10418','SUPER RARE',40),
('10323','ULTRA RARE',49),
('10403','NORMAL',14),
('10185','NORMAL',9),
('10308','HIGH RARE',28),
('10413','HIGH RARE',35),
('10415','SUPER RARE',43),
('10414','HIGH RARE',35),
('10186','SUPER RARE',37),
('10295','NORMAL',12),
('10297','RARE',23),
('10317','SUPER RARE',40),
('10108','SUPER RARE',41),
('10417','RARE',17),
('10172','NORMAL',6),
('10262','NORMAL',8),
('10261','RARE',20),
('10290','RARE',17),
('10384','RARE',15),
('10383','SUPER RARE',42),
('10110','HIGH RARE',34),
('10442','HIGH RARE',30),
('10129','RARE',15),
('10014','NORMAL',7),
('10235','NORMAL',6),
('10111','RARE',25),
('10357','RARE',15),
('10360','NORMAL',13),
('10306','RARE',17),
('10285','RARE',19),
('10343','HIGH RARE',27),
('10271','NORMAL',12),
('10003','NORMAL',9),
('10095','RARE',22),
('10096','HIGH RARE',28),
('10342','NORMAL',12),
('10327','NORMAL',14),
('10286','NORMAL',10),
('10273','NORMAL',10),
('10253','NORMAL',15),
('10061','SUPER RARE',36),
('10460','NORMAL',10),
('10459','NORMAL',13),
('10461','RARE',23),
('10296','RARE',21),
('10246','RARE',20),
('10204','RARE',24),
('10447','RARE',21),
('10429','RARE',23),
('10211','NORMAL',15),
('10193','NORMAL',9),
('10120','NORMAL',13),
('10101','NORMAL',14),
('10099','NORMAL',10),
('10241','RARE',20),
('10044','RARE',21),
('10043','HIGH RARE',30),
('10376','NORMAL',10),
('10377','NORMAL',8),
('10322','ULTRA RARE',50),
('10239','HIGH RARE',31),
('10039','NORMAL',8),
('10310','NORMAL',8),
('10247','NORMAL',14),
('10248','NORMAL',6),
('10221','NORMAL',9),
('10011','NORMAL',7),
('10140','NORMAL',11),
('10388','NORMAL',7),
('10121','RARE',16),
('10236','SUPER RARE',42),
('10102','HIGH RARE',26),
('10092','RARE',17),
('10194','RARE',17),
('10361','HIGH RARE',27),
('10354','SUPER RARE',36),
('10254','RARE',18),
('10222','RARE',17),
('10470','RARE',23),
('10059','RARE',17),
('10428','NORMAL',5),
('10471','NORMAL',14),
('10450','NORMAL',10),
('10432','RARE',22),
('10359','ULTRA RARE',51),
('10362','HIGH RARE',33),
('10454','RARE',21),
('10363','NORMAL',9),
('10436','NORMAL',12),
('10412','NORMAL',12),
('10040','NORMAL',15),
('10042','RARE',24),
('10237','RARE',25),
('10207','HIGH RARE',27),
('10208','HIGH RARE',31),
('10303','NORMAL',9),
('10468','NORMAL',13),
('10467','NORMAL',15),
('10294','NORMAL',15),
('10258','RARE',25),
('10056','NORMAL',14),
('10041','HIGH RARE',32),
('10255','SUPER RARE',44),
('10141','RARE',22),
('10133','RARE',23),
('10091','RARE',21),
('10090','RARE',20),
('10344','NORMAL',7),
('10330','NORMAL',11),
('10263','NORMAL',6),
('10249','NORMAL',13),
('10063','NORMAL',14),
('10052','SUPER RARE',39),
('10190','NORMAL',13),
('10174','NORMAL',12),
('10122','NORMAL',14),
('10029','RARE',23),
('10232','NORMAL',12),
('10104','RARE',24),
('10378','RARE',23),
('10126','HIGH RARE',31),
('10062','MYTHIC RARE',58),
('10203','HIGH RARE',33),
('10097','RARE',22),
('10280','NORMAL',10),
('10352','NORMAL',10),
('10277','NORMAL',7),
('10100','NORMAL',9),
('10451','NORMAL',12),
('10389','NORMAL',11),
('10264','NORMAL',11),
('10438','NORMAL',13),
('10177','NORMAL',13),
('10178','NORMAL',12),
('10372','RARE',24),
('10373','SUPER RARE',35),
('10130','NORMAL',7),
('10131','HIGH RARE',31),
('10341','SUPER RARE',44),
('10272','NORMAL',6),
('10117','SUPER RARE',44),
('10078','HIGH RARE',30),
('10084','NORMAL',10),
('10085','NORMAL',11),
('10217','SUPER RARE',40),
('10216','SUPER RARE',39),
('10324','ULTRA RARE',53),
('10006','NORMAL',14),
('10068','SUPER RARE',41),
('10400','HIGH RARE',26),
('10331','ULTRA RARE',52),
('10250','NORMAL',7),
('10022','NORMAL',8),
('10437','RARE',18),
('10426','RARE',18),
('10381','NORMAL',5),
('10179','NORMAL',8),
('10215','NORMAL',13),
('10214','HIGH RARE',31),
('10223','NORMAL',12),
('10269','SUPER RARE',38),
('10268','HIGH RARE',29),
('10473','HIGH RARE',28),
('10135','RARE',25),
('10206','NORMAL',11),
('10240','HIGH RARE',32),
('10238','NORMAL',12),
('10230','RARE',22),
('10227','RARE',24),
('10387','NORMAL',10),
('10281','SUPER RARE',41),
('10472','NORMAL',8),
('10455','RARE',24),
('10423','NORMAL',10),
('10456','NORMAL',7),
('10457','HIGH RARE',33),
('10224','RARE',24),
('10382','NORMAL',6),
('10393','HIGH RARE',33),
('10030','NORMAL',9),
('10391','RARE',19),
('10392','SUPER RARE',42),
('10311','MYTHIC RARE',65),
('10397','RARE',21),
('10242','RARE',15),
('10356','NORMAL',10),
('10274','NORMAL',6),
('10192','NORMAL',15),
('10093','NORMAL',8),
('10312','ULTRA RARE',47),
('10243','NORMAL',14),
('10231','HIGH RARE',35),
('10399','SUPER RARE',43),
('10050','NORMAL',9),
('10073','HIGH RARE',33),
('10229','HIGH RARE',34),
('10012','NORMAL',12),
('10219','NORMAL',8),
('10305','NORMAL',9),
('10443','NORMAL',8),
('10024','SUPER RARE',41),
('10446','NORMAL',13),
('10427','NORMAL',14),
('10411','NORMAL',9),
('10058','ULTRA RARE',54),
('10395','NORMAL',15),
('10213','SUPER RARE',44),
('10175','RARE',19),
('10007','RARE',20),
('10257','HIGH RARE',31),
('10291','ULTRA RARE',54),
('10326','MYTHIC RARE',55),
('10288','HIGH RARE',30),
('10282','NORMAL',11),
('10405','RARE',18),
('10452','HIGH RARE',34),
('10370','RARE',19),
('10368','RARE',19),
('10369','SUPER RARE',36),
('10358','ULTRA RARE',55),
('10351','NORMAL',10),
('10449','NORMAL',6),
('10422','NORMAL',8),
('10421','NORMAL',13),
('10396','NORMAL',15),
('10127','SUPER RARE',44),
('10439','SUPER RARE',45),
('10355','NORMAL',14),
('10367','RARE',25),
('10440','ULTRA RARE',53),
('10267','HIGH RARE',35)
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;

-- 1) 테이블 (모두 본인 행만 읽기 · 쓰기는 RPC 만)
create table if not exists public.pvp_decks (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null check (league in ('open','hr')),
  mode text not null check (mode in ('1v1','3v3')),
  slot smallint not null check (slot between 0 and 2),
  uids jsonb not null default '[]'::jsonb,
  snap jsonb not null default '[]'::jsonb,      -- 등록 시점 방어 덱 스냅샷 (서버가 story_progress 에서 복사)
  cost int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, league, mode, slot));
create table if not exists public.pvp_ratings (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null,
  rating int not null default 1000, wins int not null default 0, losses int not null default 0,
  def_wins int not null default 0, def_losses int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, league, mode, season));
create table if not exists public.pvp_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null, day date not null,
  opp_user uuid, opp_name text, seed bigint not null,
  my_snap jsonb not null, opp_snap jsonb not null,
  my_rating int not null, opp_rating int not null, dw int not null, dl int not null,
  created_at timestamptz not null default now(),
  reported_at timestamptz, wins smallint, losses smallint, win boolean not null default false,
  verified boolean);                                -- tools/pvp_verify.mjs 재검증 결과
create index if not exists pvp_attempts_user_day on public.pvp_attempts (user_id, day);
create table if not exists public.pvp_reward_table (
  league text not null, mode text not null, rank_from int not null, rank_to int not null, reward jsonb not null,
  primary key (league, mode, rank_from));
create table if not exists public.pvp_reward_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  league text not null, mode text not null, season date not null, rank int not null, reward jsonb not null,
  claimed_at timestamptz not null default now(), primary key (user_id, league, mode, season));
alter table public.pvp_decks enable row level security;
alter table public.pvp_ratings enable row level security;
alter table public.pvp_attempts enable row level security;
alter table public.pvp_reward_table enable row level security;
alter table public.pvp_reward_claims enable row level security;
drop policy if exists pvp_decks_own on public.pvp_decks;           create policy pvp_decks_own on public.pvp_decks for select using (auth.uid() = user_id);
drop policy if exists pvp_ratings_own on public.pvp_ratings;       create policy pvp_ratings_own on public.pvp_ratings for select using (auth.uid() = user_id);
drop policy if exists pvp_attempts_own on public.pvp_attempts;     create policy pvp_attempts_own on public.pvp_attempts for select using (auth.uid() = user_id);
drop policy if exists pvp_reward_read on public.pvp_reward_table;  create policy pvp_reward_read on public.pvp_reward_table for select using (true);
drop policy if exists pvp_claims_own on public.pvp_reward_claims;  create policy pvp_claims_own on public.pvp_reward_claims for select using (auth.uid() = user_id);
revoke insert, update, delete on public.pvp_decks, public.pvp_ratings, public.pvp_attempts, public.pvp_reward_table, public.pvp_reward_claims, public.pvp_card_meta from anon, authenticated;

-- 시즌 보상표 (양 리그·모드 동일): gold / blood / shard(이상한 조각) / soul = player_wallet, tickets = 소환권(story_gacha.tickets)
insert into public.pvp_reward_table (league, mode, rank_from, rank_to, reward)
select l, m, f, t, r::jsonb from (values ('open'), ('hr')) a(l), (values ('1v1'), ('3v3')) b(m),
  (values (1, 1, '{"gold":3000,"soul":50,"tickets":50}'), (2, 3, '{"gold":2000,"soul":30,"tickets":30}'), (4, 10, '{"gold":1200,"soul":15,"tickets":20}'),
          (11, 50, '{"gold":600,"shard":20,"tickets":10}'), (51, 100, '{"gold":300,"shard":10,"tickets":10}'), (101, 1000000, '{"gold":100,"tickets":5}')) c(f, t, r)
on conflict (league, mode, rank_from) do update set rank_to = excluded.rank_to, reward = excluded.reward;

-- 2) 공통
create or replace function public._pvp_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;
-- 주간 시즌 = 한국 시간 월요일 00:00 시작 (ISO 주)
create or replace function public._pvp_season() returns date language sql stable as $$ select date_trunc('week', now() at time zone 'Asia/Seoul')::date $$;
create or replace function public._pvp_ok(p_league text, p_mode text) returns int language plpgsql immutable as $$
begin
  if p_league not in ('open','hr') then raise exception 'bad league'; end if;
  if p_mode = '1v1' then return 1; elsif p_mode = '3v3' then return 3; end if;
  raise exception 'bad mode';
end $$;
-- 덱 스냅샷: 내가 가진 카드(uid)만, 1~5장, 같은 카드 id 중복 불가, HR 리그는 HR 이하 + 코스트 합 150 이하
create or replace function public._pvp_snap(p_user uuid, p_uids jsonb, p_league text) returns jsonb language plpgsql stable set search_path = public as $$
declare owned jsonb; out jsonb := '[]'::jsonb; u text; o jsonb; m pvp_card_meta; cost int := 0; ids text[] := '{}';
begin
  if jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) not between 1 and 5 then raise exception 'deck size'; end if;
  select case when jsonb_typeof(data->'owned') = 'array' then data->'owned' else '[]'::jsonb end into owned from story_progress where user_id = p_user;
  for u in select jsonb_array_elements_text(p_uids) loop
    if u like 'guest:%' then raise exception 'card not owned'; end if;
    select x into o from jsonb_array_elements(coalesce(owned, '[]'::jsonb)) x where x->>'uid' = u limit 1;
    if o is null then raise exception 'card not owned'; end if;
    select * into m from pvp_card_meta where id = o->>'id';
    if m.id is null then raise exception 'unknown card'; end if;
    if m.id = any(ids) then raise exception 'duplicate card'; end if;
    if p_league = 'hr' and m.grade not in ('NORMAL','RARE','HIGH RARE') then raise exception 'grade not allowed'; end if;
    ids := ids || m.id; cost := cost + m.cost;
    out := out || jsonb_build_object('uid', u, 'id', o->>'id', 'level', coalesce((o->>'level')::int, 1), 'ex', coalesce((o->>'ex')::int, 0),
      'exb', coalesce((o->>'exb')::numeric, 0), 'boost', coalesce(o->'boost', '{}'::jsonb), 'skillLv', coalesce(o->'skillLv', '{}'::jsonb));
  end loop;
  if p_league = 'hr' and cost > 150 then raise exception 'cost over 150'; end if;
  return jsonb_build_object('cards', out, 'cost', cost);
end $$;
create or replace function public._pvp_rating(p_user uuid, p_league text, p_mode text) returns pvp_ratings language plpgsql set search_path = public as $$
declare r pvp_ratings;
begin
  insert into pvp_ratings (user_id, league, mode, season) values (p_user, p_league, p_mode, _pvp_season()) on conflict do nothing;
  select * into r from pvp_ratings where user_id = p_user and league = p_league and mode = p_mode and season = _pvp_season() for update;
  return r;
end $$;
revoke all on function public._pvp_snap(uuid, jsonb, text), public._pvp_rating(uuid, text, text) from public, anon, authenticated;

-- 3) 덱 등록 (PvP 전용 · 마이 덱과 별개). p_uids = [] 이면 그 슬롯 삭제
create or replace function public.pvp_set_deck(p_league text, p_mode text, p_slot int, p_uids jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); s jsonb; other text[];
begin
  if uid is null then raise exception 'login required'; end if;
  if p_slot is null or p_slot < 0 or p_slot >= n then raise exception 'bad slot'; end if;
  if p_uids is null or jsonb_typeof(p_uids) <> 'array' or jsonb_array_length(p_uids) = 0 then
    delete from pvp_decks where user_id = uid and league = p_league and mode = p_mode and slot = p_slot;
    return jsonb_build_object('ok', true, 'slot', p_slot, 'cards', '[]'::jsonb);
  end if;
  s := _pvp_snap(uid, p_uids, p_league);
  -- 3v3: 같은 카드는 세 덱 중 한 곳에만
  select coalesce(array_agg(x->>'id'), '{}') into other from pvp_decks d, jsonb_array_elements(d.snap) x
    where d.user_id = uid and d.league = p_league and d.mode = p_mode and d.slot <> p_slot;
  if exists (select 1 from jsonb_array_elements(s->'cards') x where x->>'id' = any(other)) then raise exception 'card used in another deck'; end if;
  insert into pvp_decks (user_id, league, mode, slot, uids, snap, cost, updated_at)
  values (uid, p_league, p_mode, p_slot, p_uids, s->'cards', (s->>'cost')::int, now())
  on conflict (user_id, league, mode, slot) do update set uids = excluded.uids, snap = excluded.snap, cost = excluded.cost, updated_at = now();
  return jsonb_build_object('ok', true, 'slot', p_slot, 'cards', s->'cards', 'cost', (s->>'cost')::int);
end $$;

-- 4) 상태: 오늘 남은 횟수(리그·모드별 10회) · 내 레이팅 · 내 덱 · 시즌
create or replace function public.pvp_status(p_league text, p_mode text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int := _pvp_ok(p_league, p_mode); used int; r pvp_ratings; decks jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  select count(*) into used from pvp_attempts where user_id = uid and league = p_league and mode = p_mode and day = _pvp_day();
  r := _pvp_rating(uid, p_league, p_mode);
  select coalesce(jsonb_agg(jsonb_build_object('slot', slot, 'uids', uids, 'cost', cost) order by slot), '[]'::jsonb) into decks
    from pvp_decks where user_id = uid and league = p_league and mode = p_mode;
  return jsonb_build_object('left', greatest(0, 10 - used), 'max', 10, 'rating', r.rating, 'wins', r.wins, 'losses', r.losses,
    'def_wins', r.def_wins, 'def_losses', r.def_losses, 'decks', decks, 'need', n,
    'season', _pvp_season(), 'season_end', ((_pvp_season() + 7)::timestamp at time zone 'Asia/Seoul'));
end $$;

-- 5) 매칭 시작: 횟수 차감 · 내 덱 재검사(지금 가진 카드로) · 비슷한 레이팅 상대(방어 덱 스냅샷) · seed 발급
--    패배 처리를 먼저 반영(미보고 = 패배). 승리 보고 시 되돌리고 승리 반영
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

-- 6) 결과 보고: 시작 후 1시간 안, 한 번만. 승리면 선반영한 패배를 되돌리고 승리 반영
create or replace function public.pvp_report(p_id bigint, p_wins int, p_losses int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a pvp_attempts; n int; need int; v_win boolean; r int;
begin
  if uid is null then raise exception 'login required'; end if;
  select * into a from pvp_attempts where id = p_id and user_id = uid for update;
  if a.id is null then raise exception 'not found'; end if;
  if a.reported_at is not null then raise exception 'already reported'; end if;
  if now() - a.created_at > interval '1 hour' then raise exception 'expired'; end if;
  n := _pvp_ok(a.league, a.mode); need := case when n = 3 then 2 else 1 end;
  if p_wins is null or p_losses is null or p_wins < 0 or p_losses < 0 or p_wins > need or p_losses > need
     or not (p_wins = need or p_losses = need) or (p_wins = need and p_losses = need) then raise exception 'bad result'; end if;
  v_win := p_wins = need;
  update pvp_attempts set reported_at = now(), wins = p_wins, losses = p_losses, win = v_win where id = p_id;
  if v_win then
    update pvp_ratings set rating = rating + a.dl + a.dw, wins = wins + 1, losses = losses - 1, updated_at = now()
      where user_id = uid and league = a.league and mode = a.mode and season = a.season;
    if a.opp_user is not null then
      update pvp_ratings set rating = rating - a.dl / 2 - a.dw / 2, def_wins = def_wins - 1, def_losses = def_losses + 1, updated_at = now()
        where user_id = a.opp_user and league = a.league and mode = a.mode and season = a.season;
    end if;
  end if;
  select rating into r from pvp_ratings where user_id = uid and league = a.league and mode = a.mode and season = a.season;
  return jsonb_build_object('ok', true, 'win', v_win, 'rating', r, 'delta', case when v_win then a.dw else -a.dl end);
end $$;

-- 7) 랭킹 (리그·모드·시즌별 상위 100 + 내 순위). 1판 이상 한 유저만
create or replace function public.pvp_rankings(p_league text, p_mode text, p_season date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := coalesce(p_season, _pvp_season()); top jsonb; mine jsonb;
begin
  perform _pvp_ok(p_league, p_mode);
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select coalesce(jsonb_agg(jsonb_build_object('rank', rk, 'name', coalesce(p.nickname, '플레이어'), 'rating', rating, 'wins', wins, 'losses', losses, 'me', t.user_id = uid) order by rk), '[]'::jsonb)
    into top from (select * from t order by rk limit 100) t left join profiles p on p.id = t.user_id;
  with t as (select r.user_id, r.rating, r.wins, r.losses, rank() over (order by r.rating desc, r.wins desc) rk
             from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0)
  select jsonb_build_object('rank', rk, 'rating', rating, 'wins', wins, 'losses', losses) into mine from t where t.user_id = uid;
  return jsonb_build_object('season', s, 'top', top, 'me', mine);
end $$;

-- 8) 지난 시즌 보상 받기 (시즌 끝난 뒤 1회). 보상표 = pvp_reward_table (임시안)
create or replace function public.pvp_claim_reward(p_league text, p_mode text, p_season date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rk int; rw jsonb;
begin
  if uid is null then raise exception 'login required'; end if;
  perform _pvp_ok(p_league, p_mode);
  if p_season is null or p_season >= _pvp_season() then raise exception 'season not ended'; end if;
  if exists (select 1 from pvp_reward_claims where user_id = uid and league = p_league and mode = p_mode and season = p_season) then raise exception 'already claimed'; end if;
  select t.rk into rk from (select user_id, rank() over (order by rating desc, wins desc) rk from pvp_ratings
    where league = p_league and mode = p_mode and season = p_season and wins + losses > 0) t where t.user_id = uid;
  if rk is null then raise exception 'not ranked'; end if;
  select reward into rw from pvp_reward_table where league = p_league and mode = p_mode and rk between rank_from and rank_to order by rank_from limit 1;
  if rw is null then raise exception 'no reward'; end if;
  insert into pvp_reward_claims (user_id, league, mode, season, rank, reward) values (uid, p_league, p_mode, p_season, rk, rw);
  if rw - 'tickets' <> '{}'::jsonb then perform _wallet_add(uid, rw - 'tickets', 'pvp_season'); end if;
  if coalesce((rw->>'tickets')::int, 0) > 0 then
    insert into story_gacha (user_id, last_draw) values (uid, _pvp_day() - 1) on conflict (user_id) do nothing;
    update story_gacha set tickets = tickets + (rw->>'tickets')::int, updated_at = now() where user_id = uid;
  end if;
  return jsonb_build_object('ok', true, 'rank', rk, 'reward', rw);
end $$;

revoke all on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_status(text, text), public.pvp_start(text, text),
  public.pvp_report(bigint, int, int), public.pvp_claim_reward(text, text, date) from public, anon;
grant execute on function public.pvp_set_deck(text, text, int, jsonb), public.pvp_status(text, text), public.pvp_start(text, text),
  public.pvp_report(bigint, int, int), public.pvp_claim_reward(text, text, date) to authenticated;
revoke all on function public.pvp_rankings(text, text, date) from public;
grant execute on function public.pvp_rankings(text, text, date) to anon, authenticated;
