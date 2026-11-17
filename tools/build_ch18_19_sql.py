#!/usr/bin/env python3
"""디버그 64번 (CH18·19 · 신규 카드 10533~10543 · 16-1 어린 최국선) staging SQL 생성
입력: supabase/security_phase2_clears.sql 의 생성 블록 (node tools/build_phase2_catalog.mjs 먼저), data/*.csv, js/*-engine-version.js
출력: supabase/story_ch18_19_staging.sql · supabase/story_ch18_19_check_staging.sql
사용: python3 tools/build_ch18_19_sql.py [--check]"""
import csv, json, re, sys
G = '7703759698107299042'
blk = open('supabase/security_phase2_clears.sql', encoding='utf8').read()
blk = blk[blk.index('-- BEGIN GENERATED PHASE2 STORY'):blk.index('-- END GENERATED PHASE2 STORY')]
rows = [l.rstrip(',') for l in blk.split('\n') if re.match(r"^\((18|19),\d+,'',|^\(16,1,'',", l)]
NEW = [str(i) for i in range(10533, 10544)]
meta = [l for l in blk.split('\n') if l.startswith('insert into public.battle_card_meta_v2') and any(f"values ('{i}'," in l for i in NEW)]
assert len(meta) == len(NEW), len(meta)
cards = {r['id']: r for f in ('data/cards.csv', 'data/npc_cards.csv') for r in csv.DictReader(open(f, encoding='utf-8-sig'))}
STORY = {}
for chn in (18, 19):
    s = open(f'js/story-data-ch{chn}.js', encoding='utf8').read(); ch = json.loads(s[s.index('push(') + 5:s.rindex(')')])
    STORY[chn] = ch['phases']
cfg = ', '.join(f"({c},{p['no']},'{p['type']}',3,null,{0 if p.get('scene') else len(p['enemies']['ids'])})" for c in (18, 19) for p in STORY[c])
def h(f, pat=r'[0-9a-f]{64}'): return re.search(pat, open(f).read()).group(0)
NEWH = {
    'pvp_policy_v3': h('js/pvp-engine-version.js'), 'guildbattle_policy_v4': h('js/guildbattle-engine-version.js'),
    'arcade_policy_v5': h('js/arcade-engine-version.js'), 'battle_replay_policy_v6': h('js/sweep-engine-version.js'),
    'battle_replay_policy_v7': re.search(r'DIRECT_V7[^;]*?([0-9a-f]{64})', open('js/battle-session.js').read()).group(1),
}
# 66번(PR #624) 해시 SQL 이 허용하던 옛 값 + 66번 새 값 → 이번 새 값
prev = open('supabase/sheet_skills66_hash_staging.sql', encoding='utf8').read()
OLD = {t: re.findall(r'[0-9a-f]{64}', prev[prev.index(f'update public.{t}'):prev.index(';', prev.index(f'update public.{t}'))]) for t in NEWH}
upd = '\n'.join(f"""  update public.{t}
    set engine_hash = '{v}'
    where singleton and engine_hash in ({', '.join(f"'{x}'" for x in dict.fromkeys(OLD[t] + [v]))});""" for t, v in NEWH.items())
