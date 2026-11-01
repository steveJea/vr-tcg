-- 파견 (배척지 001~009 · 안전지대 B~SS). 선행: phaseE_1/2(지갑·플레이어 레벨) · gem.sql · gacha.sql(story_gacha.tickets) · trade_drink.sql(_item_add). 여러 번 실행해도 안전.
-- 규칙 요약
--  * 매일 0시(KST) 의뢰 6개(배척지 4 · 안전지대 2) 무작위. 새로고침: 하루 3번 무료 → 심연석 20/30/40/50(이후 50)
--  * 필수 = 등급만(보낸 카드 중 1장 이상이 그 등급 이상). 속성·클래스 맞는 카드 1장당 +15%(속성·클래스 따로, 최대 +60%), 필수보다 높은 등급 카드 있으면 +10%
--  * 보너스 최대(+60%)면 10% 확률 대성공(보상 2배). 보상·확률·종료 시각은 출발할 때 서버가 정해 둠
--  * 시간 1/4/8/12시간 = 1시간 보상 × 1 / 3.5 / 6 / 8.5
--  * 동시 진행 슬롯: 플레이어 Lv1~29 = 3, 30~59 = 4, 60~ = 5. 하루 출발 최대 12번
--  * 한 카드(uid)는 진행 중인 파견 하나에만. 덱·스토리·PvP 사용은 막지 않음. MR·LR 카드는 아직 파견 불가

