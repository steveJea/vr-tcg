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
('1000100007','SUPER RARE',43),
('1000100009','RARE',17),
('1000100010','RARE',17),
('1000100011','HIGH RARE',26),
('1000100012','NORMAL',5),
('1000100013','NORMAL',5),
('1000100014','NORMAL',7),
('1000100016','NORMAL',6),
('1000200018','ULTRA RARE',48),
('1000200020','NORMAL',8),
('1000200021','NORMAL',14),
('1000200022','NORMAL',14),
('1000200024','SUPER RARE',45),
('1000200030','MYTHIC RARE',62),
('1000200032','NORMAL',10),
('1000200033','NORMAL',8),
('1000200034','NORMAL',14),
('1000200035','HIGH RARE',30),
('1000200036','HIGH RARE',26),
('1000200037','RARE',23),
('1000200038','HIGH RARE',30),
('1000200039','RARE',24),
('1000200040','NORMAL',6),
('1000200041','RARE',25),
('1000200042','NORMAL',13),
('1000200043','RARE',24),
('1000200046','NORMAL',7),
('1000200047','NORMAL',12),
('1000200048','NORMAL',10),
('1000200049','NORMAL',11),
('1000200050','NORMAL',10),
('1000200052','NORMAL',12),
('1000300054','NORMAL',10),
('1000300056','SUPER RARE',37),
('1000300057','NORMAL',7),
('1000300058','NORMAL',5),
('1000300059','NORMAL',5),
('1000300060','RARE',23),
('1000300061','NORMAL',8),
('1000300062','NORMAL',13),
('1000300063','NORMAL',6),
('1000300064','NORMAL',11),
('1000300065','NORMAL',11),
('1000300067','RARE',21),
('1000300070','RARE',20),
('1000300071','NORMAL',12),
('1000300072','NORMAL',6),
('1000300073','RARE',17),
('1000300074','NORMAL',12),
('1000300075','NORMAL',6),
('1000300076','NORMAL',11),
('1000300077','NORMAL',10),
('1000300078','NORMAL',12),
('1000300079','NORMAL',11),
('1000400090','HIGH RARE',28),
('1000400091','NORMAL',7),
('1000400092','SUPER RARE',45),
('1000400093','NORMAL',7),
('1000400100','RARE',23),
('1000400101','HIGH RARE',29),
('1000400102','NORMAL',9),
('1000400103','NORMAL',11),
('1000500107','HIGH RARE',27),
('1000500108','NORMAL',15),
('1000500109','SUPER RARE',37),
('1000500112','RARE',18),
('1000500113','RARE',17),
('1000600119','RARE',16),
('1000600120','HIGH RARE',32),
('1000600121','NORMAL',11),
('1000600122','HIGH RARE',29),
('1000600124','NORMAL',15),
('1000600125','SUPER RARE',37),
('1000600127','HIGH RARE',28),
('1000600130','SUPER RARE',36),
('2000600131','RARE',16),
('1000600133','NORMAL',13),
('1000700137','NORMAL',11),
('1000800169','NORMAL',9),
('1000800177','RARE',18),
('1000800178','RARE',19),
('1000800180','HIGH RARE',33),
('1000800182','NORMAL',6),
('1000800189','RARE',22),
('1000800192','NORMAL',6),
('1001000212','NORMAL',11),
('1001000213','SUPER RARE',38),
('1001000214','NORMAL',8),
('1001100218','RARE',20),
('1001100219','RARE',21),
('1001100227','RARE',24),
('1001100228','RARE',22),
('1001100236','HIGH RARE',32),
('1001100240','NORMAL',5),
('1001400245','HIGH RARE',25),
('1001400250','NORMAL',11),
('1001400252','HIGH RARE',29),
('1001400255','NORMAL',10),
('1001400256','NORMAL',8),
('1001400258','NORMAL',5),
('1001400266','RARE',22),
('1001400268','NORMAL',7),
('1001400271','HIGH RARE',35),
('1001400272','NORMAL',13),
('1001400273','RARE',18),
('1001400274','RARE',16),
('1001500280','NORMAL',13),
('1001500283','RARE',18),
('1001500285','RARE',16),
('1001500286','HIGH RARE',27),
('1001500287','NORMAL',7),
('1001500288','NORMAL',10),
('1001500289','NORMAL',6),
('1001500290','HIGH RARE',26),
('1001500293','HIGH RARE',32),
('1001500295','NORMAL',14),
('1001500296','NORMAL',6),
('1001500298','RARE',16),
('1001500299','NORMAL',6),
('1001500300','NORMAL',6),
('1001500301','NORMAL',7),
('1001500302','NORMAL',12),
('1001500303','RARE',23),
('1001500304','NORMAL',14),
('1001500305','SUPER RARE',42),
('1001500306','HIGH RARE',30),
('1001500307','HIGH RARE',32),
('1001500310','NORMAL',7),
('1001500311','SUPER RARE',35),
('1001500313','SUPER RARE',43),
('1001500315','ULTRA RARE',46),
('1001600318','RARE',22),
('1001600319','NORMAL',12),
('1001600320','RARE',15),
('1001600322','NORMAL',14),
('1001600323','RARE',20),
('1001600324','SUPER RARE',38),
('1001600325','NORMAL',5),
('1001600326','HIGH RARE',28),
('1001600327','RARE',19),
('1001600328','RARE',20),
('1001600329','RARE',21),
('1001600330','RARE',16),
('1001700331','NORMAL',13),
('1001700332','RARE',18),
('1001700333','RARE',19),
('1001700336','NORMAL',9),
('1001700337','NORMAL',14),
('1001700338','NORMAL',13),
('1001700340','NORMAL',9),
('1001800344','RARE',16),
('1001900346','RARE',16),
('1001900348','NORMAL',7),
('1001900349','NORMAL',14),
('1001900351','NORMAL',7),
('1002000355','SUPER RARE',39),
('1002100356','NORMAL',15),
('1002100357','NORMAL',6),
('1002100358','NORMAL',12),
('1002100359','NORMAL',11),
('1002100360','NORMAL',5),
('1002100361','NORMAL',13),
('1002100363','NORMAL',11),
('1002100364','HIGH RARE',25),
('1002100366','SUPER RARE',39),
('1002100367','NORMAL',7),
('1002100368','NORMAL',10),
('1002100369','NORMAL',9),
('1002100370','HIGH RARE',25),
('1002100371','ULTRA RARE',45),
('1002200372','ULTRA RARE',49),
('1002400375','SUPER RARE',38),
('1002400376','RARE',16),
('1002400377','HIGH RARE',29),
('1002400378','ULTRA RARE',51),
('1100000001','ULTRA RARE',50),
('1002400380','NORMAL',9),
('1002400381','NORMAL',9),
('1002400384','NORMAL',14),
('2000100001','ULTRA RARE',46),
('2000100002','NORMAL',13),
('2000100003','RARE',20),
('2000100004','RARE',15),
('2000100005','HIGH RARE',26),
('2000100006','RARE',21),
('2000100008','RARE',19),
('2000100015','NORMAL',8),
('2000100017','NORMAL',8),
('2000200019','HIGH RARE',25),
('2000200023','HIGH RARE',27),
('2000200025','HIGH RARE',34),
('2000200026','RARE',21),
('2000200027','HIGH RARE',29),
('2000200028','RARE',19),
('2000200029','NORMAL',8),
('2000200031','RARE',19),
('2000200044','RARE',25),
('2000200045','RARE',18),
('2000200051','SUPER RARE',43),
('2000200053','RARE',22),
('2000300055','NORMAL',9),
('2000300066','NORMAL',9),
('2000300068','NORMAL',5),
('2000300069','NORMAL',11),
('2000300080','HIGH RARE',34),
('2000300081','HIGH RARE',34),
('2000300082','SUPER RARE',40),
('2000300083','ULTRA RARE',49),
('2000400084','NORMAL',14),
('2000400085','NORMAL',9),
('2000400086','HIGH RARE',28),
('2000400087','HIGH RARE',35),
('2000400088','SUPER RARE',43),
('2000400089','HIGH RARE',35),
('2000400094','SUPER RARE',37),
('2000400095','NORMAL',12),
('2000400096','RARE',23),
('2000400097','SUPER RARE',40),
('2000400098','SUPER RARE',41),
('2000400099','RARE',17),
('2000400104','NORMAL',6),
('2000400105','NORMAL',8),
('2000400106','RARE',20),
('2000500110','RARE',17),
('2000500111','RARE',15),
('2000500114','SUPER RARE',42),
('2000600115','HIGH RARE',34),
('2000600116','HIGH RARE',30),
('2000600117','RARE',15),
('2000600118','NORMAL',7),
('2000600123','NORMAL',6),
('2000600126','RARE',25),
('2000600128','RARE',15),
('2000600129','NORMAL',13),
('2000600132','RARE',17),
('2000600134','RARE',19),
('2000600135','HIGH RARE',27),
('2000600136','NORMAL',12),
('2000700138','NORMAL',9),
('2000700139','RARE',22),
('2000700140','HIGH RARE',28),
('2000700141','NORMAL',12),
('2000700142','NORMAL',14),
('2000700143','NORMAL',10),
('2000700144','NORMAL',10),
('2000700145','NORMAL',15),
('2000700146','SUPER RARE',36),
('2000700147','NORMAL',10),
('2000700148','NORMAL',13),
('2000700149','RARE',23),
('2000700150','RARE',21),
('2000700151','RARE',20),
('2000700152','RARE',24),
('2000700153','RARE',21),
('2000700154','RARE',23),
('2000700155','NORMAL',15),
('2000700156','NORMAL',9),
('2000700157','NORMAL',13),
('2000700158','NORMAL',14),
('2000700159','NORMAL',10),
('2000700160','RARE',20),
('2000700161','RARE',21),
('2000700162','HIGH RARE',30),
('2000700163','NORMAL',10),
('2000700164','NORMAL',8),
('2000700165','ULTRA RARE',50),
('2000700166','HIGH RARE',31),
('2000800167','NORMAL',8),
('2000800168','NORMAL',8),
('2000800170','NORMAL',14),
('2000800171','NORMAL',6),
('2000800172','NORMAL',9),
('2000800173','NORMAL',7),
('2000800174','NORMAL',11),
('2000800175','NORMAL',7),
('2000800176','RARE',16),
('2000800179','SUPER RARE',42),
('2000800181','HIGH RARE',26),
('2000800183','RARE',17),
('2000800184','RARE',17),
('2000800185','HIGH RARE',27),
('2000800186','SUPER RARE',36),
('2000800187','RARE',18),
('2000800188','RARE',17),
('2000800190','RARE',23),
('2000800191','RARE',17),
('2000800193','NORMAL',5),
('2000800194','NORMAL',14),
('2000800195','NORMAL',10),
('2000800196','RARE',22),
('2000800197','ULTRA RARE',51),
('2000900198','HIGH RARE',33),
('2000900199','RARE',21),
('2000900200','NORMAL',9),
('2000900201','NORMAL',12),
('2000900202','NORMAL',12),
('2000900203','NORMAL',15),
('2000900204','RARE',24),
('2000900205','RARE',25),
('2000900206','HIGH RARE',27),
('2000900207','HIGH RARE',31),
('2000900208','NORMAL',9),
('2000900209','NORMAL',13),
('2000900210','NORMAL',15),
('2000900211','NORMAL',15),
('2000900212','RARE',25),
('2000900213','NORMAL',14),
('2000900214','HIGH RARE',32),
('2000900215','SUPER RARE',44),
('2000900216','RARE',22),
('2000900217','RARE',23),
('2000900218','RARE',21),
('2000900219','RARE',20),
('2000900220','NORMAL',7),
('2000900221','NORMAL',11),
('2000900222','NORMAL',6),
('2000900223','NORMAL',13),
('2000900224','NORMAL',14),
('2000900225','SUPER RARE',39),
('2000900226','NORMAL',13),
('2000900227','NORMAL',12),
('2000900228','NORMAL',14),
('2000900229','RARE',23),
('2000900230','NORMAL',12),
('2000900231','RARE',24),
('2000900232','RARE',23),
('2000900233','HIGH RARE',31),
('2000900234','MYTHIC RARE',58),
('2000900235','HIGH RARE',33),
('2000900236','RARE',22),
('2001100215','NORMAL',10),
('2001100216','NORMAL',10),
('2001100217','NORMAL',7),
('2001100220','NORMAL',9),
('2001100221','NORMAL',12),
('2001100222','NORMAL',11),
('2001100223','NORMAL',11),
('2001100224','NORMAL',13),
('2001100225','NORMAL',13),
('2001100226','NORMAL',12),
('2001100229','RARE',24),
('2001100230','SUPER RARE',35),
('2001100231','NORMAL',7),
('2001100232','HIGH RARE',31),
('2001100233','SUPER RARE',44),
('2001100234','NORMAL',6),
('2001100235','SUPER RARE',44),
('2001100237','HIGH RARE',30),
('2001100238','NORMAL',10),
('2001100239','NORMAL',11),
('2001100241','SUPER RARE',40),
('2001100242','SUPER RARE',39),
('2001100243','ULTRA RARE',53),
('2001200244','NORMAL',14),
('2001400246','SUPER RARE',41),
('2001400247','HIGH RARE',26),
('2001400248','ULTRA RARE',52),
('2001400249','NORMAL',7),
('2001400251','NORMAL',8),
('2001400253','RARE',18),
('2001400254','RARE',18),
('2001400257','NORMAL',5),
('2001400259','NORMAL',8),
('2001400260','NORMAL',13),
('2001400261','HIGH RARE',31),
('2001400262','NORMAL',12),
('2001400263','SUPER RARE',38),
('2001400264','HIGH RARE',29),
('2001400265','HIGH RARE',28),
('2001400267','RARE',25),
('2001400269','NORMAL',11),
('2001400270','HIGH RARE',32),
('2001400275','NORMAL',12),
('2001400276','RARE',22),
('2001400277','RARE',24),
('2001400278','NORMAL',10),
('2001400279','SUPER RARE',41),
('2001500281','NORMAL',8),
('2001500282','RARE',24),
('2001500284','NORMAL',10),
('2001500291','NORMAL',7),
('2001500292','HIGH RARE',33),
('2001500294','RARE',24),
('2001500297','NORMAL',6),
('2001500308','HIGH RARE',33),
('2001500309','NORMAL',9),
('2001500312','RARE',19),
('2001500314','SUPER RARE',42),
('2001500316','MYTHIC RARE',65),
('2001600317','RARE',21),
('2001600321','RARE',15),
('2001700334','NORMAL',10),
('2001700335','NORMAL',6),
('2001700339','NORMAL',15),
('2001700341','NORMAL',8),
('2001700342','ULTRA RARE',47),
('2001800343','NORMAL',14),
('2001800345','HIGH RARE',35),
('2001900347','SUPER RARE',43),
('2001900350','NORMAL',9),
('2002000352','HIGH RARE',33),
('2002000353','HIGH RARE',34),
('2002000354','NORMAL',12),
('2002100362','NORMAL',8),
('2002100365','NORMAL',9),
('2002300373','NORMAL',8),
('2002400374','SUPER RARE',41),
('2002400379','NORMAL',13),
('2002400382','NORMAL',14),
('2002400383','NORMAL',9),
('2000000001','ULTRA RARE',54),
('2000000002','NORMAL',15),
('2000000003','SUPER RARE',44),
('2000000004','RARE',19),
('2000000005','RARE',20),
('2000000006','HIGH RARE',31),
('2000000007','ULTRA RARE',54),
('2000000008','MYTHIC RARE',55),
('2000000009','HIGH RARE',30),
('2000000010','NORMAL',11),
('2000000011','RARE',18),
('2000000012','HIGH RARE',34),
('1000000001','RARE',19),
('1000000002','RARE',19),
('1000000003','SUPER RARE',36),
('1000000004','ULTRA RARE',55),
('1000000005','NORMAL',10),
('1000000006','NORMAL',6),
('1000000007','NORMAL',8),
('1000000008','NORMAL',13),
('1000000009','NORMAL',15),
('2000000013','SUPER RARE',44),
('2000000014','SUPER RARE',45),
('2000000015','NORMAL',14),
('2000000016','RARE',25),
('2000000017','ULTRA RARE',53),
('2000000040','HIGH RARE',35)
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
