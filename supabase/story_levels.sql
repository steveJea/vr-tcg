-- =====================================================================
-- VR: Abyss Gate - 스토리 카드 레벨 + 폐기 (추가분)
-- 사용법: story.sql → gacha.sql → story_server.sql 실행 후 붙여넣고 Run. 여러 번 실행해도 안전.
-- 보유 카드(owned[]) 항목: { id, count, boost, level, exp, totalExp, cpts(카드 전용 포인트), spentCard(카드 포인트로 쓴 양), ex(합성 단계, 예정) }
-- =====================================================================

-- 1) 카드 풀에 이름·MR 추가 (뽑기는 gacha=true 인 카드만 · MR 제외 유지)
alter table public.story_card_pool add column if not exists name text;
alter table public.story_card_pool add column if not exists gacha boolean not null default true;
alter table public.story_card_pool drop constraint if exists story_card_pool_grade_check;
alter table public.story_card_pool add constraint story_card_pool_grade_check check (grade in ('NORMAL','RARE','HIGH RARE','SUPER RARE','ULTRA RARE','MYTHIC RARE','LEGENDARY RARE'));
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10118','SUPER RARE','민홍기',true),
  ('10019','RARE','강태준',true),
  ('10018','RARE','강태안',true),
  ('10299','HIGH RARE','이민수',true),
  ('10074','NORMAL','김철민',true),
  ('10080','NORMAL','김홍민',true),
  ('10445','NORMAL','한재',true),
  ('10375','NORMAL','정형준',true),
  ('10051','ULTRA RARE','김기림',true),
  ('10404','NORMAL','최강수',true),
  ('10049','NORMAL','길정재',true),
  ('10048','NORMAL','길윤재',true),
  ('10189','SUPER RARE','선우민철',true),
  ('10060','MYTHIC RARE','김성진',false),
  ('10071','NORMAL','김준하',true),
  ('10086','NORMAL','남경택',true),
  ('10169','NORMAL','사주혁',true),
  ('10137','HIGH RARE','복광준',true),
  ('10138','HIGH RARE','복광훈',true),
  ('10020','RARE','강한길',true),
  ('10463','HIGH RARE','황보재규',true),
  ('10228','RARE','안중산',true),
  ('10453','NORMAL','허재철',true),
  ('10293','RARE','윤태영',true),
  ('10010','NORMAL','강우섭',true),
  ('10380','RARE','조승규',true),
  ('10114','NORMAL','문희찬',true),
  ('10401','NORMAL','채훈기',true),
  ('10315','NORMAL','이찬열',true),
  ('10026','NORMAL','고차연',true),
  ('10191','NORMAL','선인구',true),
  ('10469','NORMAL','황준태',true),
  ('10001','NORMAL','가윤우',true),
  ('10183','SUPER RARE','서태우',true),
  ('10064','NORMAL','김자근',true),
  ('10444','NORMAL','한석열',true),
  ('10279','NORMAL','윤동훈',true),
  ('10225','RARE','안용태',true),
  ('10431','NORMAL','표정재',true),
  ('10332','NORMAL','장동만',true),
  ('10201','NORMAL','소석준',true),
  ('10346','NORMAL','전성국',true),
  ('10275','NORMAL','유형수',true),
  ('10124','RARE','박언석',true),
  ('10134','RARE','배승규',true),
  ('10037','NORMAL','구성원',true),
  ('10031','NORMAL','곽명구',true),
  ('10180','RARE','서영석',true),
  ('10390','NORMAL','주연욱',true),
  ('10027','NORMAL','고한홍',true),
  ('10033','NORMAL','곽재준',true),
  ('10353','NORMAL','전호영',true),
  ('10244','NORMAL','염상휘',true),
  ('10245','NORMAL','염태영',true),
  ('10292','HIGH RARE','윤태민',true),
  ('10076','NORMAL','김철하',true),
  ('10045','SUPER RARE','금어진',true),
  ('10409','NORMAL','최민우',true),
  ('10407','RARE','최대운',true),
  ('10036','HIGH RARE','곽태우',true),
  ('10075','NORMAL','김철중',true),
  ('10173','NORMAL','서규인',true),
  ('10406','HIGH RARE','최국선',true),
  ('10328','NORMAL','임창수',true),
  ('10329','SUPER RARE','임창열',true),
  ('10098','RARE','두윤창',true),
  ('10187','RARE','선영운',true),
  ('10319','RARE','이후남',true),
  ('10081','HIGH RARE','김후',true),
  ('10252','NORMAL','오명준',true),
  ('10298','HIGH RARE','이명진',true),
  ('10125','NORMAL','박오류',true),
  ('10025','SUPER RARE','고정태',true),
  ('10035','HIGH RARE','곽진영',true),
  ('10112','SUPER RARE','문지철',true),
  ('10270','RARE','유진산',true),
  ('10069','NORMAL','김정한',true),
  ('10088','NORMAL','남궁무열',true),
  ('10004','NORMAL','강명준',true),
  ('10420','RARE','최한길',true),
  ('10408','RARE','최두길',true),
  ('10205','HIGH RARE','송동혁',true),
  ('10139','NORMAL','복규철',true),
  ('10347','RARE','전수양',true),
  ('10023','NORMAL','고병헌',true),
  ('10448','NORMAL','허성',true),
  ('10067','SUPER RARE','김재섭',true),
  ('10005','NORMAL','강상',true),
  ('10276','RARE','유혜운',true),
  ('10259','RARE','오한음',true),
  ('10386','RARE','조한얼',true),
  ('10105','RARE','마하랑',true),
  ('10077','HIGH RARE','김한결',true),
  ('10212','NORMAL','신성진',true),
  ('10065','HIGH RARE','김재량',true),
  ('10008','NORMAL','강승헌',true),
  ('10425','HIGH RARE','탁동탁',true),
  ('10107','NORMAL','문동혁',true),
  ('10032','NORMAL','곽민수',true),
  ('10142','NORMAL','봉우람',true),
  ('10089','RARE','남궁형남',true),
  ('10094','NORMAL','노재범',true),
  ('10350','HIGH RARE','전중혁',true),
  ('10366','NORMAL','정지석',true),
  ('10016','RARE','강철하',true),
  ('10385','RARE','조주열',true),
  ('10474','NORMAL','황혁',true),
  ('10287','RARE','윤우람',true),
  ('10182','RARE','서진성',true),
  ('10136','HIGH RARE','백천주',true),
  ('10209','NORMAL','송철순',true),
  ('10170','NORMAL','사진태',true),
  ('10128','NORMAL','박태욱',true),
  ('10433','HIGH RARE','풍건',true),
  ('10374','HIGH RARE','정한서',true),
  ('10218','NORMAL','신재',true),
  ('10441','NORMAL','하혁',true),
  ('10349','RARE','전주일',true),
  ('10314','NORMAL','이진우',true),
  ('10337','NORMAL','장승헌',true),
  ('10038','NORMAL','국태원',true),
  ('10365','NORMAL','정종일',true),
  ('10278','RARE','윤남규',true),
  ('10251','NORMAL','예현승',true),
  ('10109','SUPER RARE','문재',true),
  ('10017','HIGH RARE','강철훈',true),
  ('10015','HIGH RARE','강철진',true),
  ('10028','NORMAL','공윤성',true),
  ('10181','SUPER RARE','서오성',true),
  ('10333','SUPER RARE','장무영',true),
  ('10054','ULTRA RARE','김동욱',true),
  ('10046','RARE','금유진',true),
  ('10066','NORMAL','김재민',true),
  ('10195','RARE','성재수',true),
  ('10283','NORMAL','윤석구',true),
  ('10284','RARE','윤석팔',true),
  ('10321','SUPER RARE','인창수',true),
  ('10320','NORMAL','인창민',true),
  ('10371','HIGH RARE','정태진',true),
  ('10345','RARE','전민진',true),
  ('10021','RARE','경원석',true),
  ('10424','RARE','추정욱',true),
  ('10398','RARE','진수열',true),
  ('10318','NORMAL','이호준',true),
  ('10458','RARE','황기훈',true),
  ('10464','RARE','황보훈',true),
  ('10233','NORMAL','안현',true),
  ('10034','NORMAL','곽제형',true),
  ('10171','NORMAL','서경석',true),
  ('10119','NORMAL','박미르',true),
  ('10226','RARE','안재수',true),
  ('10307','RARE','이영하',true),
  ('10402','NORMAL','천재황',true),
  ('10009','NORMAL','강신',true),
  ('10055','NORMAL','김들',true),
  ('10013','SUPER RARE','강준철',true),
  ('10313','NORMAL','이진규',true),
  ('10106','NORMAL','마형은',true),
  ('10316','NORMAL','이택길',true),
  ('10416','NORMAL','최재홍',true),
  ('10057','NORMAL','김민규',true),
  ('10220','NORMAL','신주호',true),
  ('10340','NORMAL','장제훈',true),
  ('10309','HIGH RARE','이재덕',true),
  ('10070','SUPER RARE','김준기',true),
  ('10113','NORMAL','문철재',true),
  ('10364','NORMAL','정재헌',true),
  ('10410','NORMAL','최봉근',true),
  ('10419','HIGH RARE','최진규',true),
  ('10053','ULTRA RARE','김대욱',true),
  ('10176','ULTRA RARE','서성민',true),
  ('10200','SUPER RARE','소민섭',true),
  ('10234','RARE','안호선',true),
  ('10123','HIGH RARE','박성관',true),
  ('10304','ULTRA RARE','이성호',true),
  ('10435','ULTRA RARE','하승진',true),
  ('10434','NORMAL','풍힘찬',true),
  ('10430','NORMAL','표오성',true),
  ('10379','NORMAL','제갈버들',true),
  ('10325','ULTRA RARE','임유리',true),
  ('10260','NORMAL','오희진',true),
  ('10300','RARE','이민채',true),
  ('10462','RARE','황보예',true),
  ('10072','HIGH RARE','김지수',true),
  ('10256','RARE','오유나',true),
  ('10115','RARE','민유연',true),
  ('10348','NORMAL','전잔디',true),
  ('10339','NORMAL','장은채',true),
  ('10394','HIGH RARE','지세련',true),
  ('10047','HIGH RARE','길선재',true),
  ('10188','HIGH RARE','선우민아',true),
  ('10132','RARE','배나빛',true),
  ('10087','HIGH RARE','남고은',true),
  ('10202','RARE','손란',true),
  ('10184','NORMAL','서하윤',true),
  ('10103','RARE','류하예',true),
  ('10265','RARE','용지혜',true),
  ('10266','RARE','용지효',true),
  ('10465','NORMAL','황예영',true),
  ('10466','RARE','황예은',true),
  ('10002','NORMAL','강나빛',true),
  ('10289','NORMAL','윤정하',true),
  ('10083','NORMAL','김희건',true),
  ('10079','NORMAL','김현진',true),
  ('10338','HIGH RARE','장아유',true),
  ('10336','HIGH RARE','장세유',true),
  ('10418','SUPER RARE','최지연',true),
  ('10323','ULTRA RARE','임나리',true),
  ('10403','NORMAL','천혜원',true),
  ('10185','NORMAL','선나영',true),
  ('10308','HIGH RARE','이윤이',true),
  ('10413','HIGH RARE','최윤아',true),
  ('10415','SUPER RARE','최윤희',true),
  ('10414','HIGH RARE','최윤정',true),
  ('10186','SUPER RARE','선미영',true),
  ('10295','NORMAL','윤희지',true),
  ('10297','RARE','이로하',true),
  ('10317','SUPER RARE','이혜경',true),
  ('10108','SUPER RARE','문유선',true),
  ('10417','RARE','최정인',true),
  ('10172','NORMAL','서규안',true),
  ('10262','NORMAL','온리윤',true),
  ('10261','RARE','온리연',true),
  ('10290','RARE','윤진아',true),
  ('10384','RARE','조윤하',true),
  ('10383','SUPER RARE','조윤이',true),
  ('10110','HIGH RARE','문지아',true),
  ('10442','HIGH RARE','한겨울',true),
  ('10129','RARE','박혜안',true),
  ('10014','NORMAL','강지민',true),
  ('10235','NORMAL','안희숙',true),
  ('10111','RARE','문지예',true),
  ('10357','RARE','정서영',true),
  ('10360','NORMAL','정아영',true),
  ('10306','RARE','이영아',true),
  ('10285','RARE','윤세정',true),
  ('10343','HIGH RARE','전미성',true),
  ('10271','NORMAL','유진아',true),
  ('10003','NORMAL','강리안',true),
  ('10095','RARE','노정아',true),
  ('10096','HIGH RARE','노정은',true),
  ('10342','NORMAL','장혜린',true),
  ('10327','NORMAL','임조은',true),
  ('10286','NORMAL','윤수영',true),
  ('10273','NORMAL','유태이',true),
  ('10253','NORMAL','오빛나',true),
  ('10061','SUPER RARE','김소영',true),
  ('10460','NORMAL','황다영',true),
  ('10459','NORMAL','황다미',true),
  ('10461','RARE','황다윤',true),
  ('10296','RARE','이누리',true),
  ('10246','RARE','예민지',true),
  ('10204','RARE','송다혜',true),
  ('10447','RARE','허동아',true),
  ('10429','RARE','탁희원',true),
  ('10211','NORMAL','신단비',true),
  ('10193','NORMAL','설지원',true),
  ('10120','NORMAL','박보라',true),
  ('10101','NORMAL','류하늘',true),
  ('10099','NORMAL','류장미',true),
  ('10241','RARE','양주영',true),
  ('10044','RARE','권지우',true),
  ('10043','HIGH RARE','권지아',true),
  ('10376','NORMAL','정혜원',true),
  ('10377','NORMAL','정혜진',true),
  ('10322','ULTRA RARE','임규리',true),
  ('10239','HIGH RARE','양유영',true),
  ('10039','NORMAL','권두리',true),
  ('10310','NORMAL','이제원',true),
  ('10247','NORMAL','예유나',true),
  ('10248','NORMAL','예유진',true),
  ('10221','NORMAL','신지아',true),
  ('10011','NORMAL','강유영',true),
  ('10140','NORMAL','복선아',true),
  ('10388','NORMAL','주서형',true),
  ('10121','RARE','박샘',true),
  ('10236','SUPER RARE','양겨울',true),
  ('10102','HIGH RARE','류하늬',true),
  ('10092','RARE','남소연',true),
  ('10194','RARE','설하늘',true),
  ('10361','HIGH RARE','정아윤',true),
  ('10354','SUPER RARE','정다윤',true),
  ('10254','RARE','오샘나',true),
  ('10222','RARE','심버들',true),
  ('10470','RARE','황지수',true),
  ('10059','RARE','김샛별',true),
  ('10428','NORMAL','탁세은',true),
  ('10471','NORMAL','황지은',true),
  ('10450','NORMAL','허유란',true),
  ('10432','RARE','표지아',true),
  ('10359','ULTRA RARE','정아람',true),
  ('10362','HIGH RARE','정연아',true),
  ('10454','RARE','허진서',true),
  ('10363','NORMAL','정영아',true),
  ('10436','NORMAL','하윤하',true),
  ('10412','NORMAL','최유안',true),
  ('10040','NORMAL','권예강',true),
  ('10042','RARE','권예진',true),
  ('10237','RARE','양서진',true),
  ('10207','HIGH RARE','송지아',true),
  ('10208','HIGH RARE','송지은',true),
  ('10303','NORMAL','이믿음',true),
  ('10468','NORMAL','황은채',true),
  ('10467','NORMAL','황은아',true),
  ('10294','NORMAL','윤태희',true),
  ('10258','RARE','오한설',true),
  ('10056','NORMAL','김미윤',true),
  ('10041','HIGH RARE','권예리',true),
  ('10255','SUPER RARE','오설화',true),
  ('10141','RARE','복정아',true),
  ('10133','RARE','배수연',true),
  ('10091','RARE','남다윤',true),
  ('10090','RARE','남다연',true),
  ('10344','NORMAL','전민강',true),
  ('10330','NORMAL','임한빈',true),
  ('10263','NORMAL','온유진',true),
  ('10249','NORMAL','예은아',true),
  ('10063','NORMAL','김예빈',true),
  ('10052','SUPER RARE','김나현',true),
  ('10190','NORMAL','선유린',true),
  ('10174','NORMAL','서미나',true),
  ('10122','NORMAL','박설이',true),
  ('10029','RARE','공주연',true),
  ('10232','NORMAL','안태영',true),
  ('10104','RARE','류햇빛',true),
  ('10378','RARE','제갈민영',true),
  ('10126','HIGH RARE','박인아',true),
  ('10062','MYTHIC RARE','김신현',false),
  ('10203','HIGH RARE','손혜연',true),
  ('10097','RARE','동지선',true),
  ('10280','NORMAL','윤미리내',true),
  ('10352','NORMAL','전하나',true),
  ('10277','NORMAL','유혜윰',true),
  ('10100','NORMAL','류태연',true),
  ('10451','NORMAL','허유리',true),
  ('10389','NORMAL','주슬기',true),
  ('10264','NORMAL','왕유영',true),
  ('10438','NORMAL','하지연',true),
  ('10177','NORMAL','서아란',true),
  ('10178','NORMAL','서아리',true),
  ('10372','RARE','정하나',true),
  ('10373','SUPER RARE','정하루',true),
  ('10130','NORMAL','반지아',true),
  ('10131','HIGH RARE','반지윤',true),
  ('10341','SUPER RARE','장초롱',true),
  ('10272','NORMAL','유진이',true),
  ('10117','SUPER RARE','민지은',true),
  ('10078','HIGH RARE','김한별',true),
  ('10084','NORMAL','나윤아',true),
  ('10085','NORMAL','나윤영',true),
  ('10217','SUPER RARE','신예은',true),
  ('10216','SUPER RARE','신아은',true),
  ('10324','ULTRA RARE','임예리',true),
  ('10006','NORMAL','강서언',true),
  ('10068','SUPER RARE','김재신',true),
  ('10400','HIGH RARE','채예린',true),
  ('10331','ULTRA RARE','임혜리',true),
  ('10250','NORMAL','예햇빛',true),
  ('10022','NORMAL','고명희',true),
  ('10437','RARE','하장미',true),
  ('10426','RARE','탁동혜',true),
  ('10381','NORMAL','조아린',true),
  ('10179','NORMAL','서애정',true),
  ('10215','NORMAL','신아윤',true),
  ('10214','HIGH RARE','신아린',true),
  ('10223','NORMAL','안다미',true),
  ('10269','SUPER RARE','유아리',true),
  ('10268','HIGH RARE','유나리',true),
  ('10473','HIGH RARE','황한결',true),
  ('10135','RARE','백버들',true),
  ('10206','NORMAL','송예빈',true),
  ('10240','HIGH RARE','양제림',true),
  ('10238','NORMAL','양소영',true),
  ('10230','RARE','안지연',true),
  ('10227','RARE','안주연',true),
  ('10387','NORMAL','주서영',true),
  ('10281','SUPER RARE','윤믿음',true),
  ('10472','NORMAL','황진',true),
  ('10455','RARE','홍가영',true),
  ('10423','NORMAL','추나리',true),
  ('10456','NORMAL','홍나영',true),
  ('10457','HIGH RARE','홍다영',true),
  ('10224','RARE','안리',true),
  ('10382','NORMAL','조영애',true),
  ('10393','HIGH RARE','주예서',true),
  ('10030','NORMAL','공태인',true),
  ('10391','RARE','주예나',true),
  ('10392','SUPER RARE','주예린',true),
  ('10311','MYTHIC RARE','이지영',false),
  ('10397','RARE','진교진',true),
  ('10242','RARE','양지림',true),
  ('10356','NORMAL','정새론',true),
  ('10274','NORMAL','유한결',true),
  ('10192','NORMAL','설달',true),
  ('10093','NORMAL','남태은',true),
  ('10312','ULTRA RARE','이진경',true),
  ('10243','NORMAL','연재은',true),
  ('10231','HIGH RARE','안지윤',true),
  ('10399','SUPER RARE','진하린',true),
  ('10050','NORMAL','김가람',true),
  ('10073','HIGH RARE','김지우',true),
  ('10229','HIGH RARE','안지수',true),
  ('10012','NORMAL','강재아',true),
  ('10219','NORMAL','신주원',true),
  ('10305','NORMAL','이소진',true),
  ('10443','NORMAL','한믿음',true),
  ('10024','SUPER RARE','고세린',true),
  ('10446','NORMAL','한하루',true),
  ('10427','NORMAL','탁리',true),
  ('10411','NORMAL','최여진',true),
  ('10058','ULTRA RARE','김백중',true),
  ('10395','NORMAL','지유현',true),
  ('10213','SUPER RARE','신시은',true),
  ('10175','RARE','서민아',true),
  ('10007','RARE','강세연',true),
  ('10257','HIGH RARE','오채원',true),
  ('10291','ULTRA RARE','[각성] 윤진아',true),
  ('10326','MYTHIC RARE','[각성] 임유리',false),
  ('10288','HIGH RARE','윤은별',true),
  ('10282','NORMAL','윤샛별',true),
  ('10405','RARE','최겨울',true),
  ('10452','HIGH RARE','허유희',true),
  ('10370','RARE','정치환',true),
  ('10368','RARE','정치성',true),
  ('10369','SUPER RARE','정치욱',true),
  ('10358','ULTRA RARE','정석윤',true),
  ('10351','NORMAL','전필수',true),
  ('10449','NORMAL','허요한',true),
  ('10422','NORMAL','최훈필',true),
  ('10421','NORMAL','최훈남',true),
  ('10396','NORMAL','지주현',true)