-- 1) 카드 정보 (등급 0=N 1=R 2=HR 3=SR 4=UR 5=MR 6=LR · 속성 · 클래스). data/cards.csv · npc_cards.csv 에서 생성
create table if not exists public.dispatch_card_meta (id text primary key, grade int not null, el text not null, cls text not null);
alter table public.dispatch_card_meta enable row level security;
drop policy if exists dispatch_card_meta_read on public.dispatch_card_meta;
create policy dispatch_card_meta_read on public.dispatch_card_meta for select using (true);
insert into public.dispatch_card_meta (id, grade, el, cls) values
('10001',0,'WIND','CHARGE'),
('10002',0,'WIND','CHARGE'),
('10003',0,'FIRE','CHARGE'),
('10004',0,'WIND','DEFENSE'),
('10005',0,'WIND','DEFENSE'),
('10006',0,'FIRE','SUPPORT'),
('10007',1,'WIND','DEFENSE'),
('10008',0,'WIND','CHARGE'),
('10009',0,'WIND','CHARGE'),
('10010',0,'FIRE','CHARGE'),
('10011',0,'WIND','CHARGE'),
('10012',0,'WIND','CHARGE'),
('10013',3,'FIRE','CHARGE'),
('10014',0,'FIRE','CHARGE'),
('10015',2,'ICE','CRUSH'),
('10016',1,'WIND','CHARGE'),
('10017',2,'FIRE','CHARGE'),
('10018',1,'WIND','CHARGE'),
('10019',1,'FIRE','CRUSH'),
('10020',1,'FIRE','CHARGE'),
('10021',1,'WIND','CHARGE'),
('10022',0,'FIRE','DEFENSE'),
('10023',0,'WIND','DEFENSE'),
('10024',3,'ICE','DEFENSE'),
('10025',3,'FIRE','DISTURB'),
('10026',0,'FIRE','CHARGE'),
('10027',0,'ICE','CHARGE'),
('10028',0,'WIND','CHARGE'),
('10029',1,'FIRE','CHARGE'),
('10030',0,'WIND','CHARGE'),
('10031',0,'ICE','DEFENSE'),
('10032',0,'WIND','CHARGE'),
('10033',0,'FIRE','CHARGE'),
('10034',0,'WIND','CHARGE'),
('10035',2,'ICE','CHARGE'),
('10036',2,'WIND','CRUSH'),
('10037',0,'FIRE','CHARGE'),
('10038',0,'WIND','CHARGE'),
('10039',0,'WIND','FASCINATION'),
('10040',0,'FIRE','DEFENSE'),
('10041',2,'WIND','CRUSH'),
('10042',1,'WIND','CRUSH'),
('10043',2,'WIND','CRUSH'),
('10044',1,'WIND','CHARGE'),
('10045',3,'ICE','CHARGE'),
('10046',1,'WIND','CRUSH'),
('10047',2,'WIND','CRUSH'),
('10048',0,'WIND','CHARGE'),
('10049',0,'ICE','DEFENSE'),
('10050',0,'FIRE','DEFENSE'),
('10051',4,'FIRE','CHARGE'),
('10052',3,'DARK','DISTURB'),
('10053',4,'DARK','OVERWHELMING'),
('10054',4,'DARK','OVERWHELMING'),
('10055',0,'WIND','CHARGE'),
('10056',0,'WIND','DEFENSE'),
('10057',0,'WIND','CHARGE'),
('10058',4,'FIRE','CRUSH'),
('10059',1,'DARK','DISTURB'),
('10060',5,'ABYSS','FURIOUS'),
('10061',3,'ICE','CRUSH'),
('10062',5,'ABYSS','PHENOMENAL'),
('10063',0,'ICE','DEFENSE'),
('10064',0,'WIND','DEFENSE'),
('10065',2,'ICE','CHARGE'),
('10066',0,'WIND','CHARGE'),
('10067',3,'FIRE','CRUSH'),
('10068',3,'DARK','CRUSH'),
('10069',0,'ICE','CHARGE'),
('10070',3,'ICE','CHARGE'),
('10071',0,'WIND','CHARGE'),
('10072',2,'DARK','DISTURB'),
('10073',2,'LIGHT','SUPPORT'),
('10074',0,'WIND','DEFENSE'),
('10075',0,'WIND','CHARGE'),
('10076',0,'ICE','CHARGE'),
('10077',2,'ICE','CRUSH'),
('10078',2,'FIRE','FASCINATION'),
('10079',0,'FIRE','DEFENSE'),
('10080',0,'WIND','DEFENSE'),
('10081',2,'WIND','DISTURB'),
('10082',2,'WIND','DEFENSE'),
('10083',0,'WIND','CHARGE'),
('10084',0,'FIRE','CHARGE'),
('10085',0,'FIRE','CHARGE'),
('10086',0,'WIND','CHARGE'),
('10087',2,'ICE','CRUSH'),
('10088',0,'FIRE','CHARGE'),
('10089',1,'WIND','CHARGE'),
('10090',1,'ICE','FASCINATION'),
('10091',1,'DARK','DISTURB'),
('10092',1,'WIND','CHARGE'),
('10093',0,'WIND','CHARGE'),
('10094',0,'WIND','CHARGE'),
('10095',1,'FIRE','CRUSH'),
('10096',2,'ICE','CRUSH'),
('10097',1,'WIND','DEFENSE'),
('10098',1,'FIRE','CHARGE'),
('10099',0,'WIND','CHARGE'),
('10100',0,'FIRE','CHARGE'),
('10101',0,'WIND','CHARGE'),
('10102',2,'WIND','DISTURB'),
('10103',1,'DARK','SUPPORT'),
('10104',1,'WIND','CRUSH'),
('10105',1,'FIRE','CHARGE'),
('10106',0,'ICE','CHARGE'),
('10107',0,'WIND','CHARGE'),
('10108',3,'LIGHT','SUPPORT'),
('10109',3,'FIRE','CHARGE'),
('10110',2,'FIRE','CRUSH'),
('10111',1,'FIRE','SUPPORT'),
('10112',3,'FIRE','CHARGE'),
('10113',0,'ICE','DEFENSE'),
('10114',0,'WIND','CHARGE'),
('10115',1,'WIND','SUPPORT'),
('10116',3,'FIRE','CRUSH'),
('10117',3,'FIRE','CHARGE'),
('10118',3,'FIRE','CHARGE'),
('10119',0,'ICE','DEFENSE'),
('10120',0,'FIRE','CHARGE'),
('10121',1,'WIND','DISTURB'),
('10122',0,'ICE','CHARGE'),
('10123',2,'FIRE','DEFENSE'),
('10124',1,'WIND','CHARGE'),
('10125',0,'FIRE','CHARGE'),
('10126',2,'WIND','CRUSH'),
('10127',3,'LIGHT','CHARGE'),
('10128',0,'FIRE','CHARGE'),
('10129',1,'WIND','SUPPORT'),
('10130',0,'WIND','DEFENSE'),
('10131',2,'DARK','DISTURB'),
('10132',1,'WIND','FASCINATION'),
('10133',1,'WIND','CHARGE'),
('10134',1,'WIND','CHARGE'),
('10135',1,'DARK','SUPPORT'),
('10136',2,'ICE','CHARGE'),
('10137',2,'ICE','CHARGE'),
('10138',2,'WIND','DISTURB'),
('10139',0,'WIND','CHARGE'),
('10140',0,'WIND','CHARGE'),
('10141',1,'WIND','CRUSH'),
('10142',0,'ICE','CHARGE'),
('10143',0,'FIRE','CHARGE'),
('10144',0,'WIND','CHARGE'),
('10145',0,'ICE','CHARGE'),
('10146',0,'FIRE','DEFENSE'),
('10147',0,'WIND','DEFENSE'),
('10148',1,'ICE','DEFENSE'),
('10149',1,'FIRE','DEFENSE'),
('10150',1,'WIND','CRUSH'),
('10151',2,'ICE','CRUSH'),
('10152',2,'FIRE','CRUSH'),
('10153',0,'WIND','CHARGE'),
('10154',0,'ICE','CHARGE'),
('10155',0,'FIRE','DEFENSE'),
('10156',0,'WIND','DEFENSE'),
('10157',0,'ICE','DEFENSE'),
('10158',0,'FIRE','DEFENSE'),
('10159',1,'WIND','CRUSH'),
('10160',1,'ICE','CRUSH'),
('10161',1,'FIRE','CRUSH'),
('10162',1,'WIND','CHARGE'),
('10163',2,'ICE','CHARGE'),
('10164',2,'FIRE','DEFENSE'),
('10165',2,'WIND','DEFENSE'),
('10166',2,'DARK','SUPPORT'),
('10167',2,'DARK','SUPPORT'),
('10168',2,'DARK','DISTURB'),
('10169',0,'WIND','DEFENSE'),
('10170',0,'FIRE','CHARGE'),
('10171',0,'FIRE','CHARGE'),
('10172',0,'FIRE','CHARGE'),
('10173',0,'WIND','CHARGE'),
('10174',0,'WIND','CHARGE'),
('10175',1,'WIND','CHARGE'),
('10176',4,'LIGHT','SUPPORT'),
('10177',0,'WIND','CHARGE'),
('10178',0,'ICE','CHARGE'),
('10179',0,'WIND','CHARGE'),
('10180',1,'ICE','DEFENSE'),
('10181',3,'WIND','CRUSH'),
('10182',1,'DARK','DISTURB'),
('10183',3,'ICE','CRUSH'),
('10184',0,'WIND','DEFENSE'),
('10185',0,'FIRE','CHARGE'),
('10186',3,'ICE','DISTURB'),
('10187',1,'FIRE','DEFENSE'),
('10188',2,'WIND','CHARGE'),
('10189',3,'FIRE','DEFENSE'),
('10190',0,'FIRE','FASCINATION'),
('10191',0,'ICE','DEFENSE'),
('10192',0,'FIRE','CHARGE'),
('10193',0,'ICE','DEFENSE'),
('10194',1,'WIND','CRUSH'),
('10195',1,'ICE','CRUSH'),
('10196',0,'WIND','CHARGE'),
('10197',0,'WIND','CHARGE'),
('10198',0,'WIND','CHARGE'),
('10199',1,'WIND','CHARGE'),
('10200',3,'DARK','CRUSH'),
('10201',0,'WIND','DEFENSE'),
('10202',1,'FIRE','CHARGE'),
('10203',2,'LIGHT','SUPPORT'),
('10204',1,'WIND','CHARGE'),
('10205',2,'ICE','CRUSH'),
('10206',0,'ICE','DEFENSE'),
('10207',2,'ICE','DISTURB'),
('10208',2,'DARK','CRUSH'),
('10209',0,'ICE','CHARGE'),
('10210',2,'WIND','CHARGE'),
('10211',0,'WIND','DEFENSE'),
('10212',0,'WIND','DEFENSE'),
('10213',3,'FIRE','DISTURB'),
('10214',2,'FIRE','CHARGE'),
('10215',0,'FIRE','DEFENSE'),
('10216',3,'DARK','FASCINATION'),
('10217',3,'DARK','DISTURB'),
('10218',0,'FIRE','CHARGE'),
('10219',0,'DARK','DEFENSE'),
('10220',0,'FIRE','CHARGE'),
('10221',0,'FIRE','CHARGE'),
('10222',1,'WIND','CHARGE'),
('10223',0,'WIND','DEFENSE'),
('10224',1,'WIND','CRUSH'),
('10225',1,'FIRE','CHARGE'),
('10226',1,'WIND','SUPPORT'),
('10227',1,'WIND','CHARGE'),
('10228',1,'FIRE','DEFENSE'),
('10229',2,'FIRE','CHARGE'),
('10230',1,'WIND','CRUSH'),
('10231',2,'LIGHT','DISTURB'),
('10232',0,'WIND','DEFENSE'),
('10233',0,'FIRE','CHARGE'),
('10234',1,'FIRE','CHARGE'),
('10235',0,'ICE','CHARGE'),
('10236',3,'FIRE','CRUSH'),
('10237',1,'ICE','CHARGE'),
('10238',0,'WIND','DEFENSE'),
('10239',2,'WIND','CHARGE'),
('10240',2,'WIND','CHARGE'),
('10241',1,'WIND','SUPPORT'),
('10242',1,'WIND','DISTURB'),
('10243',0,'ICE','CHARGE'),
('10244',0,'FIRE','CHARGE'),
('10245',0,'WIND','DEFENSE'),
('10246',1,'WIND','CHARGE'),
('10247',0,'ICE','DEFENSE'),
('10248',0,'WIND','DEFENSE'),
('10249',0,'FIRE','CHARGE'),
('10250',0,'WIND','CHARGE'),
('10251',0,'FIRE','CHARGE'),
('10252',0,'ICE','CHARGE'),
('10253',0,'FIRE','CHARGE'),
('10254',1,'WIND','CHARGE'),
('10255',3,'ICE','CRUSH'),
('10256',1,'DARK','SUPPORT'),
('10257',2,'ICE','SUPPORT'),
('10258',1,'WIND','SUPPORT'),
('10259',1,'ICE','CHARGE'),
('10260',0,'ICE','CHARGE'),
('10261',1,'WIND','SUPPORT'),
('10262',0,'WIND','DEFENSE'),
('10263',0,'FIRE','CHARGE'),
('10264',0,'ICE','CHARGE'),
('10265',1,'WIND','CHARGE'),
('10266',1,'WIND','SUPPORT'),
('10267',2,'ICE','DEFENSE'),
('10268',2,'WIND','DEFENSE'),
('10269',3,'WIND','CRUSH'),
('10270',1,'FIRE','CRUSH'),
('10271',0,'WIND','CHARGE'),
('10272',0,'WIND','CHARGE'),
('10273',0,'WIND','CHARGE'),
('10274',0,'WIND','CHARGE'),
('10275',0,'ICE','CHARGE'),
('10276',1,'WIND','CHARGE'),
('10277',0,'WIND','CHARGE'),
('10278',1,'WIND','CHARGE'),
('10279',0,'WIND','CHARGE'),
('10280',0,'ICE','CHARGE'),
('10281',3,'WIND','CRUSH'),
('10282',0,'ICE','CHARGE'),
('10283',0,'FIRE','CHARGE'),
('10284',1,'FIRE','CHARGE'),
('10285',1,'WIND','DEFENSE'),
('10286',0,'WIND','DEFENSE'),
('10287',1,'FIRE','CRUSH'),
('10288',2,'FIRE','CHARGE'),
('10289',0,'WIND','CHARGE'),
('10290',1,'LIGHT','SUPPORT'),
('10291',4,'DARK','CHARGE'),
('10292',2,'WIND','CHARGE'),
('10293',1,'FIRE','CHARGE'),
('10294',0,'WIND','CHARGE'),
('10295',0,'WIND','CHARGE'),
('10296',1,'WIND','CHARGE'),
('10297',1,'WIND','SUPPORT'),
('10298',2,'FIRE','CRUSH'),
('10299',2,'ICE','DEFENSE'),
('10300',1,'DARK','SUPPORT'),
('10301',3,'DARK','CRUSH'),
('10302',1,'WIND','DISTURB'),
('10303',0,'WIND','DEFENSE'),
('10304',4,'DARK','CRUSH'),
('10305',0,'FIRE','CHARGE'),
('10306',1,'WIND','SUPPORT'),
('10307',1,'ICE','CHARGE'),
('10308',2,'ICE','SUPPORT'),
('10309',2,'FIRE','CRUSH'),
('10310',0,'WIND','SUPPORT'),
('10311',5,'ABYSS','EXTERMINATE'),
('10312',4,'DARK','DISTURB'),
('10313',0,'WIND','DEFENSE'),
('10314',0,'WIND','CHARGE'),
('10315',0,'FIRE','DEFENSE'),
('10316',0,'WIND','DEFENSE'),
('10317',3,'ICE','FASCINATION'),
('10318',0,'WIND','CHARGE'),
('10319',1,'FIRE','CRUSH'),
('10320',0,'FIRE','CHARGE'),
('10321',3,'DARK','CRUSH'),
('10322',4,'ICE','CRUSH'),
('10323',4,'FIRE','CRUSH'),
('10324',4,'DARK','DISTURB'),
('10325',4,'DARK','FASCINATION'),
('10326',5,'DARK','FASCINATION'),
('10327',0,'ICE','DEFENSE'),
('10328',0,'FIRE','CHARGE'),
('10329',3,'WIND','CHARGE'),
('10330',0,'ICE','DEFENSE'),
('10331',4,'LIGHT','SUPPORT'),
('10332',0,'ICE','CHARGE'),
('10333',3,'FIRE','CHARGE'),
('10334',6,'VOID','UNLIMITED'),
('10335',5,'ABYSS','BALANCE'),
('10336',2,'WIND','CHARGE'),
('10337',0,'ICE','CHARGE'),
('10338',2,'WIND','CRUSH'),
('10339',0,'ICE','CHARGE'),
('10340',0,'FIRE','CHARGE'),
('10341',3,'ICE','CRUSH'),
('10342',0,'WIND','CHARGE'),
('10343',2,'FIRE','DISTURB'),
('10344',0,'ICE','CHARGE'),
('10345',1,'FIRE','CHARGE'),
('10346',0,'WIND','CHARGE'),
('10347',1,'ICE','CRUSH'),
('10348',0,'ICE','CHARGE'),
('10349',1,'FIRE','CHARGE'),
('10350',2,'FIRE','DEFENSE'),
('10351',0,'WIND','CHARGE'),
('10352',0,'WIND','DEFENSE'),
('10353',0,'WIND','CHARGE'),
('10354',3,'ICE','CRUSH'),
('10355',0,'ICE','CHARGE'),
('10356',0,'ICE','CHARGE'),
('10357',1,'FIRE','CRUSH'),
('10358',4,'WIND','DISTURB'),
('10359',4,'ICE','CRUSH'),
('10360',0,'WIND','CHARGE'),
('10361',2,'WIND','FASCINATION'),
('10362',2,'DARK','FASCINATION'),
('10363',0,'WIND','DEFENSE'),
('10364',0,'ICE','CHARGE'),
('10365',0,'WIND','DEFENSE'),
('10366',0,'WIND','CHARGE'),
('10367',1,'ICE','SUPPORT'),
('10368',1,'WIND','CHARGE'),
('10369',3,'ICE','DISTURB'),
('10370',1,'ICE','CHARGE'),
('10371',2,'FIRE','CRUSH'),
('10372',1,'ICE','CHARGE'),
('10373',3,'WIND','CRUSH'),
('10374',2,'WIND','CHARGE'),
('10375',0,'FIRE','DEFENSE'),
('10376',0,'WIND','CHARGE'),
('10377',0,'WIND','DEFENSE'),
('10378',1,'ICE','CHARGE'),
('10379',0,'WIND','CHARGE'),
('10380',1,'ICE','DEFENSE'),
('10381',0,'FIRE','DEFENSE'),
('10382',0,'WIND','CHARGE'),
('10383',3,'DARK','DISTURB'),
('10384',1,'WIND','SUPPORT'),
('10385',1,'ICE','DEFENSE'),
('10386',1,'WIND','CHARGE'),
('10387',0,'WIND','DEFENSE'),
('10388',0,'WIND','CHARGE'),
('10389',0,'WIND','DEFENSE'),
('10390',0,'WIND','CHARGE'),
('10391',1,'WIND','FASCINATION'),
('10392',3,'WIND','SUPPORT'),
('10393',2,'ICE','SUPPORT'),
('10394',2,'LIGHT','SUPPORT'),
('10395',0,'WIND','CHARGE'),
('10396',0,'ICE','CHARGE'),
('10397',1,'ICE','CRUSH'),
('10398',1,'ICE','CRUSH'),
('10399',3,'WIND','CRUSH'),
('10400',2,'ICE','DISTURB'),
('10401',0,'FIRE','CHARGE'),
('10402',0,'WIND','DEFENSE'),
('10403',0,'ICE','DEFENSE'),
('10404',0,'WIND','DEFENSE'),
('10405',1,'LIGHT','SUPPORT'),
('10406',2,'ICE','CHARGE'),
('10407',1,'ICE','DEFENSE'),
('10408',1,'WIND','CHARGE'),
('10409',0,'FIRE','CHARGE'),
('10410',0,'WIND','CHARGE'),
('10411',0,'ICE','DEFENSE'),
('10412',0,'ICE','CHARGE'),
('10413',2,'WIND','SUPPORT'),
('10414',2,'ICE','SUPPORT'),
('10415',3,'DARK','FASCINATION'),
('10416',0,'WIND','CHARGE'),
('10417',1,'ICE','DEFENSE'),
('10418',3,'ICE','DISTURB'),
('10419',2,'WIND','CRUSH'),
('10420',1,'WIND','CHARGE'),
('10421',0,'WIND','CHARGE'),
('10422',0,'WIND','CHARGE'),
('10423',0,'FIRE','CHARGE'),
('10424',1,'WIND','CHARGE'),
('10425',2,'WIND','CRUSH'),
('10426',1,'FIRE','FASCINATION'),
('10427',0,'FIRE','CHARGE'),
('10428',0,'WIND','DEFENSE'),
('10429',1,'WIND','CRUSH'),
('10430',0,'WIND','CHARGE'),
('10431',0,'WIND','DEFENSE'),
('10432',1,'WIND','SUPPORT'),
('10433',2,'WIND','CHARGE'),
('10434',0,'FIRE','DEFENSE'),
('10435',4,'FIRE','DISTURB'),
('10436',0,'FIRE','CHARGE'),
('10437',1,'DARK','FASCINATION'),
('10438',0,'ICE','CHARGE'),
('10439',3,'WIND','DEFENSE'),
('10440',4,'WIND','DEFENSE'),
('10441',0,'FIRE','CHARGE'),
('10442',2,'ICE','CRUSH'),
('10443',0,'ICE','DEFENSE'),
('10444',0,'FIRE','CHARGE'),
('10445',0,'WIND','CHARGE'),
('10446',0,'FIRE','CHARGE'),
('10447',1,'WIND','CHARGE'),
('10448',0,'FIRE','DEFENSE'),
('10449',0,'WIND','DEFENSE'),
('10450',0,'ICE','CHARGE'),
('10451',0,'ICE','CHARGE'),
('10452',2,'ICE','SUPPORT'),
('10453',0,'WIND','CHARGE'),
('10454',1,'ICE','CRUSH'),
('10455',1,'FIRE','CHARGE'),
('10456',0,'ICE','CHARGE'),
('10457',2,'WIND','SUPPORT'),
('10458',1,'FIRE','CHARGE'),
('10459',0,'WIND','CHARGE'),
('10460',0,'WIND','CHARGE'),
('10461',1,'FIRE','CHARGE'),
('10462',1,'WIND','CRUSH'),
('10463',2,'WIND','CRUSH'),
('10464',1,'FIRE','CHARGE'),
('10465',3,'WIND','CHARGE'),
('10466',1,'WIND','SUPPORT'),
('10467',0,'LIGHT','SUPPORT'),
('10468',0,'WIND','SUPPORT'),
('10469',0,'FIRE','CHARGE'),
('10470',1,'FIRE','CHARGE'),
('10471',0,'FIRE','CHARGE'),
('10472',0,'WIND','CHARGE'),
('10473',2,'WIND','CHARGE'),
('10474',0,'WIND','CHARGE'),
('10475',3,'DARK','CRUSH'),
('10476',0,'WIND','CHARGE'),
('10477',0,'WIND','DEFENSE'),
('10478',1,'WIND','DEFENSE'),
('10479',1,'ICE','CHARGE'),
('10480',2,'ICE','DEFENSE'),
('10481',2,'ICE','DISTURB'),
('10482',2,'FIRE','CHARGE'),
('10483',2,'FIRE','CHARGE'),
('10484',2,'FIRE','CRUSH'),
('10485',1,'FIRE','DEFENSE'),
('10486',1,'FIRE','SUPPORT'),
('10487',0,'WIND','CHARGE'),
('10488',3,'ICE','CHARGE'),
('10489',2,'FIRE','DEFENSE'),
('10490',3,'WIND','SUPPORT'),
('10491',3,'ICE','DISTURB'),
('10492',0,'LIGHT','CHARGE'),
('10493',2,'LIGHT','SUPPORT'),
('10494',0,'WIND','CHARGE'),
('10495',1,'ICE','CHARGE'),
('10496',2,'FIRE','CHARGE'),
('10497',0,'WIND','CHARGE'),
('10498',1,'ICE','CHARGE'),
('10499',2,'FIRE','CHARGE'),
('10500',1,'DARK','DISTURB'),
('10501',2,'DARK','DISTURB'),
('10502',3,'DARK','CRUSH'),
('10503',4,'DARK','DISTURB'),
('10504',4,'LIGHT','SUPPORT'),
('10505',2,'ICE','CRUSH'),
('10506',2,'ICE','CHARGE'),
('10507',2,'ICE','CRUSH'),
('10508',3,'FIRE','DISTURB'),
('10509',2,'WIND','CHARGE'),
('10510',2,'FIRE','CHARGE')
on conflict (id) do update set grade = excluded.grade, el = excluded.el, cls = excluded.cls;

