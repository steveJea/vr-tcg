"""2026-11-21 스킬 시트 (황보예 변경 · 왕유영·하지연·주슬기·허유리·류태연 추가): staging 엔진 해시 SQL + 단일 SELECT 확인 SQL.
이전 해시 = rename_three_cards_hash_staging.sql (11/19) 의 새 값. 스킬 레벨업용 story_skill_meta (액티브 4개) 도 같이 반영.
사용: python3 tools/build_sheet1121_sql.py [--check]"""
import re, sys, json
G = '7703759698107299042'
def h(f): return re.search(r'[0-9a-f]{64}', open(f).read()).group(0)
NEWH = {
    'pvp_policy_v3': h('js/pvp-engine-version.js'), 'guildbattle_policy_v4': h('js/guildbattle-engine-version.js'),
    'arcade_policy_v5': h('js/arcade-engine-version.js'), 'battle_replay_policy_v6': h('js/sweep-engine-version.js'),
    'battle_replay_policy_v7': re.search(r'DIRECT_V7[^;]*?([0-9a-f]{64})', open('js/battle-session.js').read()).group(1),
}
prev = open('supabase/rename_three_cards_hash_staging.sql', encoding='utf8').read()
OLD = {t: re.search(rf"update public\.{t}\s+set engine_hash = '([0-9a-f]{{64}})'", prev).group(1) for t in NEWH}
meta_src = open('supabase/sheet_skills1121_meta.sql', encoding='utf8').read()
META = re.findall(r"\('(\d+)',(\d+),(\d+)\)", meta_src)
SK = json.load(open('data/skills.json', encoding='utf8'))
for cid, idx, ul in META:   # 액티브 idx번째와 해금 레벨이 skills.json 과 같아야 함
    act = [s for s in SK[cid] if s['mode'] == 'active']
    assert act[int(idx) - 1]['unlock'] == int(ul), (cid, idx, ul)
meta_rows = ',\n  '.join(f"('{c}',{i},{u})" for c, i, u in META)
upd = '\n'.join(f"""  update public.{t} set engine_hash = '{v}' where singleton and engine_hash in ('{OLD[t]}', '{v}');""" for t, v in NEWH.items())
need = '\n     or '.join(f"not exists (select 1 from public.{t} where singleton and engine_hash = '{v}')" for t, v in NEWH.items())
sql = f"""-- =====================================================================
-- 2026-11-21 스킬 시트 반영: 황보예 스킬 변경 (사망 패시브 → 액티브 '나 갈거거든?'),
-- 왕유영·하지연·주슬기·허유리·류태연 스킬 추가. 스킬 데이터가 엔진에 들어가 있어 엔진 해시 5개 갱신
-- + 스킬 레벨업 해금 메타 (새 액티브 4개, Lv2).
-- 먼저 Edge Function 5개(pvp-verify-v3, guildbattle-verify-v4, arcade-verify-v5,
-- story-tower-verify-v6, story-direct-verify-v7)를 새 dashboard_single_file.ts 로 재배포한 뒤 실행.
-- 이전 값은 rename_three_cards_hash_staging.sql (11/19) 실행 후 값. 여러 번 실행해도 안전. 삭제 없음.
-- STAGING ONLY (cuyqchmdcnsgzkwyclji). 생성: python3 tools/build_sheet1121_sql.py (직접 고치지 말 것)
-- =====================================================================
begin;
do $guard$
begin
  if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '{G}' then
    raise exception 'STOP: sheet skills 1121 hash is staging cuyqchmdcnsgzkwyclji only; production forbidden';
  end if;
end $guard$;
insert into public.story_skill_meta (card_id, idx, unlock) values
  {meta_rows}
on conflict (card_id, idx) do update set unlock = excluded.unlock;
do $hash$
begin
{upd}
  if {need}
  then
    raise exception 'STOP: 엔진 해시가 예상과 다릅니다. rename_three_cards_hash_staging.sql 을 먼저 돌렸는지 확인해 주세요.';
  end if;
end $hash$;
commit;
"""
meta_chk = '\n  and '.join(f"exists (select 1 from public.story_skill_meta where card_id = '{c}' and idx = {i} and unlock = {u})" for c, i, u in META)
chk = ("-- 확인용 (읽기 전용): ok = true 면 정상\nselect (\n  (select system_identifier::text from pg_catalog.pg_control_system()) = '" + G + "'\n  and "
       + '\n  and '.join(f"(select engine_hash from public.{t} where singleton) = '{v}'" for t, v in NEWH.items())
       + '\n  and ' + meta_chk + "\n) as ok;\n")
out = {'supabase/sheet_skills1121_hash_staging.sql': sql, 'supabase/sheet_skills1121_hash_check_staging.sql': chk}
if '--check' in sys.argv:
    bad = [f for f, s in out.items() if open(f, encoding='utf8').read() != s]
    if bad: sys.exit('stale: ' + ', '.join(bad) + ' → python3 tools/build_sheet1121_sql.py')
else:
    for f, s in out.items(): open(f, 'w', encoding='utf8').write(s)
print('sheet 1121 hash SQL:', ', '.join(f'{t} {OLD[t][:8]}→{v[:8]}' for t, v in NEWH.items()), '·', len(META), 'meta')