on conflict (id) do update set grade = excluded.grade, name = excluded.name, gacha = excluded.gacha;

-- 2) 페이즈별 적 수 (처치 수 상한 검증용)
alter table public.story_phase_config add column if not exists enemy_count int not null default 1;
update public.story_phase_config set enemy_count = v.n from (values (1,1,1),(1,2,2),(1,3,2),(1,4,3),(1,5,4)) v(c,p,n) where chapter = v.c and phase = v.p;

-- 3) 레벨 규칙
-- 최대 레벨: N 20 / R 30 / HR 40 / SR 50 / UR 60 / MR 70. ex(합성 단계)마다 +10 (EX 합성용 훅)
create or replace function public._story_cap(g text, ex int default 0) returns int language sql immutable as $$
  select (case g when 'NORMAL' then 20 when 'RARE' then 30 when 'HIGH RARE' then 40 when 'SUPER RARE' then 50 when 'ULTRA RARE' then 60 when 'MYTHIC RARE' then 70 else 20 end) + 10 * greatest(0, coalesce(ex, 0))
$$;
-- 폐기 기본 EXP (등급만)
create or replace function public._story_feed_exp(g text) returns int language sql immutable as $$
  select case g when 'NORMAL' then 50 when 'RARE' then 150 when 'HIGH RARE' then 400 when 'SUPER RARE' then 1000 when 'ULTRA RARE' then 3000 when 'MYTHIC RARE' then 6000 else 50 end