-- 2) 파견지. rw = 1시간 기본 보상 (소수점은 그 확률로 1개 더: 0.3 → 30% 확률로 1)
create table if not exists public.dispatch_zones (
  id text primary key, grp text not null check (grp in ('exile', 'safe')), name text not null, ord int not null,
  min_grade int not null check (min_grade between 0 and 4), size int not null check (size between 1 and 4), rw jsonb not null);
alter table public.dispatch_zones enable row level security;
drop policy if exists dispatch_zones_read on public.dispatch_zones;
create policy dispatch_zones_read on public.dispatch_zones for select using (true);
insert into public.dispatch_zones (id, grp, name, ord, min_grade, size, rw) values
  ('x001', 'exile', '배척지 001', 1, 0, 1, '{"shard":5,"blood":3}'),
  ('x002', 'exile', '배척지 002', 2, 0, 2, '{"shard":7,"blood":5}'),
  ('x003', 'exile', '배척지 003', 3, 1, 2, '{"shard":10,"blood":8,"soul":0.3}'),
  ('x004', 'exile', '배척지 004', 4, 1, 2, '{"shard":12,"blood":9,"soul":0.4}'),
  ('x005', 'exile', '배척지 005', 5, 2, 3, '{"shard":14,"blood":10,"soul":0.8}'),
  ('x006', 'exile', '배척지 006', 6, 2, 3, '{"shard":16,"blood":12,"soul":1}'),
  ('x007', 'exile', '배척지 007', 7, 3, 3, '{"shard":18,"blood":14,"soul":1.5,"gem":0.2}'),
  ('x008', 'exile', '배척지 008', 8, 3, 4, '{"shard":20,"blood":16,"soul":2.2,"gem":0.6}'),
  ('x009', 'exile', '배척지 009', 9, 4, 4, '{"shard":24,"blood":20,"soul":3.3,"gem":1.6}'),
  ('sB',   'safe',  '안전지대 B급', 11, 0, 1, '{"gold":500}'),
  ('sA',   'safe',  '안전지대 A급', 12, 1, 2, '{"gold":1000,"drink":0.15}'),
  ('sS',   'safe',  '안전지대 S급', 13, 2, 3, '{"gold":2000,"tickets":0.05}'),
  ('sSS',  'safe',  '안전지대 SS급', 14, 3, 4, '{"gold":3300,"tickets":0.17,"gem":0.8}')
