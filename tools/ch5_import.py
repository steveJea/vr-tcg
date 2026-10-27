#!/usr/bin/env python3
"""챕터 5 대본(md) → js/story-data-ch5.js
사용법: python3 tools/ch5_import.py <대본 파일 ch5_gyeoul.md>
단일 루트(주인공 한겨울, 페이즈 10 은 진하린). '적: 이름, 이름(L)' 의 (L) = 상대 리더(보스전이면 보스 카드).
페이즈별 강제 배정·추가 조건은 아래 RULES 표 (구글 시트 '어비스게이트 스토리' 탭 '챕터5' 기준).
'겨울 친구' 는 카드가 없어 이름만 표시 (초상화 없음).
"""
import csv, json, os, re, sys
ROOT = os.path.join(os.path.dirname(__file__), '..')
rows = list(csv.DictReader(open(os.path.join(ROOT, 'data/cards.csv'), encoding='utf-8-sig')))
ID = {r['name']: r['id'] for r in rows}
GW, HR, AY, SY = ID['한겨울'], ID['진하린'], ID['정아영'], ID['정서영']
NO_CARD = ['겨울 친구']
# party 조건: banClass(이 속성 출전 불가) · maxGrade(이 등급까지만 → UR 이상 불가). 필수 카드는 조건 예외
NO_UR = {'maxGrade': 'SUPER RARE'}
RULES = {n: ([GW], {}, None) for n in range(1, 7)}
RULES.update({7: ([GW], {'banClass': ['DARK']}, None), 8: ([GW], {'banClass': ['LIGHT']}, None), 9: ([GW], NO_UR, None),
              10: ([HR], NO_UR, {'undying': [SY]})})
# 정아영은 N 등급이지만 3·10페이즈 리더: 스토리 전용 능력치 (해당 페이즈에서만, 카드 원본은 그대로)
BOOST = {3: {AY: {'HP': 150, 'ATK': 30, 'DEF': 26}},
         10: {AY: {'HP': 360, 'ATK': 62, 'DEF': 44}, SY: {'HP': 240, 'ATK': 40, 'DEF': 30}}}
# power 는 boost 스탯으로 옵션 B 공식 계산 (tools/power.py)
sys.path.insert(0, os.path.dirname(__file__)); from power import card_power
BYID = {r['id']: r for r in rows}
for _b in BOOST.values():
    for _k, _v in _b.items(): _v['power'] = card_power(BYID[_k], **_v)
LINE = re.compile(r'^\[([^:\]]+?)\s*(?:\((기본|화남|웃음)\))?:\s*(.*)\]$')

def parse(path):
    secs, cur = [], None
    for raw in open(path, encoding='utf-8'):
        s = raw.strip()
        if s.startswith('## '): cur = {'head': s[3:].strip(), 'lines': [], 'after': None, 'text': [], 'enemies': None}; secs.append(cur); continue
        if cur is None or not s: continue
        if s.startswith('- 전투 승리 후'): cur['after'] = []; continue
        m = LINE.match(s)
        if m:
            L = {'speaker': m.group(1).strip(), 'text': m.group(3).strip()}
            if m.group(2) and m.group(2) != '기본': L['expr'] = m.group(2)
            (cur['after'] if cur['after'] is not None else cur['lines']).append(L); continue
        if s.startswith('적:'): cur['enemies'] = [n.strip() for n in s[2:].split(',') if n.strip()]; continue
        if not s.startswith('Chapter'): cur['text'].append(s)
    return secs

def main(src):
    secs = parse(src); ch = {'id': 5, 'title': 'CHAPTER 5', 'subtitle': '영원히 멈추지 않는 비', 'rewardCard': None, 'hero': GW, 'single': True, 'phases': []}
    missing = set()
    for s in secs:
        h = s['head']
        if h.startswith('한겨울 ·'): continue
        if h.startswith('캐릭터 소개'): ch['tagline'] = '\n'.join(s['text']); continue
        if h.startswith('시작 스토리'): ch['start'] = s['lines']; continue
        if h.startswith('엔딩'): ch['ending'] = s['lines']; continue
        m = re.match(r'Phase\.(\d+)\s*「(.+?)」', h)
        if not m: continue
        no = int(m.group(1)); raw = s['enemies']
        lead = next((n.replace('(L)', '').strip() for n in raw if '(L)' in n), None)
        names = [n.replace('(L)', '').strip() for n in raw]
        missing |= {n for n in names if n not in ID}
        ids = [ID.get(n) for n in names]
        forced, cond, rules = RULES[no]
        p = {'no': no, 'type': 'boss' if no == 10 else 'normal', 'enemyName': lead or '적군', 'title': m.group(2), 'enemies': {'ids': ids},
             'lines': {'default': s['lines']}, 'party': {'forced': forced, **cond}, 'hero': forced}
        if no in BOOST: p['enemies']['boost'] = BOOST[no]
        if lead: p['bossId'] = ID[lead]
        if rules: p['rules'] = rules
        if no == 10: p['final'] = True
        if s['after']: p['after'] = s['after']; p['afterTitle'] = '전투 후'
        ch['phases'].append(p)
    for L in [*ch.get('start', []), *ch.get('ending', []), *(x for p in ch['phases'] for x in p['lines']['default'] + p.get('after', []))]:
        if L['speaker'] not in ['내레이션', *NO_CARD] and L['speaker'] not in ID: missing.add(L['speaker'])
    if missing: raise SystemExit(f'카드 없음: {sorted(missing)}')
    assert len(ch['phases']) == 10 and all(len(p['enemies']['ids']) == 5 for p in ch['phases'])
    js = ('// ===== 스토리 챕터 5 「영원히 멈추지 않는 비」 (대본: vroyale/story/ch5_gyeoul.md, 글 문학순이 → python3 tools/ch5_import.py <파일> 로 생성. 직접 고쳐도 됨) =====\n'
          '// 단일 루트(single): 주인공 한겨울 (페이즈 10 은 진하린). party: banClass(속성 출전 불가) · maxGrade. enemies.boost: 스토리 전용 적 능력치. rules.undying: 쓰러지지 않는 적\n'
          'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n'
          f'window.STORY_DATA.noPortrait = [...new Set([...(window.STORY_DATA.noPortrait || []), ...{json.dumps(NO_CARD, ensure_ascii=False)}])];\n')
    open(os.path.join(ROOT, 'js/story-data-ch5.js'), 'w', encoding='utf-8').write(js)
    print('ok', len(ch['phases']), 'phases')

main(sys.argv[1] if len(sys.argv) > 1 else '/workspace/vroyale/story/ch5_gyeoul.md')