$$;
-- 기본값 채우기
create or replace function public._story_norm(e jsonb) returns jsonb language sql immutable as $$
  select e || jsonb_build_object(
    'count', greatest(1, coalesce((e->>'count')::int, 1)), 'boost', coalesce(e->'boost', '{}'::jsonb),
    'level', greatest(1, coalesce((e->>'level')::int, 1)), 'exp', greatest(0, coalesce((e->>'exp')::int, 0)),
    'totalExp', greatest(0, coalesce((e->>'totalExp')::int, 0)), 'cpts', greatest(0, coalesce((e->>'cpts')::int, 0)),
    'spentCard', greatest(0, coalesce((e->>'spentCard')::int, 0)))
$$;
-- EXP 획득: 다음 레벨 필요 EXP = 레벨 × 100, 레벨업마다 그 카드 전용 포인트 +1, 최대 레벨 초과분은 버림
create or replace function public._story_gain(e jsonb, amt int, g text) returns jsonb language plpgsql immutable as $$
declare lv int; ex int; tot int; cap int; got int := 0;
begin
  e := _story_norm(e);
  lv := (e->>'level')::int; ex := (e->>'exp')::int; cap := _story_cap(g, (e->>'ex')::int);
  if lv >= cap then return e || jsonb_build_object('exp', 0); end if;
  ex := ex + greatest(0, amt);
  tot := (e->>'totalExp')::int;
  while lv < cap and ex >= lv * 100 loop ex := ex - lv * 100; lv := lv + 1; got := got + 1; end loop;
  if lv >= cap then tot := tot + greatest(0, amt) - ex; ex := 0; else tot := tot + greatest(0, amt); end if;
  return e || jsonb_build_object('level', lv, 'exp', ex, 'totalExp', tot, 'cpts', (e->>'cpts')::int + got);