on conflict (id) do update set grp = excluded.grp, name = excluded.name, ord = excluded.ord, min_grade = excluded.min_grade, size = excluded.size, rw = excluded.rw;
delete from public.dispatch_zones where id not in ('x001','x002','x003','x004','x005','x006','x007','x008','x009','sB','sA','sS','sSS');

-- 3) 의뢰 게시판 · 진행 · 하루 기록 (직접 읽기만, 쓰기는 함수로만)
create table if not exists public.dispatch_offers (
  user_id uuid not null references auth.users(id) on delete cascade, slot int not null check (slot between 1 and 6),
  day date not null, zone text not null references public.dispatch_zones(id), el text not null, cls text not null,
  taken boolean not null default false, primary key (user_id, slot));
create table if not exists public.dispatch_runs (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  zone text not null references public.dispatch_zones(id), el text not null, cls text not null, hours int not null check (hours in (1, 4, 8, 12)),
  uids text[] not null, bonus int not null default 0, great boolean not null default false, reward jsonb not null,
  started_at timestamptz not null default now(), ends_at timestamptz not null,
  claimed_at timestamptz, recalled boolean not null default false);
create index if not exists dispatch_runs_open on public.dispatch_runs (user_id) where claimed_at is null;
create table if not exists public.dispatch_daily (
  user_id uuid not null references auth.users(id) on delete cascade, day date not null,
  refreshes int not null default 0, starts int not null default 0, primary key (user_id, day));