chk_hash = '\n     or '.join(f"not exists (select 1 from public.{t} where singleton and engine_hash = '{v}')" for t, v in NEWH.items())
c33 = cards['10533']
sql = f"""-- =====================================================================
-- 디버그 64번 (11/17): 스토리 챕터 18 「BITTERSWEET」(16 페이즈) · 19 「한니발라이징」(13 페이즈)
-- + 신규 카드 10533 우승찬(플레이어 카드, 뽑기 미공개) · NPC 10534~10543 · 16-1 필수 출전 어린 최국선(10536)
-- + 엔진 해시 갱신 (NPC 스킬 10종 · 신규 카드 데이터가 엔진에 들어감). PR #624(66번) 해시 SQL을 돌렸든 안 돌렸든 안전.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). Supabase SQL Editor 에 전체를 붙여넣고 Run. 여러 번 실행해도 안전. 삭제 없음.
-- 18-2·18-10·18-11·18-14·19-2·19-4·19-6 은 전투 없는 스토리 페이즈 (enemy_count=0, story_complete_scene · #623).
-- 18-15·19-13 은 16-11 처럼 진영 HP 보스전 (type=boss). 19-13 [상념] 민홍기는 쓰러지면 2턴 후 부활.
-- 생성: python3 tools/build_ch18_19_sql.py (직접 고치지 말 것)
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '{G}' then
    raise exception 'STOP: story ch18/19 staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;

insert into public.story_phase_config (chapter, phase, type, points, reward_grade, enemy_count) values
  {cfg}
on conflict (chapter, phase) do update set type = excluded.type, points = excluded.points, reward_grade = excluded.reward_grade, enemy_count = excluded.enemy_count;

-- 우승찬 10533: 시트 NPC 칸이 비어 있어 플레이어 카드(cards.csv). 2026-11-11 신규 16장과 같이 뽑기 풀에는 아직 안 넣음 (gacha=false).
insert into public.story_card_pool (id, grade, name, gacha) values ('10533','{c33['grade']}','{c33['name']}',false)
on conflict (id) do update set grade = excluded.grade, name = excluded.name;
insert into public.pvp_card_meta (id, grade, cost) values ('10533','{c33['grade']}',{c33['cost']})
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;
-- 도감 카탈로그 (security_phase1_rewards.sql 목록과 같게)
insert into public.reward_card_catalog (card_id) values ('10533') on conflict do nothing;

-- battle_card_meta_v2 / battle_story_defs_v2 (tools/build_phase2_catalog.mjs 와 같은 값)
do $cat$
begin
  if to_regclass('public.battle_story_defs_v2') is null then
    raise notice 'battle_story_defs_v2 not present; skip ch18/19 catalog';
    return;
  end if;
  execute $s0${chr(10).join(meta)}$s0$;
  execute $s1$insert into public.battle_story_defs_v2(chapter,phase,variant,definition) values
{(','+chr(10)).join(rows)}
on conflict (chapter,phase,variant) do update set definition=excluded.definition;$s1$;
end $cat$;

do $hash$
begin
{upd}
  if {chk_hash}
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. 현재 값을 확인하고 딩순이에게 알려 주세요.';
  end if;
end $hash$;
commit;
"""
n18, n19 = len(STORY[18]), len(STORY[19])
p161 = json.loads(re.search(r"^\(16,1,'','(.*)'::jsonb\)$", next(r for r in rows if r.startswith('(16,1,')), re.M).group(1).replace("''", "'"))
chk = f"""-- 읽기만 함. staging 전용. story_ch18_19_staging.sql 실행 후 한 줄 확인. 기대: ok=true
-- 생성: python3 tools/build_ch18_19_sql.py
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '{G}'
  and (select count(*) from public.story_phase_config where chapter = 18) = {n18}
  and (select count(*) from public.story_phase_config where chapter = 19) = {n19}
  and (select count(*) from public.story_phase_config where chapter in (18, 19) and enemy_count = 0) = {sum(1 for c in (18, 19) for p in STORY[c] if p.get('scene'))}
  and (select type from public.story_phase_config where chapter = 18 and phase = 15) = 'boss'
  and (select type from public.story_phase_config where chapter = 19 and phase = 13) = 'boss'
  and (select count(*) from public.battle_story_defs_v2 where chapter in (18, 19) and variant = '') = {n18 + n19}
  and (select definition->'rules'->'revive'->0->>'id' from public.battle_story_defs_v2 where chapter = 19 and phase = 13 and variant = '') = '10534'
  and (select definition->'party'->'forced'->>0 from public.battle_story_defs_v2 where chapter = 16 and phase = 1 and variant = '') = '{p161['party']['forced'][0]}'
  and (select count(*) from public.battle_card_meta_v2 where id between '10533' and '10543') = {len(NEW)}
  and (select gacha from public.story_card_pool where id = '10533') = false
  and exists (select 1 from public.reward_card_catalog where card_id = '10533'){''.join(f"{chr(10)}  and (select engine_hash from public.{t} where singleton) = '{v}'" for t, v in NEWH.items())}
) as ok;
"""
card = f"""-- =====================================================================
-- 2026-11-17 신규 카드 우승찬(10533, {c33['grade']}, 코스트 {c33['cost']}): 카드 목록 · PVP 덱 검증 · 도감 카탈로그 FK
-- 시트 NPC 칸이 비어 있어 플레이어 카드. 프로필만 있고 스킬 없음. 뽑기 풀에는 넣지 않음 (gacha = false, 11-11 신규 카드와 같음).
-- staging_install.sql 에 포함 (security_phase1_rewards.sql 의 reward_card_catalog 보다 먼저). 여러 번 실행해도 안전. 삭제 없음.
-- tools/build_ch18_19_sql.py 가 생성.
-- =====================================================================
insert into public.story_card_pool (id, grade, name, gacha) values
  ('10533','{c33['grade']}','{c33['name']}',false)
on conflict (id) do update set grade = excluded.grade, name = excluded.name;

insert into public.pvp_card_meta (id, grade, cost) values
  ('10533','{c33['grade']}',{c33['cost']})
on conflict (id) do update set grade = excluded.grade, cost = excluded.cost;
"""
out = {'supabase/card_10533.sql': card, 'supabase/story_ch18_19_staging.sql': sql, 'supabase/story_ch18_19_check_staging.sql': chk}
if '--check' in sys.argv:
    bad = [f for f, s in out.items() if open(f, encoding='utf8').read() != s]
    if bad: sys.exit('stale: ' + ', '.join(bad) + ' → python3 tools/build_ch18_19_sql.py')
else:
    for f, s in out.items(): open(f, 'w', encoding='utf8').write(s)
print('ch18/19 staging SQL:', len(rows), 'defs,', len(meta), 'card meta')