end $$;

-- 4) 전역 포인트 사용량 = 강화 합계 − 카드 전용 포인트로 쓴 양
create or replace function public._story_used(d jsonb) returns int language sql immutable as $$
  select coalesce(sum(greatest(0, coalesce((o->'boost'->>'ATK')::int,0)) + greatest(0, coalesce((o->'boost'->>'HP')::int,0)) + greatest(0, coalesce((o->'boost'->>'DEF')::int,0)) - greatest(0, coalesce((o->>'spentCard')::int, 0))), 0)::int
  from jsonb_array_elements(case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end) o
$$;

-- 5) 페이즈 클리어 + 전투 EXP. p_stats = [{"id":"카드id","kills":n}, ...] (이번 전투에 낸 내 카드)
--    EXP = (60 + 20 × 처치) × (보스 2배). 보유 카드만, 중복 제외, 처치 합계 ≤ 페이즈 적 수. 재클리어도 EXP는 지급(첫 클리어 보상은 없음)
create or replace function public.story_complete_phase(p_chapter int, p_phase int, p_stats jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; cfg story_phase_config; b jsonb; cl jsonb; first boolean; rid text; owned jsonb;
        st jsonb; idx int; k int; ksum int := 0; gain int; g text; before int; res jsonb := '[]'::jsonb; seen text[] := '{}';
begin
  select * into cfg from story_phase_config where chapter = p_chapter and phase = p_phase;
  if cfg is null then raise exception 'invalid phase'; end if;
  d := _story_lock(uid);
  b := d->'battle';
  if b is null or (b->>'chapter')::int <> p_chapter or (b->>'phase')::int <> p_phase then raise exception 'battle not started'; end if;
  if extract(epoch from clock_timestamp()) - (b->>'at')::bigint < _story_min_battle_secs() then raise exception 'too fast'; end if;
  d := d - 'battle';
  cl := coalesce(d->'cleared'->(p_chapter::text), '[]'::jsonb);
  first := not cl @> to_jsonb(p_phase);
  if first then
    if d->'cleared' is null or jsonb_typeof(d->'cleared') <> 'object' then d := jsonb_set(d, '{cleared}', '{}'::jsonb); end if;
    d := jsonb_set(d, array['cleared', p_chapter::text], cl || to_jsonb(p_phase));
    d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + cfg.points));
    if cfg.reward_grade is not null then
      owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
      select p.id into rid from story_card_pool p
        where p.grade = cfg.reward_grade and p.gacha and not exists (select 1 from jsonb_array_elements(owned) o where o->>'id' = p.id)
        order by random() limit 1;
      if rid is not null then d := jsonb_set(d, '{owned}', owned || jsonb_build_array(jsonb_build_object('id', rid, 'boost', '{}'::jsonb, 'count', 1, 'level', 1, 'exp', 0))); end if;
    end if;
  end if;
  -- 전투 EXP
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  if jsonb_typeof(p_stats) = 'array' and jsonb_array_length(p_stats) <= 30 then
    for st in select * from jsonb_array_elements(p_stats) loop
      continue when jsonb_typeof(st) <> 'object' or (st->>'id') is null or (st->>'id') = any(seen) or (st->>'id') = rid;
      select i - 1 into idx from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = st->>'id' limit 1;
      continue when idx is null;
      seen := seen || (st->>'id');
      k := least(greatest(0, coalesce((st->>'kills')::int, 0)), greatest(0, cfg.enemy_count - ksum));
      ksum := ksum + k;
      gain := (60 + 20 * k) * (case when cfg.type = 'boss' then 2 else 1 end);
      select grade into g from story_card_pool where id = st->>'id';
      before := coalesce((owned->idx->>'level')::int, 1);
      owned := jsonb_set(owned, array[idx::text], _story_gain(owned->idx, gain, coalesce(g, 'NORMAL')));
      res := res || jsonb_build_object('id', st->>'id', 'kills', k, 'exp', gain, 'from', before, 'level', (owned->idx->>'level')::int);
    end loop;
    d := jsonb_set(d, '{owned}', owned);
  end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'first', first, 'points', case when first then cfg.points else 0 end, 'reward_id', rid, 'exp', res);