do $$ declare t text; begin
  foreach t in array array['dispatch_offers', 'dispatch_runs', 'dispatch_daily'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_own', t);
    execute format('create policy %I on public.%I for select using (user_id = auth.uid())', t || '_own', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop; end $$;

-- 4) 도우미
create or replace function public._dsp_day() returns date language sql stable as $$ select (now() at time zone 'Asia/Seoul')::date $$;
create or replace function public._dsp_mult(h int) returns numeric language sql immutable as $$ select case h when 1 then 1 when 4 then 3.5 when 8 then 6 when 12 then 8.5 end $$;
create or replace function public._dsp_slots(lv int) returns int language sql immutable as $$ select case when lv >= 60 then 5 when lv >= 30 then 4 else 3 end $$;
create or replace function public._dsp_cap() returns int language sql immutable as $$ select 12 $$;
create or replace function public._dsp_free() returns int language sql immutable as $$ select 3 $$;
-- n = 오늘 이미 한 새로고침 수 → 이번 새로고침 비용
create or replace function public._dsp_cost(n int) returns int language sql immutable as $$ select case when n < 3 then 0 else least(20 + 10 * (n - 3), 50) end $$;
create or replace function public._dsp_level(p_uid uuid) returns int language plpgsql security definer set search_path = public as $$
declare lv int; begin begin select (_player_sync(p_uid)).level into lv; exception when others then lv := 1; end; return coalesce(lv, 1); end $$;
create or replace function public._dsp_owned(p_uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select case when jsonb_typeof(data->'owned') = 'array' then data->'owned' end from story_progress where user_id = p_uid), '[]'::jsonb) $$;

