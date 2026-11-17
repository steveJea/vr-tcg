"""어린 최국선 10536 나이 15 → 9 (시트 수정, 11/17): npc_cards.csv 가 엔진에 들어가므로 엔진 해시 3개(길드전 v4 · 스윕 v6 · 직접전투 v7)가 바뀜.
PR #625 해시(story_ch18_19_staging.sql 실행 후 값) → 새 해시로 바꾸는 staging SQL + 단일 SELECT 확인 SQL 생성.
사용: python3 tools/build_young_age_sql.py [--check]"""
import re, sys
G = '7703759698107299042'
def h(f): return re.search(r'[0-9a-f]{64}', open(f).read()).group(0)
NEWH = {
    'pvp_policy_v3': h('js/pvp-engine-version.js'), 'guildbattle_policy_v4': h('js/guildbattle-engine-version.js'),
    'arcade_policy_v5': h('js/arcade-engine-version.js'), 'battle_replay_policy_v6': h('js/sweep-engine-version.js'),
    'battle_replay_policy_v7': re.search(r'DIRECT_V7[^;]*?([0-9a-f]{64})', open('js/battle-session.js').read()).group(1),
}
prev = open('supabase/story_ch18_19_staging.sql', encoding='utf8').read()
OLD = {t: re.search(rf"update public\.{t}\s+set engine_hash = '([0-9a-f]{{64}})'", prev).group(1) for t in NEWH}
CH = {t: v for t, v in NEWH.items() if OLD[t] != v}
upd = '\n'.join(f"""  update public.{t} set engine_hash = '{v}' where singleton and engine_hash in ('{OLD[t]}', '{v}');""" for t, v in CH.items())
need = '\n     or '.join(f"not exists (select 1 from public.{t} where singleton and engine_hash = '{v}')" for t, v in NEWH.items())
sql = f"""-- =====================================================================
-- 11/17 어린 최국선(10536) 나이 15 → 9 (캐릭터 시트 수정). 카드 데이터가 엔진에 들어가 있어 엔진 해시 {len(CH)}개 갱신:
--   {', '.join(CH)}
-- 먼저 story_ch18_19_staging.sql (PR #625) 을 돌린 뒤 실행. 여러 번 실행해도 안전. 삭제 없음. 전투 규칙 변화 없음 (나이는 전투에 안 쓰임).
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). 생성: python3 tools/build_young_age_sql.py (직접 고치지 말 것)
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '{G}' then
    raise exception 'STOP: young age hash staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;
do $hash$
begin
{upd}
  if {need}
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. story_ch18_19_staging.sql 을 먼저 돌렸는지 확인해 주세요.';
  end if;
end $hash$;
commit;
"""
chk = "-- 확인용 (읽기 전용): ok = true 면 정상\nselect (\n  " + '\n  and '.join(f"(select engine_hash from public.{t} where singleton) = '{v}'" for t, v in NEWH.items()) + "\n) as ok;\n"
out = {'supabase/young_age_hash_staging.sql': sql, 'supabase/young_age_hash_check_staging.sql': chk}
if '--check' in sys.argv:
    bad = [f for f, s in out.items() if open(f, encoding='utf8').read() != s]
    if bad: sys.exit('stale: ' + ', '.join(bad) + ' → python3 tools/build_young_age_sql.py')
else:
    for f, s in out.items(): open(f, 'w', encoding='utf8').write(s)
print('young age hash SQL:', ', '.join(f'{t} {OLD[t][:8]}→{v[:8]}' for t, v in CH.items()))