end $$;
-- 예전 클라이언트용 (EXP 없이)
create or replace function public.story_complete_phase(p_chapter int, p_phase int) returns jsonb language sql security definer set search_path = public as $$
  select public.story_complete_phase(p_chapter, p_phase, '[]'::jsonb)
$$;

-- 6) 스탯 분배: 카드 전용 포인트(cpts) 먼저, 모자라면 전역 포인트에서
create or replace function public.story_allocate(p_alloc jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; k text; v jsonb; s text; n int; total int; gtotal int := 0; idx int; pts int; cp int; fromCard int;
begin
  if jsonb_typeof(p_alloc) <> 'object' then raise exception 'invalid alloc'; end if;
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  pts := greatest(0, coalesce((d->>'points')::int, 0));
  for k, v in select * from jsonb_each(p_alloc) loop
    select i - 1 into idx from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = k limit 1;
    if idx is null then raise exception 'card not owned'; end if;
    if jsonb_typeof(v) <> 'object' then raise exception 'invalid alloc'; end if;
    owned := jsonb_set(owned, array[idx::text], _story_norm(owned->idx));
    total := 0;
    for s in select jsonb_object_keys(v) loop
      if s not in ('ATK', 'HP', 'DEF') then raise exception 'invalid stat'; end if;
      if jsonb_typeof(v->s) <> 'number' then raise exception 'invalid amount'; end if;
      n := (v->>s)::int;
      if n < 0 or n::text <> (v->>s) then raise exception 'invalid amount'; end if;
      total := total + n;
      owned := jsonb_set(owned, array[idx::text, 'boost'], coalesce(owned->idx->'boost', '{}'::jsonb) || jsonb_build_object(s, coalesce((owned->idx->'boost'->>s)::int, 0) + n));
    end loop;
    cp := (owned->idx->>'cpts')::int;
    fromCard := least(cp, total);
    gtotal := gtotal + (total - fromCard);
    owned := jsonb_set(owned, array[idx::text], owned->idx || jsonb_build_object('cpts', cp - fromCard, 'spentCard', (owned->idx->>'spentCard')::int + fromCard));
  end loop;
  if gtotal > pts then raise exception 'not enough points'; end if;
  d := jsonb_set(jsonb_set(d, '{owned}', owned), '{points}', to_jsonb(pts - gtotal));
  return _story_save(uid, d);
end $$;

-- 7) 폐기: p_id 카드 1장을 없애고 p_target 카드에 EXP.
--    EXP = 등급 기본값 × (같은 이름이면 1.5) + (그 항목이 통째로 없어질 때) 누적 EXP의 50%
--    중복(count>1)이면 사본 1장만 소모(레벨·강화는 남은 카드에 유지). 마지막 1장이면 항목 제거 + 전역 포인트로 강화한 만큼 돌려줌
--    리더(시작 카드)는 마지막 1장을 폐기할 수 없음. 대상 자신(마지막 1장)도 불가
create or replace function public.story_discard(p_id text, p_target text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb; owned jsonb; i1 int; i2 int; e1 jsonb; c1 int; g1 text; n1 text; g2 text; n2 text; amt int; whole boolean; refund int := 0; before int; t jsonb;
begin
  d := _story_lock(uid);
  owned := case when jsonb_typeof(d->'owned') = 'array' then d->'owned' else '[]'::jsonb end;
  select i - 1 into i1 from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = p_id limit 1;
  select i - 1 into i2 from jsonb_array_elements(owned) with ordinality t(e, i) where t.e->>'id' = p_target limit 1;
  if i1 is null or i2 is null then raise exception 'card not owned'; end if;
  e1 := _story_norm(owned->i1); c1 := (e1->>'count')::int; whole := c1 <= 1;
  if whole and p_id = coalesce(d->>'starter', '') then raise exception 'cannot discard leader'; end if;
  if whole and p_id = p_target then raise exception 'cannot discard target'; end if;
  select grade, name into g1, n1 from story_card_pool where id = p_id;
  select grade, name into g2, n2 from story_card_pool where id = p_target;
  amt := _story_feed_exp(coalesce(g1, 'NORMAL'));
  if n1 is not null and n1 = n2 then amt := floor(amt * 1.5); end if;
  if whole then
    amt := amt + floor((e1->>'totalExp')::int * 0.5);
    refund := greatest(0, coalesce((e1->'boost'->>'ATK')::int,0) + coalesce((e1->'boost'->>'HP')::int,0) + coalesce((e1->'boost'->>'DEF')::int,0) - (e1->>'spentCard')::int);
  end if;
  before := coalesce((owned->i2->>'level')::int, 1);
  t := _story_gain(owned->i2, amt, coalesce(g2, 'NORMAL'));
  owned := jsonb_set(owned, array[i2::text], t);
  if whole then owned := owned - i1;
  else owned := jsonb_set(owned, array[i1::text, 'count'], to_jsonb(c1 - 1)); end if;
  d := jsonb_set(d, '{owned}', owned);
  if refund > 0 then d := jsonb_set(d, '{points}', to_jsonb(coalesce((d->>'points')::int, 0) + refund)); end if;
  d := _story_save(uid, d);
  return jsonb_build_object('data', d, 'exp', amt, 'from', before, 'level', (t->>'level')::int, 'refund', refund);
end $$;

revoke all on function public._story_cap(text, int), public._story_feed_exp(text), public._story_norm(jsonb), public._story_gain(jsonb, int, text), public._story_used(jsonb) from public, anon, authenticated;
revoke all on function public.story_complete_phase(int, int, jsonb), public.story_complete_phase(int, int), public.story_allocate(jsonb), public.story_discard(text, text) from public, anon;
grant execute on function public.story_complete_phase(int, int, jsonb), public.story_complete_phase(int, int), public.story_allocate(jsonb), public.story_discard(text, text) to authenticated;

-- 8) 기존 데이터: 보유 카드에 레벨 기본값 채우기 (기존 강화는 전역 포인트로 쓴 것으로 간주)
update public.story_progress sp set data = jsonb_set(sp.data, '{owned}', (select coalesce(jsonb_agg(public._story_norm(o) order by n), '[]'::jsonb) from jsonb_array_elements(sp.data->'owned') with ordinality x(o, n)))
  where jsonb_typeof(sp.data->'owned') = 'array';