-- 게시판 채우기 (p_all: 전부 새로 / 아니면 아직 안 보낸 의뢰만). 가진 카드 중 최고 등급(UR까지)으로 갈 수 있는 곳만
create or replace function public._dsp_fill(p_uid uuid, p_all boolean) returns void language plpgsql security definer set search_path = public as $$
declare best int; s int; z text; els text[] := array['WIND','FIRE','ICE','DARK','LIGHT']; cl text[] := array['CHARGE','CRUSH','DEFENSE','SUPPORT','DISTURB','FASCINATION'];
begin
  select coalesce(max(m.grade), 0) into best from jsonb_array_elements(_dsp_owned(p_uid)) o join dispatch_card_meta m on m.id = o->>'id' where m.grade <= 4;
  if p_all then delete from dispatch_offers where user_id = p_uid; end if;
  for s in 1..6 loop
    if not p_all and exists (select 1 from dispatch_offers where user_id = p_uid and slot = s and taken) then continue; end if;
    -- 높은 단계일수록 조금 더 자주 (ord 가중치)
    select id into z from dispatch_zones where grp = case when s <= 4 then 'exile' else 'safe' end and min_grade <= best
      order by -ln(greatest(random(), 1e-9)) / (1 + min_grade) limit 1;
    insert into dispatch_offers (user_id, slot, day, zone, el, cls, taken) values (p_uid, s, _dsp_day(), z, els[1 + floor(random() * 5)::int], cl[1 + floor(random() * 6)::int], false)
      on conflict (user_id, slot) do update set day = excluded.day, zone = excluded.zone, el = excluded.el, cls = excluded.cls, taken = false;
  end loop;
