-- 스테이징 전용. 시련의 탑 소탕 재계산을 시험할 계정 하나를 맞추는 스크립트.
-- 앱 로직을 바꾸지 않습니다. 프로덕션에서 실행하면 아래 가드가 즉시 중단합니다.
-- 임시 테이블과 begin/commit 을 쓰지 않습니다. Supabase SQL Editor 는 문장마다 따로 실행해도 됩니다.
--
-- 사용법 (Supabase 스테이징 SQL Editor 에 이 파일 전체를 붙여 넣고 Run. 선택 없이 통째로)
-- 1. 아래 DO 블록 맨 위의 v_nick, v_action 두 줄만 고칩니다. 지금 닉네임은 '드라고니아', action 은 'apply' 입니다.
--    닉네임은 한 글자도 틀리면 안 됩니다. 0명이거나 2명 이상이면 아무것도 바꾸지 않고 멈춥니다.
-- 2. 되돌릴 때는 v_action 만 'revert' 로 바꾸고 같은 파일을 다시 실행합니다.
-- 3. 그 계정의 게임 탭을 SQL 실행 전에 모두 닫습니다. 켜 둔 탭이 예전 보유 목록을 다시 저장할 수 있습니다.
-- 4. Messages 의 NOTICE 와 마지막 결과 표에서 승리 층 / 패배 층을 확인한 뒤, 게임을 새로 열고 시련의 탑에서 소탕을 한 번 누릅니다.
--
-- apply 가 하는 일 (그 계정만)
-- * 소탕 출전은 story_progress.data.owned 한 곳만 봅니다 (서버 _pvp_snap, 화면 deckInstances).
--   그 목록이 없거나 비어 있으면, 장비·증표·뽑기 기록·대전 스냅샷에 있는 카드로 1장짜리 소탕 덱을 만듭니다.
--   그런 카드도 없으면 가장 짧은 시험 카드 1장을 넣습니다. revert 하면 목록이 없던 상태는 행 삭제까지 그대로 돌아갑니다.
-- * 목록이 있으면 그 인재 중 1장·시드 7·장비/증표/강화 없음으로 "이 층은 이기고 바로 다음 층은 지는" 카드를 고릅니다.
--   가장 낮은 승리 층을 고르므로 시험이 짧습니다. 같은 카드의 사본은 남기고, 다른 인재는 백업에만 보관합니다.
-- * 그 카드의 레벨을 표의 값으로 맞추고, 강화·EX·스킬 레벨을 비웁니다. 장착 장비와 증표 강화만 잠시 벗깁니다.
-- * 리더 스킬을 끕니다. 시험 중에 리더를 바꾸면 패배 층도 이길 수 있습니다.
-- * 시련의 탑(normal) 최고 층을 승리 층 직전으로 맞춥니다. 이미 클리어한 계정도 그 층부터 다시 소탕할 수 있습니다.
-- * 오늘 시련의 탑 도전 횟수만 0으로 맞춥니다. 골드·젬·소환권·피·조각·혼은 바꾸지 않습니다.
-- * 첫 클리어 보상은 이미 받은 것으로 표시합니다. 이번 소탕은 재화를 주지 않습니다.
-- * 그 두 층의 소탕 시드를 7로 고정합니다. 예상 승패는 이 시드와 1장 덱으로 계산했습니다.
--
-- 성공 (재계산 스위치 battle_replay_policy_v6.enabled 가 켜져 있을 때)
-- * 버튼이 "3~9층"처럼 보여도, 패배 층에서 멈춥니다. 한 번만 누르세요.
-- * 승리 층: 최고 기록이 그 층으로 한 번 오릅니다. 같은 전투를 서버가 다시 받아도 같은 정산이고, 재화는 늘지 않습니다.
-- * 패배 층: 최고 기록과 재화가 더 오르지 않습니다.
-- * 스위치가 꺼져 있으면 예전 판정이라 패배 층도 클리어될 수 있습니다. 그때는 재계산 시험이 아닙니다.
--
-- revert 는 백업 테이블 public.staging_sweep_fixture_backup 의 그 계정 스냅샷만 되돌립니다.
-- 시험 후에 뽑은 인재, 시험 중에 오른 탑 기록, 시험 중에 새로 생긴 그 두 층의 클리어 영수증은 백업에 없으므로 되돌려지지 않습니다.
-- 재화는 이 스크립트가 준 적이 없습니다. 백업 줄은 revert 가 끝나면 지웁니다. 그 다음 apply 는 새 백업을 만듭니다.

do $sweep_fixture$
declare
  -- ===== 여기만 고치세요. 이 두 줄 외에는 손대지 마세요. =====
  v_nick text := '드라고니아'; -- 시험할 닉네임 하나
  v_action text := 'apply'; -- apply 또는 revert
  -- ============================================================
  v_fix jsonb;
  v_have text[] := '{}';
  v_engine text := 'acc69f350201a78835f8fbb62891698bde09ec3b1995ce72050d4703aa9ecc78';
  v_uid uuid;
  v_n int;
  v_i int := 0;
  v_snap jsonb;
  v_story jsonb;
  v_owned jsonb;
  v_reused boolean := false;
  v_card_id text;
  v_name text;
  v_level int;
  v_win int;
  v_lose int;
  v_kinds int;
  v_copies int;
  v_hidden int;
  v_story_present boolean := false;
  v_made boolean := false;
  v_from text := 'owned';
  v_need int;
  v_old_level int;
  v_new_level int;
  v_old_best int;
  v_paid int;
  v_legacy_best int;
  v_legacy_paid int;
  v_tb jsonb;
  v_tp jsonb;
  v_gear jsonb;
  v_gear_n int := 0;
  v_gear_saved int := 0;
  v_sigil jsonb;
  v_plus int;
  v_seeds jsonb;
  v_receipts jsonb;
  v_enabled boolean;
  v_hash text;
  v_target text;
  v_mark uuid;
  v_line text;
  v_lines text[];
  r record;
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then
    raise exception 'STOP: staging cuyqchmdcnsgzkwyclji only (system_identifier 7703759698107299042)';
  end if;
  create table if not exists public.staging_sweep_fixture_backup (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);