end $$;

create or replace function public._dsp_json(p_uid uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare d dispatch_daily; lv int := _dsp_level(p_uid);
begin
  select * into d from dispatch_daily where user_id = p_uid and day = _dsp_day();
  return jsonb_build_object('ok', true, 'now', now(), 'day', _dsp_day(),
    'next_reset', ((_dsp_day() + 1)::timestamp at time zone 'Asia/Seoul'),
    'offers', coalesce((select jsonb_agg(jsonb_build_object('slot', o.slot, 'zone', o.zone, 'el', o.el, 'cls', o.cls, 'taken', o.taken) order by o.slot) from dispatch_offers o where o.user_id = p_uid), '[]'::jsonb),
    'runs', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'zone', r.zone, 'el', r.el, 'cls', r.cls, 'hours', r.hours, 'uids', r.uids, 'bonus', r.bonus,
              'started_at', r.started_at, 'ends_at', r.ends_at, 'done', r.ends_at <= now(), 'reward', case when r.ends_at <= now() then r.reward end, 'great', case when r.ends_at <= now() then r.great end) order by r.ends_at)
              from dispatch_runs r where r.user_id = p_uid and r.claimed_at is null), '[]'::jsonb),
    'zones', (select jsonb_agg(jsonb_build_object('id', id, 'grp', grp, 'name', name, 'min_grade', min_grade, 'size', size, 'rw', rw) order by ord) from dispatch_zones),
    'mult', jsonb_build_object('1', 1, '4', 3.5, '8', 6, '12', 8.5),
    'slots', _dsp_slots(lv), 'level', lv, 'cap', _dsp_cap(), 'starts', coalesce(d.starts, 0),
    'refreshes', coalesce(d.refreshes, 0), 'free', _dsp_free(), 'refresh_cost', _dsp_cost(coalesce(d.refreshes, 0)));
end $$;

-- 5) 공개 함수
create or replace function public.dispatch_status() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  if not exists (select 1 from dispatch_offers where user_id = uid and day = _dsp_day()) then perform _dsp_fill(uid, true); end if;
  return _dsp_json(uid);
end $$;

create or replace function public.dispatch_refresh() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); n int; c int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  insert into dispatch_daily (user_id, day) values (uid, _dsp_day()) on conflict do nothing;
  select refreshes into n from dispatch_daily where user_id = uid and day = _dsp_day() for update;
  c := _dsp_cost(n);
  if c > 0 then
    begin perform _gem_spend(uid, c, 'dispatch_refresh', jsonb_build_object('n', n + 1));
    exception when others then if sqlerrm ~ 'not enough' then raise exception 'not enough gem'; else raise; end if; end;
  end if;
  update dispatch_daily set refreshes = refreshes + 1 where user_id = uid and day = _dsp_day();
  if not exists (select 1 from dispatch_offers where user_id = uid and day = _dsp_day()) then perform _dsp_fill(uid, true); else perform _dsp_fill(uid, false); end if;
  return _dsp_json(uid) || jsonb_build_object('spent', c);
end $$;

-- 보내기. 오류: bad hours · no offer · taken · slots full · daily cap · bad cards · not owned · busy · banned grade · need grade
create or replace function public.dispatch_start(p_slot int, p_uids text[], p_hours int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); o dispatch_offers; z dispatch_zones; owned jsonb; n int; mx int; bon int := 0; ne int; nc int; over boolean; k text; v numeric; rw jsonb := '{}'::jsonb; f numeric; great boolean := false; cnt int; d dispatch_daily;
begin
  if uid is null then raise exception 'login required'; end if;
  if p_hours not in (1, 4, 8, 12) then raise exception 'bad hours'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  select * into o from dispatch_offers where user_id = uid and slot = p_slot for update;
  if o.user_id is null or o.day <> _dsp_day() then raise exception 'no offer'; end if;
  if o.taken then raise exception 'taken'; end if;
  select * into z from dispatch_zones where id = o.zone;
  if (select count(*) from dispatch_runs where user_id = uid and claimed_at is null) >= _dsp_slots(_dsp_level(uid)) then raise exception 'slots full'; end if;
  select * into d from dispatch_daily where user_id = uid and day = _dsp_day();
  if coalesce(d.starts, 0) >= _dsp_cap() then raise exception 'daily cap'; end if;
  n := coalesce(array_length(p_uids, 1), 0);
  if n < 1 or n > z.size or (select count(distinct u) from unnest(p_uids) u) <> n then raise exception 'bad cards'; end if;
  owned := _dsp_owned(uid);
  -- 가진 카드인지 + 카드 정보
  create temp table if not exists _dsp_pick (uid text, grade int, el text, cls text) on commit drop; delete from _dsp_pick;
  insert into _dsp_pick select u, m.grade, m.el, m.cls from unnest(p_uids) u
    join lateral (select x from jsonb_array_elements(owned) x where x->>'uid' = u limit 1) ox on true
    join dispatch_card_meta m on m.id = ox.x->>'id';
  if (select count(*) from _dsp_pick) <> n then raise exception 'not owned'; end if;
  if exists (select 1 from dispatch_runs r where r.user_id = uid and r.claimed_at is null and r.uids && p_uids) then raise exception 'busy'; end if;
  if exists (select 1 from _dsp_pick where grade >= 5) then raise exception 'banned grade'; end if;
  select max(grade) into mx from _dsp_pick;
  if mx < z.min_grade then raise exception 'need grade'; end if;
  select count(*) filter (where el = o.el), count(*) filter (where cls = o.cls) into ne, nc from _dsp_pick;
  bon := least(60, 15 * (ne + nc)) + case when mx > z.min_grade then 10 else 0 end;
  great := least(60, 15 * (ne + nc)) >= 60 and random() < 0.10;
  f := _dsp_mult(p_hours) * (1 + bon / 100.0) * case when great then 2 else 1 end;
  for k, v in select key, value::numeric from jsonb_each_text(z.rw) loop
    v := v * f; cnt := floor(v)::int + case when random() < v - floor(v) then 1 else 0 end;
    if cnt > 0 then rw := rw || jsonb_build_object(k, cnt); end if;
  end loop;
  update dispatch_offers set taken = true where user_id = uid and slot = p_slot;
  insert into dispatch_daily (user_id, day, starts) values (uid, _dsp_day(), 1) on conflict (user_id, day) do update set starts = dispatch_daily.starts + 1;
  insert into dispatch_runs (user_id, zone, el, cls, hours, uids, bonus, great, reward, ends_at)
    values (uid, z.id, o.el, o.cls, p_hours, p_uids, bon, great, rw, now() + make_interval(hours => p_hours));
  return _dsp_json(uid);
end $$;

-- 일찍 부르기 (보상 없음, 카드 바로 풀림, 의뢰도 다시 쓸 수 없음)
create or replace function public.dispatch_recall(p_run bigint) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  update dispatch_runs set claimed_at = now(), recalled = true where id = p_run and user_id = uid and claimed_at is null and ends_at > now();
  if not found then raise exception 'no run'; end if;
  return _dsp_json(uid);
end $$;

-- 받기 (p_run = null 이면 끝난 것 모두)
create or replace function public.dispatch_claim(p_run bigint default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r dispatch_runs; tot jsonb := '{}'::jsonb; k text; v int; cur jsonb; got int := 0; w jsonb; t int;
begin
  if uid is null then raise exception 'login required'; end if;
  perform pg_advisory_xact_lock(hashtext('dsp:' || uid::text));
  for r in select * from dispatch_runs where user_id = uid and claimed_at is null and ends_at <= now() and (p_run is null or id = p_run) for update loop
    update dispatch_runs set claimed_at = now() where id = r.id;
    got := got + 1;
    for k, v in select key, value::int from jsonb_each_text(r.reward) loop
      tot := jsonb_set(tot, array[k], to_jsonb(coalesce((tot->>k)::int, 0) + v));
    end loop;
    if (r.reward->>'gem') is not null then perform _gem_add(uid, (r.reward->>'gem')::int, 0, 'dispatch', 'dispatch:' || r.id, jsonb_build_object('zone', r.zone)); end if;
    if (r.reward->>'drink') is not null then perform _item_add(uid, 'drink', 0, (r.reward->>'drink')::int, 'dispatch', 'dispatch:' || r.id, jsonb_build_object('zone', r.zone)); end if;
  end loop;
  if got = 0 then raise exception 'nothing to claim'; end if;
  cur := '{}'::jsonb;
  foreach k in array array['gold', 'blood', 'shard', 'soul'] loop if tot ? k then cur := cur || jsonb_build_object(k, (tot->>k)::int); end if; end loop;
  if cur <> '{}'::jsonb then w := _wallet_add(uid, cur, 'dispatch'); end if;
  if coalesce((tot->>'tickets')::int, 0) > 0 then
    update story_gacha set tickets = tickets + (tot->>'tickets')::int, updated_at = now() where user_id = uid returning tickets into t;
    if t is null then insert into story_gacha (user_id, last_draw, tickets) values (uid, _dsp_day() - 1, (tot->>'tickets')::int); end if;
  end if;
  return _dsp_json(uid) || jsonb_build_object('got', tot, 'claimed', got, 'wallet', w);
end $$;

revoke all on function public._dsp_fill(uuid, boolean), public._dsp_json(uuid), public._dsp_level(uuid), public._dsp_owned(uuid) from public, anon, authenticated;
revoke all on function public.dispatch_status(), public.dispatch_refresh(), public.dispatch_start(int, text[], int), public.dispatch_recall(bigint), public.dispatch_claim(bigint) from public, anon;
grant execute on function public.dispatch_status(), public.dispatch_refresh(), public.dispatch_start(int, text[], int), public.dispatch_recall(bigint), public.dispatch_claim(bigint) to authenticated;