create table if not exists public.staging_sweep_fixture_report (
  singleton boolean primary key default true check (singleton),
  nickname text not null,
  action text not null,
  report text not null,
  at timestamptz not null default now()
);
alter table public.staging_sweep_fixture_backup enable row level security;
alter table public.staging_sweep_fixture_report enable row level security;
revoke all on table public.staging_sweep_fixture_backup, public.staging_sweep_fixture_report from public, anon, authenticated;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    revoke all on table public.staging_sweep_fixture_backup, public.staging_sweep_fixture_report from service_role;
  end if;
  comment on table public.staging_sweep_fixture_backup is
    'Staging-only tower sweep test snapshot. Not a game table.';
  comment on table public.staging_sweep_fixture_report is
    'Latest staging sweep fixture notice. Not a game table.';

  select jsonb_agg(jsonb_build_object('id', f.id, 'level', f.level, 'win', f.win, 'lose', f.lose, 'name', f.name))
    into v_fix
  from (values
('10001', 60, 2, 3, '가윤우'),
  ('10002', 60, 2, 3, '강나빛'),
  ('10003', 40, 4, 5, '강리안'),
  ('10006', 40, 4, 5, '강서언'),
  ('10007', 1, 4, 5, '강세연'),
  ('10009', 40, 2, 3, '강신'),
  ('10010', 10, 4, 5, '강우섭'),
  ('10011', 80, 1, 2, '강유영'),
  ('10012', 40, 2, 3, '강재아'),
  ('10013', 1, 91, 92, '강준철'),
  ('10014', 80, 4, 5, '강지민'),
  ('10015', 1, 4, 5, '강철진'),
  ('10016', 1, 4, 5, '강철하'),
  ('10017', 1, 4, 5, '강철훈'),
  ('10018', 1, 2, 3, '강태안'),
  ('10019', 1, 2, 3, '강태준'),
  ('10020', 1, 4, 5, '강한길'),
  ('10021', 1, 4, 5, '경원석'),
  ('10024', 5, 91, 92, '고세린'),
  ('10025', 1, 92, 93, '고정태'),
  ('10026', 80, 2, 3, '고차연'),
  ('10029', 1, 2, 3, '공주연'),
  ('10030', 80, 2, 3, '공태인'),
  ('10033', 1, 4, 5, '곽재준'),
  ('10034', 40, 2, 3, '곽제형'),
  ('10035', 1, 4, 5, '곽진영'),
  ('10036', 1, 23, 24, '곽태우'),
  ('10037', 5, 4, 5, '구성원'),
  ('10039', 80, 2, 3, '권두리'),
  ('10040', 5, 4, 5, '권예강'),
  ('10041', 1, 27, 28, '권예리'),
  ('10042', 1, 4, 5, '권예진'),
  ('10043', 1, 27, 28, '권지아'),
  ('10044', 1, 4, 5, '권지우'),
  ('10045', 5, 94, 95, '금어진'),
  ('10046', 1, 4, 5, '금유진'),
  ('10047', 1, 4, 5, '길선재'),
  ('10048', 60, 2, 3, '길윤재'),
  ('10049', 80, 7, 8, '길정재'),
  ('10050', 60, 4, 5, '김가람'),
  ('10051', 1, 96, 97, '김기림'),
  ('10052', 1, 93, 94, '김나현'),
  ('10053', 1, 102, 103, '김대욱'),
  ('10054', 1, 102, 103, '김동욱'),
  ('10055', 80, 1, 2, '김들'),
  ('10056', 40, 2, 3, '김미윤'),
  ('10058', 1, 128, 129, '김백중'),
  ('10059', 1, 2, 3, '김샛별'),
  ('10060', 1, 178, 179, '김성진'),
  ('10061', 1, 31, 32, '김소영'),
  ('10062', 1, 122, 123, '김신현'),
  ('10063', 40, 7, 8, '김예빈'),
  ('10065', 1, 2, 3, '김재량'),
  ('10066', 60, 2, 3, '김재민'),
  ('10067', 1, 92, 93, '김재섭'),
  ('10068', 1, 92, 93, '김재신'),
  ('10069', 40, 7, 8, '김정한'),
  ('10070', 10, 94, 95, '김준기'),
  ('10071', 60, 1, 2, '김준하'),
  ('10072', 1, 42, 43, '김지수'),
  ('10073', 1, 53, 54, '김지우'),
  ('10075', 80, 1, 2, '김철중'),
  ('10077', 1, 4, 5, '김한결'),
  ('10078', 1, 4, 5, '김한별'),
  ('10079', 1, 4, 5, '김현진'),
  ('10081', 1, 42, 43, '김후'),
  ('10084', 40, 12, 13, '나윤아'),
  ('10085', 40, 4, 5, '나윤영'),
  ('10087', 1, 4, 5, '남고은'),
  ('10088', 20, 4, 5, '남궁무열'),
  ('10089', 1, 4, 5, '남궁형남'),
  ('10090', 1, 2, 3, '남다연'),
  ('10091', 1, 4, 5, '남다윤'),
  ('10092', 1, 4, 5, '남소연'),
  ('10095', 1, 4, 5, '노정아'),
  ('10096', 1, 4, 5, '노정은'),
  ('10097', 1, 4, 5, '동지선'),
  ('10098', 1, 4, 5, '두윤창'),
  ('10099', 80, 2, 3, '류장미'),
  ('10100', 60, 4, 5, '류태연'),
  ('10101', 20, 2, 3, '류하늘'),
  ('10102', 1, 22, 23, '류하늬'),
  ('10103', 1, 2, 3, '류하예'),
  ('10104', 1, 4, 5, '류햇빛'),
  ('10105', 1, 4, 5, '마하랑'),
  ('10107', 60, 2, 3, '문동혁'),
  ('10108', 1, 94, 95, '문유선'),
  ('10109', 1, 91, 92, '문재'),
  ('10110', 1, 4, 5, '문지아'),
  ('10111', 1, 4, 5, '문지예'),
  ('10112', 1, 92, 93, '문지철'),
  ('10114', 80, 1, 2, '문희찬'),
  ('10115', 1, 2, 3, '민유연'),
  ('10117', 1, 91, 92, '민지은'),
  ('10118', 1, 96, 97, '민홍기'),
  ('10119', 80, 7, 8, '박미르'),
  ('10120', 1, 12, 13, '박보라'),
  ('10121', 1, 2, 3, '박샘'),
  ('10122', 40, 7, 8, '박설이'),
  ('10123', 1, 4, 5, '박성관'),
  ('10124', 1, 4, 5, '박언석'),
  ('10125', 1, 4, 5, '박오류'),
  ('10126', 1, 23, 24, '박인아'),
  ('10127', 1, 94, 95, '박인영'),
  ('10129', 20, 2, 3, '박혜안'),
  ('10131', 1, 31, 32, '반지윤'),
  ('10132', 1, 2, 3, '배나빛'),
  ('10133', 1, 4, 5, '배수연'),
  ('10134', 1, 4, 5, '배승규'),
  ('10135', 1, 4, 5, '백버들'),
  ('10136', 1, 4, 5, '백천주'),
  ('10137', 1, 4, 5, '복광준'),
  ('10138', 1, 4, 5, '복광훈'),
  ('10140', 40, 2, 3, '복선아'),
  ('10141', 1, 4, 5, '복정아'),
  ('10169', 60, 2, 3, '사주혁'),
  ('10170', 40, 4, 5, '사진태'),
  ('10171', 40, 4, 5, '서경석'),
  ('10172', 80, 4, 5, '서규안'),
  ('10173', 60, 2, 3, '서규인'),
  ('10174', 40, 2, 3, '서미나'),
  ('10175', 1, 3, 4, '서민아'),
  ('10176', 1, 101, 102, '서성민'),
  ('10177', 40, 1, 2, '서아란'),
  ('10178', 60, 2, 3, '서아리'),
  ('10180', 1, 7, 8, '서영석'),
  ('10181', 1, 51, 52, '서오성'),
  ('10182', 1, 2, 3, '서진성'),
  ('10183', 5, 94, 95, '서태우'),
  ('10184', 80, 2, 3, '서하윤'),
  ('10185', 10, 12, 13, '선나영'),
  ('10186', 10, 111, 112, '선미영'),
  ('10187', 1, 4, 5, '선영운'),
  ('10188', 1, 27, 28, '선우민아'),
  ('10189', 1, 91, 92, '선우민철'),
  ('10190', 20, 4, 5, '선유린'),
  ('10191', 80, 7, 8, '선인구'),
  ('10192', 20, 3, 4, '설달'),
  ('10194', 1, 2, 3, '설하늘'),
  ('10195', 5, 1, 2, '성재수'),
  ('10200', 1, 91, 92, '소민섭'),
  ('10202', 1, 4, 5, '손란'),
  ('10203', 1, 51, 52, '손혜연'),
  ('10204', 1, 4, 5, '송다혜'),
  ('10205', 1, 4, 5, '송동혁'),
  ('10207', 1, 4, 5, '송지아'),
  ('10208', 1, 4, 5, '송지은'),
  ('10213', 1, 92, 93, '신시은'),
  ('10214', 1, 4, 5, '신아린'),
  ('10215', 40, 4, 5, '신아윤'),
  ('10216', 1, 102, 103, '신아은'),
  ('10217', 1, 102, 103, '신예은'),
  ('10218', 20, 4, 5, '신재'),
  ('10220', 10, 4, 5, '신주호'),
  ('10221', 80, 4, 5, '신지아'),
  ('10222', 1, 4, 5, '심버들'),
  ('10223', 60, 2, 3, '안다미'),
  ('10224', 1, 4, 5, '안리'),
  ('10225', 1, 4, 5, '안용태'),
  ('10226', 1, 2, 3, '안재수'),
  ('10227', 1, 4, 5, '안주연'),
  ('10228', 1, 4, 5, '안중산'),
  ('10229', 1, 4, 5, '안지수'),
  ('10230', 1, 4, 5, '안지연'),
  ('10231', 20, 107, 108, '안지윤'),
  ('10232', 60, 2, 3, '안태영'),
  ('10233', 40, 4, 5, '안현'),
  ('10234', 1, 2, 3, '안호선'),
  ('10236', 1, 92, 93, '양겨울'),
  ('10237', 1, 2, 3, '양서진'),
  ('10238', 40, 2, 3, '양소영'),
  ('10239', 1, 42, 43, '양유영'),
  ('10240', 1, 27, 28, '양제림'),
  ('10241', 1, 2, 3, '양주영'),
  ('10242', 5, 2, 3, '양지림'),
  ('10243', 20, 7, 8, '연재은'),
  ('10244', 1, 4, 5, '염상휘'),
  ('10245', 60, 2, 3, '염태영'),
  ('10246', 1, 4, 5, '예민지'),
  ('10247', 60, 7, 8, '예유나'),
  ('10249', 5, 4, 5, '예은아'),
  ('10251', 40, 4, 5, '예현승'),
  ('10252', 80, 2, 3, '오명준'),
  ('10253', 1, 3, 4, '오빛나'),
  ('10254', 1, 2, 3, '오샘나'),
  ('10255', 5, 92, 93, '오설화'),
  ('10256', 1, 4, 5, '오유나'),
  ('10257', 1, 22, 23, '오채원'),
  ('10258', 1, 4, 5, '오한설'),
  ('10259', 1, 2, 3, '오한음'),
  ('10260', 60, 7, 8, '오희진'),
  ('10261', 1, 2, 3, '온리연'),
  ('10264', 60, 7, 8, '왕유영'),
  ('10265', 1, 4, 5, '용지혜'),
  ('10266', 1, 2, 3, '용지효'),
  ('10267', 1, 51, 52, '유가을'),
  ('10268', 1, 27, 28, '유나리'),
  ('10269', 5, 102, 103, '유아리'),
  ('10270', 1, 4, 5, '유진산'),
  ('10271', 40, 2, 3, '유진아'),
  ('10273', 60, 2, 3, '유태이'),
  ('10275', 40, 7, 8, '유형수'),
  ('10276', 1, 4, 5, '유혜운'),
  ('10278', 1, 2, 3, '윤남규'),
  ('10280', 80, 7, 8, '윤미리내'),
  ('10281', 1, 93, 94, '윤믿음'),
  ('10282', 40, 7, 8, '윤샛별'),
  ('10283', 1, 4, 5, '윤석구'),
  ('10284', 1, 4, 5, '윤석팔'),
  ('10285', 1, 2, 3, '윤세정'),
  ('10287', 1, 4, 5, '윤우람'),
  ('10288', 1, 4, 5, '윤은별'),
  ('10289', 80, 2, 3, '윤정하'),
  ('10290', 1, 2, 3, '윤진아'),
  ('10291', 1, 122, 123, '[각성] 윤진아'),
  ('10292', 1, 4, 5, '윤태민'),
  ('10293', 1, 4, 5, '윤태영'),
  ('10294', 20, 1, 2, '윤태희'),
  ('10295', 40, 2, 3, '윤희지'),
  ('10296', 1, 4, 5, '이누리'),
  ('10297', 1, 2, 3, '이로하'),
  ('10298', 1, 4, 5, '이명진'),
  ('10299', 1, 2, 3, '이민수'),
  ('10300', 1, 4, 5, '이민채'),
  ('10303', 60, 2, 3, '이믿음'),
  ('10304', 1, 102, 103, '이성호'),
  ('10305', 80, 2, 3, '이소진'),
  ('10306', 1, 2, 3, '이영아'),
  ('10307', 1, 7, 8, '이영하'),
  ('10308', 1, 4, 5, '이윤이'),
  ('10309', 1, 4, 5, '이재덕'),
  ('10311', 1, 178, 179, '이지영'),
  ('10312', 1, 113, 114, '이진경'),
  ('10313', 40, 2, 3, '이진규'),
  ('10315', 60, 4, 5, '이찬열'),
  ('10316', 60, 2, 3, '이택길'),
  ('10317', 1, 81, 82, '이혜경'),
  ('10318', 20, 2, 3, '이호준'),
  ('10319', 1, 4, 5, '이후남'),
  ('10321', 1, 93, 94, '인창수'),
  ('10322', 1, 102, 103, '임규리'),
  ('10323', 1, 122, 123, '임나리'),
  ('10324', 1, 101, 102, '임예리'),
  ('10325', 1, 118, 119, '임유리'),
  ('10326', 1, 164, 165, '[각성] 임유리'),
  ('10327', 5, 7, 8, '임조은'),
  ('10328', 1, 4, 5, '임창수'),
  ('10329', 1, 81, 82, '임창열'),
  ('10330', 80, 7, 8, '임한빈'),
  ('10331', 1, 102, 103, '임혜리'),
  ('10332', 40, 7, 8, '장동만'),
  ('10333', 1, 91, 92, '장무영'),
  ('10336', 1, 51, 52, '장세유'),
  ('10338', 1, 51, 52, '장아유'),
  ('10340', 40, 4, 5, '장제훈'),
  ('10341', 1, 93, 94, '장초롱'),
  ('10342', 20, 2, 3, '장혜린'),
  ('10343', 1, 4, 5, '전미성'),
  ('10345', 1, 2, 3, '전민진'),
  ('10346', 40, 2, 3, '전성국'),
  ('10347', 1, 2, 3, '전수양'),
  ('10348', 80, 7, 8, '전잔디'),
  ('10349', 1, 4, 5, '전주일'),
  ('10350', 1, 36, 37, '전중혁'),
  ('10351', 80, 2, 3, '전필수'),
  ('10352', 60, 2, 3, '전하나'),
  ('10353', 40, 2, 3, '전호영'),
  ('10354', 1, 51, 52, '정다윤'),
  ('10355', 40, 7, 8, '정미선'),
  ('10356', 60, 7, 8, '정새론'),
  ('10357', 1, 2, 3, '정서영'),
  ('10358', 1, 113, 114, '정석윤'),
  ('10359', 1, 102, 103, '정아람'),
  ('10360', 40, 2, 3, '정아영'),
  ('10361', 1, 23, 24, '정아윤'),
  ('10362', 1, 4, 5, '정연아'),
  ('10364', 80, 7, 8, '정재헌'),
  ('10365', 80, 2, 3, '정종일'),
  ('10366', 40, 2, 3, '정지석'),
  ('10367', 1, 2, 3, '정지선'),
  ('10368', 1, 4, 5, '정치성'),
  ('10369', 1, 51, 52, '정치욱'),
  ('10370', 1, 2, 3, '정치환'),
  ('10371', 1, 4, 5, '정태진'),
  ('10372', 1, 2, 3, '정하나'),
  ('10373', 1, 27, 28, '정하루'),
  ('10374', 1, 18, 19, '정한서'),
  ('10375', 80, 4, 5, '정형준'),
  ('10378', 1, 2, 3, '제갈민영'),
  ('10379', 60, 2, 3, '제갈버들'),
  ('10380', 1, 2, 3, '조승규'),
  ('10383', 1, 93, 94, '조윤이'),
  ('10384', 1, 1, 2, '조윤하'),
  ('10385', 1, 7, 8, '조주열'),
  ('10386', 1, 4, 5, '조한얼'),
  ('10387', 40, 2, 3, '주서영'),
  ('10389', 80, 2, 3, '주슬기'),
  ('10390', 40, 2, 3, '주연욱'),
  ('10391', 1, 4, 5, '주예나'),
  ('10392', 1, 93, 94, '주예린'),
  ('10393', 1, 22, 23, '주예서'),
  ('10394', 1, 2, 3, '지세련'),
  ('10395', 40, 2, 3, '지유현'),
  ('10396', 20, 7, 8, '지주현'),
  ('10397', 5, 13, 14, '진교진'),
  ('10398', 1, 7, 8, '진수열'),
  ('10399', 1, 82, 83, '진하린'),
  ('10400', 1, 22, 23, '채예린'),
  ('10401', 5, 4, 5, '채훈기'),
  ('10403', 40, 7, 8, '천혜원'),
  ('10405', 5, 2, 3, '최겨울'),
  ('10406', 1, 51, 52, '최국선'),
  ('10407', 1, 2, 3, '최대운'),
  ('10408', 1, 3, 4, '최두길'),
  ('10409', 40, 4, 5, '최민우'),
  ('10410', 80, 2, 3, '최봉근'),
  ('10411', 80, 7, 8, '최여진'),
  ('10412', 40, 7, 8, '최유안'),
  ('10413', 1, 51, 52, '최윤아'),
  ('10414', 1, 22, 23, '최윤정'),
  ('10415', 1, 94, 95, '최윤희'),
  ('10416', 40, 2, 3, '최재홍'),
  ('10417', 5, 7, 8, '최정인'),
  ('10418', 10, 91, 92, '최지연'),
  ('10419', 1, 4, 5, '최진규'),
  ('10420', 1, 4, 5, '최한길'),
  ('10421', 40, 2, 3, '최훈남'),
  ('10422', 80, 2, 3, '최훈필'),
  ('10423', 40, 4, 5, '추나리'),
  ('10424', 1, 4, 5, '추정욱'),
  ('10425', 1, 23, 24, '탁동탁'),
  ('10426', 1, 4, 5, '탁동혜'),
  ('10427', 40, 3, 4, '탁리'),
  ('10429', 1, 4, 5, '탁희원'),
  ('10430', 80, 2, 3, '표오성'),
  ('10432', 1, 2, 3, '표지아'),
  ('10433', 1, 18, 19, '풍건'),
  ('10434', 60, 4, 5, '풍힘찬'),
  ('10435', 1, 92, 93, '하승진'),
  ('10436', 20, 3, 4, '하윤하'),
  ('10437', 1, 4, 5, '하장미'),
  ('10438', 80, 7, 8, '하지연'),
  ('10439', 1, 106, 107, '하지은'),
  ('10440', 1, 113, 114, '하지혜'),
  ('10442', 1, 4, 5, '한겨울'),
  ('10446', 10, 3, 4, '한하루'),
  ('10447', 1, 2, 3, '허동아'),
  ('10448', 40, 4, 5, '허성'),
  ('10450', 80, 7, 8, '허유란'),
  ('10451', 40, 7, 8, '허유리'),
  ('10452', 1, 37, 38, '허유희'),
  ('10454', 1, 2, 3, '허진서'),
  ('10455', 1, 4, 5, '홍가영'),
  ('10457', 1, 23, 24, '홍다영'),
  ('10458', 1, 4, 5, '황기훈'),
  ('10459', 40, 2, 3, '황다미'),
  ('10460', 40, 2, 3, '황다영'),
  ('10461', 1, 4, 5, '황다윤'),
  ('10462', 1, 2, 3, '황보예'),
  ('10463', 1, 23, 24, '황보재규'),
  ('10464', 1, 4, 5, '황보훈'),
  ('10465', 10, 104, 105, '황예영'),
  ('10466', 1, 2, 3, '황예은'),
  ('10467', 5, 2, 3, '황은아'),
  ('10468', 60, 2, 3, '황은채'),
  ('10469', 40, 4, 5, '황준태'),
  ('10470', 1, 4, 5, '황지수'),
  ('10471', 20, 4, 5, '황지은'),
  ('10473', 1, 27, 28, '황한결'),
  ('10474', 60, 1, 2, '황혁'),
  ('10509', 1, 23, 24, '강보람')
  ) as f(id, level, win, lose, name);
  if v_action not in ('apply', 'revert') then
    raise exception 'STOP: action must be apply or revert';
  end if;
  v_nick := btrim(v_nick);
  if v_nick is null or v_nick = '' or char_length(v_nick) > 20 then
    raise exception 'STOP: set v_nick to one profile nickname';
  end if;
  if to_regprocedure('public.battle_sweep_settle_v6(uuid,uuid,text,jsonb)') is null
     or to_regprocedure('public.battle_session_start_v2(text,text,jsonb,uuid)') is null
     or to_regprocedure('public._tower_min_level(text)') is null
     or to_regprocedure('public._tower_today()') is null
     or to_regprocedure('public._clear_access_v2(uuid,text,text)') is null then
    raise exception 'STOP: phase6 sweep SQL is not installed on this staging database';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(v_fix) as x(id text, level int, win int, lose int, name text)
    where x.lose <> x.win + 1 or x.win < 1 or x.lose > 349 or x.win % 10 = 0 or x.lose % 10 = 0 or x.win % 10 = 9
  ) then
    raise exception 'STOP: fixture table is inconsistent';
  end if;

  select count(*) into v_n from public.profiles where nickname = v_nick;
  if v_n = 0 then
    raise exception 'STOP: nickname % matches 0 profiles', v_nick;
  end if;
  if v_n > 1 then
    raise exception 'STOP: nickname % matches % profiles; nothing was changed', v_nick, v_n;
  end if;
  select id into v_uid from public.profiles where nickname = v_nick;
  perform pg_advisory_xact_lock(hashtext('staging-sweep-fixture:' || v_uid::text));
  perform 1 from public.story_progress where user_id = v_uid for update;
  perform 1 from public.player_state where user_id = v_uid for update;
  perform 1 from public.tower_progress where user_id = v_uid and tower = 'normal' for update;
  perform 1 from public.battle_legacy_access_v2 where user_id = v_uid for update;
  perform 1 from public.staging_sweep_fixture_backup where user_id = v_uid for update;

  if v_action = 'revert' then
    select snapshot into v_snap from public.staging_sweep_fixture_backup where user_id = v_uid;
    if v_snap is null then
      raise exception 'STOP: no sweep fixture backup for %; nothing was changed', v_nick;
    end if;
    v_card_id := v_snap->>'card_id';

    if v_snap->'player_state' is null or jsonb_typeof(v_snap->'player_state') = 'null' then
      delete from public.player_state where user_id = v_uid;
    else
      insert into public.player_state(user_id, level, xp, stamina, stamina_at)
      values (
        v_uid,
        (v_snap->'player_state'->>'level')::int,
        (v_snap->'player_state'->>'xp')::int,
        (v_snap->'player_state'->>'stamina')::int,
        (v_snap->'player_state'->>'stamina_at')::timestamptz
      )
      on conflict (user_id) do update set
        level = excluded.level,
        xp = excluded.xp,
        stamina = excluded.stamina,
        stamina_at = excluded.stamina_at,
        updated_at = now();
    end if;

    if v_snap->'tower' is null or jsonb_typeof(v_snap->'tower') = 'null' then
      delete from public.tower_progress where user_id = v_uid and tower = 'normal';
    else
      insert into public.tower_progress(user_id, tower, best_floor, paid_floor, battle, clears, rewards, day, day_floors)
      values (
        v_uid,
        'normal',
        (v_snap->'tower'->>'best_floor')::int,
        (v_snap->'tower'->>'paid_floor')::int,
        case when jsonb_typeof(v_snap->'tower'->'battle') = 'null' then null else v_snap->'tower'->'battle' end,
        coalesce((v_snap->'tower'->>'clears')::int, 0),
        case when jsonb_typeof(v_snap->'tower'->'rewards') = 'object' then v_snap->'tower'->'rewards' else '{}'::jsonb end,
        nullif(v_snap->'tower'->>'day', '')::date,
        coalesce((v_snap->'tower'->>'day_floors')::int, 0)
      )
      on conflict (user_id, tower) do update set
        best_floor = excluded.best_floor,
        paid_floor = excluded.paid_floor,
        battle = excluded.battle,
        clears = excluded.clears,
        rewards = excluded.rewards,
        day = excluded.day,
        day_floors = excluded.day_floors,
        updated_at = now();
    end if;

    if v_snap->'legacy' is null or jsonb_typeof(v_snap->'legacy') = 'null' then
      delete from public.battle_legacy_access_v2 where user_id = v_uid;
    else
      insert into public.battle_legacy_access_v2(user_id, cleared, tower_best, tower_paid)
      values (
        v_uid,
        case when jsonb_typeof(v_snap->'legacy'->'cleared') = 'object' then v_snap->'legacy'->'cleared' else '{}'::jsonb end,
        case when jsonb_typeof(v_snap->'legacy'->'tower_best') = 'object' then v_snap->'legacy'->'tower_best' else '{}'::jsonb end,
        case when jsonb_typeof(v_snap->'legacy'->'tower_paid') = 'object' then v_snap->'legacy'->'tower_paid' else '{}'::jsonb end
      )
      on conflict (user_id) do update set
        cleared = excluded.cleared,
        tower_best = excluded.tower_best,
        tower_paid = excluded.tower_paid;
    end if;

    if coalesce((v_snap->>'story_present')::boolean, jsonb_typeof(v_snap->'story_data') = 'object') then
      update public.story_progress
        set data = v_snap->'story_data', updated_at = now()
        where user_id = v_uid;
      if not found then
        insert into public.story_progress(user_id, data)
        values (v_uid, v_snap->'story_data');
      end if;
    else
      delete from public.story_progress where user_id = v_uid;
    end if;

    update public.player_gear set equipped_card = null
      where user_id = v_uid and equipped_card = v_card_id;
    v_gear_n := 0;
    for r in select value from jsonb_array_elements(coalesce(v_snap->'gear', '[]'::jsonb)) loop
      update public.player_gear
        set equipped_card = r.value->>'equipped_card'
        where id = (r.value->>'id')::bigint and user_id = v_uid;
      if found then v_gear_n := v_gear_n + 1; end if;
    end loop;

    if coalesce((v_snap->'sigil'->>'present')::boolean, false) then
      update public.player_sigils
        set plus = case when jsonb_typeof(v_snap->'sigil'->'plus') = 'null' then null else (v_snap->'sigil'->>'plus')::int end
        where user_id = v_uid and card_id = v_card_id;
    end if;

    for r in select value from jsonb_array_elements(coalesce(v_snap->'seeds', '[]'::jsonb)) loop
      v_target := r.value->>'target';
      if jsonb_typeof(r.value->'seed') = 'null' then
        delete from public.battle_session_seeds_v2
          where user_id = v_uid and mode = 'tower_sweep' and target = v_target and rule_version = 3;
      else
        insert into public.battle_session_seeds_v2(user_id, mode, target, seed, rule_version)
        values (v_uid, 'tower_sweep', v_target, (r.value->>'seed')::int, 3)
        on conflict (user_id, mode, target, rule_version) do update set seed = excluded.seed;
      end if;
    end loop;

    delete from public.battle_clear_receipts_v2 rc
      where rc.user_id = v_uid and rc.mode = 'tower'
        and rc.target in ('normal:' || (v_snap->>'win'), 'normal:' || (v_snap->>'lose'))
        and not (rc.target = any (array(select jsonb_array_elements_text(coalesce(v_snap->'receipts', '[]'::jsonb)))));
    delete from public.battle_sessions_v2
      where user_id = v_uid
        and target in ('normal:' || (v_snap->>'win'), 'normal:' || (v_snap->>'lose'))
        and coalesce(snapshot->>'fixture_marker', '') = 'true';

    delete from public.staging_sweep_fixture_backup where user_id = v_uid;

    v_lines := array[
      'revert 완료: ' || v_nick || ' (' || v_uid::text || ')',
      '시련의 탑 기록, 계정 레벨, 리더, 장비 장착, 증표 강화, 소탕 시드를 백업 시점으로 되돌렸습니다.',
      case when coalesce((v_snap->>'story_present')::boolean, jsonb_typeof(v_snap->'story_data') = 'object')
        then '보유 인재 목록을 백업 내용으로 되돌렸습니다.'
        else '스토리 보유 목록이 원래 없었으므로 그 행을 지웠습니다.' end,
      '시험 뒤에 뽑은 인재와 시험으로 오른 탑 기록은 백업에 없어서 사라집니다. 장비 복구 ' || v_gear_n::text || '개.',
      '골드·젬·소환권·피·조각·혼은 이 스크립트가 바꾼 적이 없습니다.',
      '같은 파일을 다시 apply 하면 새 백업을 만들고 시험을 다시 맞춥니다.'
    ];
  else
    select data into v_story from public.story_progress where user_id = v_uid;
    v_story_present := found;
    if not v_story_present or jsonb_typeof(v_story) is distinct from 'object' then
      v_story_present := false;
      v_story := '{}'::jsonb;
    end if;
    select snapshot into v_snap from public.staging_sweep_fixture_backup where user_id = v_uid;
    v_reused := v_snap is not null;

    if not v_reused then
      v_have := '{}';
      if jsonb_typeof(v_story->'owned') = 'array' then
        select coalesce(array_agg(distinct elem->>'id'), '{}') into v_have
        from jsonb_array_elements(v_story->'owned') elem
        where elem->>'id' ~ '^[0-9]+$';
        v_from := 'owned';
      elsif jsonb_typeof(v_story->'owned') = 'object' then
        select coalesce(array_agg(k.id), '{}') into v_have
        from jsonb_object_keys(v_story->'owned') as k(id)
        where k.id ~ '^[0-9]+$';
        v_from := 'owned';
      end if;
      if not exists (
        select 1 from jsonb_to_recordset(v_fix) as f(id text, level int, win int, lose int, name text)
        where f.id = any(coalesce(v_have, '{}'))
      ) then
        v_from := 'trace';
        v_have := '{}';
        if to_regclass('public.player_gear') is not null then
          select coalesce(v_have, '{}') || coalesce(array_agg(distinct g.equipped_card), '{}') into v_have
          from public.player_gear g
          where g.user_id = v_uid and g.equipped_card ~ '^[0-9]+$';
        end if;
        if to_regclass('public.player_sigils') is not null then
          select coalesce(v_have, '{}') || coalesce(array_agg(distinct s.card_id), '{}') into v_have
          from public.player_sigils s
          where s.user_id = v_uid and s.card_id ~ '^[0-9]+$';
        end if;
        if to_regclass('public.story_gacha_log') is not null then
          select coalesce(v_have, '{}') || coalesce(array_agg(distinct l.card_id), '{}') into v_have
          from public.story_gacha_log l
          where l.user_id = v_uid and l.card_id ~ '^[0-9]+$';
        end if;
        if to_regclass('public.pvp_decks') is not null then
          select coalesce(v_have, '{}') || coalesce(array_agg(distinct c->>'id'), '{}') into v_have
          from public.pvp_decks d
          cross join lateral jsonb_array_elements(case when jsonb_typeof(d.snap) = 'array' then d.snap else '[]'::jsonb end) c
          where d.user_id = v_uid and c->>'id' ~ '^[0-9]+$';
        end if;
        if to_regclass('public.battle_sessions_v2') is not null then
          select coalesce(v_have, '{}') || coalesce(array_agg(distinct c->>'id'), '{}') into v_have
          from public.battle_sessions_v2 s
          cross join lateral jsonb_array_elements(case when jsonb_typeof(s.snapshot->'cards') = 'array' then s.snapshot->'cards' else '[]'::jsonb end) c
          where s.user_id = v_uid and c->>'id' ~ '^[0-9]+$';
        end if;
      end if;
      select f.id, f.name, f.level, f.win, f.lose
        into v_card_id, v_name, v_level, v_win, v_lose
      from jsonb_to_recordset(v_fix) as f(id text, level int, win int, lose int, name text)
      where f.id = any(coalesce(v_have, '{}'))
      order by f.win, f.level, f.id
      limit 1;
      if v_card_id is null then
        v_from := 'new';
        select f.id, f.name, f.level, f.win, f.lose
          into v_card_id, v_name, v_level, v_win, v_lose
        from jsonb_to_recordset(v_fix) as f(id text, level int, win int, lose int, name text)
        order by f.win, f.level, f.id
        limit 1;
      end if;
      v_made := not exists (
        select 1
        from jsonb_array_elements(case when jsonb_typeof(v_story->'owned') = 'array' then v_story->'owned' else '[]'::jsonb end) elem
        where elem->>'id' = v_card_id
      );

      select case when ps.user_id is null then 'null'::jsonb else jsonb_build_object(
        'level', ps.level, 'xp', ps.xp, 'stamina', ps.stamina, 'stamina_at', ps.stamina_at
      ) end
        into v_snap
      from (select 1) s
      left join public.player_state ps on ps.user_id = v_uid;
      v_snap := jsonb_build_object('player_state', v_snap);

      select case when tp.user_id is null then 'null'::jsonb else jsonb_build_object(
        'best_floor', tp.best_floor, 'paid_floor', tp.paid_floor, 'battle', tp.battle,
        'clears', tp.clears, 'rewards', tp.rewards, 'day', tp.day, 'day_floors', tp.day_floors
      ) end
        into v_tb
      from (select 1) s
      left join public.tower_progress tp on tp.user_id = v_uid and tp.tower = 'normal';

      select case when lg.user_id is null then 'null'::jsonb else jsonb_build_object(
        'cleared', lg.cleared, 'tower_best', lg.tower_best, 'tower_paid', lg.tower_paid
      ) end
        into v_tp
      from (select 1) s
      left join public.battle_legacy_access_v2 lg on lg.user_id = v_uid;

      select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'equipped_card', g.equipped_card) order by g.id), '[]'::jsonb)
        into v_gear
      from public.player_gear g
      where g.user_id = v_uid and g.equipped_card = v_card_id;

      select s.plus into v_plus from public.player_sigils s where s.user_id = v_uid and s.card_id = v_card_id;
      if found then v_sigil := jsonb_build_object('present', true, 'plus', v_plus);
      else v_sigil := jsonb_build_object('present', false); end if;

      select coalesce(jsonb_agg(jsonb_build_object('target', t.target, 'seed', sd.seed)), '[]'::jsonb)
        into v_seeds
      from unnest(array['normal:' || v_win::text, 'normal:' || v_lose::text]) as t(target)
      left join public.battle_session_seeds_v2 sd
        on sd.user_id = v_uid and sd.mode = 'tower_sweep' and sd.target = t.target and sd.rule_version = 3;

      select coalesce(jsonb_agg(rc.target order by rc.target), '[]'::jsonb)
        into v_receipts
      from public.battle_clear_receipts_v2 rc
      where rc.user_id = v_uid and rc.mode = 'tower'
        and rc.target in ('normal:' || v_win::text, 'normal:' || v_lose::text);

      v_snap := v_snap || jsonb_build_object(
        'nickname', v_nick,
        'card_id', v_card_id,
        'card_name', v_name,
        'level', v_level,
        'win', v_win,
        'lose', v_lose,
        'tower', v_tb,
        'legacy', v_tp,
        'story_present', v_story_present,
        'story_data', case when v_story_present then v_story else 'null'::jsonb end,
        'made_card', v_made,
        'card_from', v_from,
        'gear', v_gear,
        'sigil', v_sigil,
        'seeds', v_seeds,
        'receipts', v_receipts
      );
      insert into public.staging_sweep_fixture_backup(user_id, nickname, snapshot)
      values (v_uid, v_nick, v_snap);
    end if;

    v_card_id := v_snap->>'card_id';
    select f.level, f.win, f.lose, f.name
      into v_level, v_win, v_lose, v_name
    from jsonb_to_recordset(v_fix) as f(id text, level int, win int, lose int, name text)
    where f.id = v_card_id;
    if not found
       or (v_snap->>'level')::int is distinct from v_level
       or (v_snap->>'win')::int is distinct from v_win
       or (v_snap->>'lose')::int is distinct from v_lose then
      raise exception 'STOP: backup for % does not match this fixture file. Revert with the file that created it.', v_nick;
    end if;
    v_story := case when jsonb_typeof(v_snap->'story_data') = 'object' then v_snap->'story_data' else '{}'::jsonb end;
    v_story_present := coalesce((v_snap->>'story_present')::boolean, jsonb_typeof(v_snap->'story_data') = 'object');

    select coalesce(jsonb_agg(
      (elem - 'level' - 'exp' - 'boost' - 'ex' - 'exb' - 'skillLv')
      || jsonb_build_object(
        'uid', case when coalesce(elem->>'uid', '') <> '' then elem->>'uid' else 'sweepfix:' || v_card_id || ':' || ord::text end,
        'id', v_card_id,
        'level', v_level, 'exp', 0, 'boost', '{}'::jsonb, 'ex', 0, 'exb', 0, 'skillLv', '{}'::jsonb
      )
      order by ord
    ), '[]'::jsonb)
      into v_owned
    from jsonb_array_elements(case when jsonb_typeof(v_story->'owned') = 'array' then v_story->'owned' else '[]'::jsonb end)
      with ordinality as t(elem, ord)
    where jsonb_typeof(elem) = 'object' and elem->>'id' = v_card_id;
    if coalesce(jsonb_array_length(v_owned), 0) < 1 then
      v_owned := jsonb_build_array(jsonb_build_object(
        'uid', 'sweepfix:' || v_card_id,
        'id', v_card_id,
        'level', v_level,
        'exp', 0,
        'totalExp', 0,
        'boost', '{}'::jsonb,
        'ex', 0,
        'exb', 0,
        'skillLv', '{}'::jsonb,
        'cpts', 0,
        'spentCard', 0
      ));
    end if;
    v_copies := jsonb_array_length(v_owned);
    select count(*) into v_hidden
    from jsonb_array_elements(case when jsonb_typeof(v_story->'owned') = 'array' then v_story->'owned' else '[]'::jsonb end) elem
    where jsonb_typeof(elem) = 'object' and elem->>'id' is distinct from v_card_id;

    v_story := jsonb_set(v_story, '{owned}', v_owned, true);
    v_story := jsonb_set(v_story, '{leader}', 'null'::jsonb, true);
    v_story := jsonb_set(v_story, '{decks}', jsonb_build_array(jsonb_build_object(
      'name', '소탕 시험',
      'uids', jsonb_build_array(v_owned->0->>'uid')
    )), true);
    if v_story_present then
      update public.story_progress set data = v_story, updated_at = now() where user_id = v_uid;
      if not found then
        insert into public.story_progress(user_id, data) values (v_uid, v_story);
      end if;
    else
      insert into public.story_progress(user_id, data) values (v_uid, v_story)
      on conflict (user_id) do update set data = excluded.data, updated_at = now();
    end if;

    v_need := public._tower_min_level('normal');
    if v_need is null or v_need < 1 or v_need > 100 or public._tower_daily('normal') < 2
       or not (public._tower_dow() = any(public._tower_days('normal'))) then
      raise exception 'STOP: normal tower gate is not usable for this test';
    end if;
    if v_snap->'player_state' is null or jsonb_typeof(v_snap->'player_state') = 'null' then
      v_old_level := 1;
      v_new_level := greatest(v_old_level, v_need);
      insert into public.player_state(user_id, level)
      values (v_uid, v_new_level)
      on conflict (user_id) do update set level = excluded.level, updated_at = now();
    else
      v_old_level := (v_snap->'player_state'->>'level')::int;
      v_new_level := greatest(v_old_level, v_need);
      insert into public.player_state(user_id, level, xp, stamina, stamina_at)
      values (
        v_uid, v_new_level,
        (v_snap->'player_state'->>'xp')::int,
        (v_snap->'player_state'->>'stamina')::int,
        (v_snap->'player_state'->>'stamina_at')::timestamptz
      )
      on conflict (user_id) do update set
        level = excluded.level, xp = excluded.xp, stamina = excluded.stamina,
        stamina_at = excluded.stamina_at, updated_at = now();
    end if;

    v_old_best := case when v_snap->'tower' is null or jsonb_typeof(v_snap->'tower') = 'null' then 0 else (v_snap->'tower'->>'best_floor')::int end;
    v_paid := greatest(
      case when v_snap->'tower' is null or jsonb_typeof(v_snap->'tower') = 'null' then 0 else coalesce((v_snap->'tower'->>'paid_floor')::int, 0) end,
      v_lose
    );
    if v_snap->'tower' is null or jsonb_typeof(v_snap->'tower') = 'null' then
      insert into public.tower_progress(user_id, tower, best_floor, paid_floor, battle, clears, rewards, day, day_floors)
      values (v_uid, 'normal', v_win - 1, v_paid, null, 0, '{}'::jsonb, public._tower_today(), 0)
      on conflict (user_id, tower) do update set
        best_floor = excluded.best_floor, paid_floor = excluded.paid_floor, battle = null,
        clears = 0, rewards = '{}'::jsonb, day = excluded.day, day_floors = 0, updated_at = now();
    else
      insert into public.tower_progress(user_id, tower, best_floor, paid_floor, battle, clears, rewards, day, day_floors)
      values (
        v_uid, 'normal', v_win - 1, v_paid, null,
        coalesce((v_snap->'tower'->>'clears')::int, 0),
        case when jsonb_typeof(v_snap->'tower'->'rewards') = 'object' then v_snap->'tower'->'rewards' else '{}'::jsonb end,
        public._tower_today(), 0
      )
      on conflict (user_id, tower) do update set
        best_floor = excluded.best_floor, paid_floor = excluded.paid_floor, battle = null,
        clears = excluded.clears, rewards = excluded.rewards, day = excluded.day,
        day_floors = 0, updated_at = now();
    end if;

    v_legacy_best := greatest(
      case when v_snap->'legacy' is null or jsonb_typeof(v_snap->'legacy') = 'null' then 0
           else coalesce((v_snap->'legacy'->'tower_best'->>'normal')::int, 0) end,
      v_win - 1
    );
    v_legacy_paid := greatest(
      case when v_snap->'legacy' is null or jsonb_typeof(v_snap->'legacy') = 'null' then 0
           else coalesce((v_snap->'legacy'->'tower_paid'->>'normal')::int, 0) end,
      v_lose
    );
    if v_snap->'legacy' is null or jsonb_typeof(v_snap->'legacy') = 'null' then
      v_tb := jsonb_build_object('normal', v_legacy_best);
      v_tp := jsonb_build_object('normal', v_legacy_paid);
      insert into public.battle_legacy_access_v2(user_id, cleared, tower_best, tower_paid)
      values (v_uid, '{}'::jsonb, v_tb, v_tp)
      on conflict (user_id) do update set
        cleared = excluded.cleared, tower_best = excluded.tower_best, tower_paid = excluded.tower_paid;
    else
      v_tb := jsonb_set(
        case when jsonb_typeof(v_snap->'legacy'->'tower_best') = 'object' then v_snap->'legacy'->'tower_best' else '{}'::jsonb end,
        '{normal}', to_jsonb(v_legacy_best), true);
      v_tp := jsonb_set(
        case when jsonb_typeof(v_snap->'legacy'->'tower_paid') = 'object' then v_snap->'legacy'->'tower_paid' else '{}'::jsonb end,
        '{normal}', to_jsonb(v_legacy_paid), true);
      insert into public.battle_legacy_access_v2(user_id, cleared, tower_best, tower_paid)
      values (
        v_uid,
        case when jsonb_typeof(v_snap->'legacy'->'cleared') = 'object' then v_snap->'legacy'->'cleared' else '{}'::jsonb end,
        v_tb, v_tp
      )
      on conflict (user_id) do update set
        cleared = excluded.cleared, tower_best = excluded.tower_best, tower_paid = excluded.tower_paid;
    end if;

    update public.player_gear set equipped_card = null
      where user_id = v_uid and equipped_card = v_card_id;
    get diagnostics v_gear_n = row_count;
    v_gear_saved := coalesce(jsonb_array_length(v_snap->'gear'), 0);
    update public.player_sigils set plus = null
      where user_id = v_uid and card_id = v_card_id and plus is not null;

    insert into public.battle_session_seeds_v2(user_id, mode, target, seed, rule_version)
    values
      (v_uid, 'tower_sweep', 'normal:' || v_win::text, 7, 3),
      (v_uid, 'tower_sweep', 'normal:' || v_lose::text, 7, 3)
    on conflict (user_id, mode, target, rule_version) do update set seed = excluded.seed;

    if coalesce((select (tower_paid->>'normal')::int from public.battle_legacy_access_v2 where user_id = v_uid), 0) < v_lose
       or coalesce((select paid_floor from public.tower_progress where user_id = v_uid and tower = 'normal'), 0) < v_lose then
      raise exception 'STOP: first-clear baseline was not raised for %', v_nick;
    end if;
    -- The server pays only when floor > tower_paid.normal AND no receipt exists.
    -- A receipt for the win and lose floors makes first_ false even if that baseline is missed.
    foreach v_target in array array['normal:' || v_win::text, 'normal:' || v_lose::text] loop
      if exists (select 1 from public.battle_clear_receipts_v2 where user_id = v_uid and mode = 'tower' and target = v_target) then
        continue;
      end if;
      insert into public.battle_sessions_v2(user_id, request_id, mode, target, party, seed, snapshot, status, issued_at, expires_at, finished_at)
      values (
        v_uid, gen_random_uuid(), 'tower_sweep', v_target, '[]'::jsonb, 7,
        jsonb_build_object('min_seconds', 0, 'fixture_marker', true, 'cards', '[]'::jsonb),
        'settled', clock_timestamp() - interval '3 hours', clock_timestamp() - interval '1 hour', clock_timestamp()
      )
      returning id into v_mark;
      insert into public.battle_clear_receipts_v2(user_id, mode, target, session_id)
      values (v_uid, 'tower', v_target, v_mark);
    end loop;

    v_enabled := null;
    v_hash := null;
    if to_regclass('public.battle_replay_policy_v6') is not null then
      select enabled, engine_hash into v_enabled, v_hash from public.battle_replay_policy_v6 where singleton;
    end if;

    v_lines := array[
      'apply 완료: ' || v_nick || ' (' || v_uid::text || ')' || case when v_reused then ' / 기존 백업 유지' else ' / 새 백업' end,
      '소탕 인재 1장: ' || v_name || ' (id ' || v_card_id || ') 레벨 ' || v_level::text || ' / 사본 ' || v_copies::text || '장만 보유 목록에 남김 / 다른 인재 ' || v_hidden::text || '장은 백업에 보관'
        || case coalesce(v_snap->>'card_from', 'owned')
          when 'new' then ' 보유 인재가 없어 시험 카드 1장을 넣었습니다. revert 하면 그 목록은 원래대로 돌아갑니다.'
          when 'trace' then ' 스토리 보유 목록이 비어 장비·증표·뽑기·대전 기록의 카드로 소탕 덱을 만들었습니다. revert 하면 목록은 원래대로 돌아갑니다.'
          else '' end,
      '리더 스킬 끔. 장비 ' || v_gear_n::text || '개 해제 (백업 ' || v_gear_saved::text || '개). 증표 강화도 잠시 끔. 강화·EX·스킬 레벨 비움.',
      '계정 레벨 ' || v_old_level::text || ' -> ' || v_new_level::text || ' (시련의 탑 입장 하한 ' || v_need::text || '). 경험치와 행동력은 백업 값.',
      '시련의 탑 최고 층 ' || v_old_best::text || ' -> ' || (v_win - 1)::text || '. 오늘 도전 횟수 0. 다른 탑은 그대로.',
      '예상 승리 층: 시련의 탑 ' || v_win::text || '층. 예상 패배 층: ' || v_lose::text || '층. 시드 7. 이 인재 1장만.',
      '버튼이 ' || v_win::text || '~' || ((((v_win - 1) / 10) * 10) + 9)::text || '층처럼 보여도 ' || v_lose::text || '층에서 멈춥니다. 예전 탭은 닫고 게임을 새로 연 뒤 소탕을 한 번만 누르세요.',
      '골드·젬·소환권·피·조각·혼은 바꾸지 않았습니다. 승리 ' || v_win::text || '층과 패배 ' || v_lose::text || '층은 영수증과 tower_paid.normal ' || v_legacy_paid::text || ' 로 이미 받은 층입니다. 서버는 그 층이 이 기준보다 높고 영수증이 없을 때만 첫 보상(골드는 50+5×층)을 줍니다.',
      '성공: 승리 층까지 최고 기록이 오르고, 같은 승리 전투를 다시 받아도 같은 정산입니다. 패배 층에서는 기록과 재화가 늘지 않습니다.',
      case
        when v_enabled is true and v_hash is not distinct from v_engine then '재계산 스위치: 켜짐. 엔진 해시가 이 파일의 계산과 같습니다.'
        when v_enabled is true then '재계산 스위치: 켜짐. 경고: 엔진 해시가 이 파일의 계산과 달라 승패가 어긋날 수 있습니다.'
        when v_enabled is false then '재계산 스위치: 꺼짐. 패배 층도 클리어될 수 있습니다. 스위치를 켠 뒤에 시험하세요.'
        else '재계산 스위치를 읽지 못했습니다. phase6 정책 표를 확인하세요.'
      end,
      '되돌리기: v_action 을 revert 로 바꾸고 이 파일을 다시 실행하세요. 시험 후에 뽑은 인재는 백업에 없습니다.'
    ];
  end if;

  insert into public.staging_sweep_fixture_report(singleton, nickname, action, report)
  values (true, v_nick, v_action, array_to_string(v_lines, E'\n'))
  on conflict (singleton) do update
    set nickname = excluded.nickname, action = excluded.action, report = excluded.report, at = now();
  foreach v_line in array v_lines loop
    raise notice '%', v_line;
  end loop;
end
$sweep_fixture$;


select nickname, action, at, report as "시험 안내"
from public.staging_sweep_fixture_report
where singleton;
