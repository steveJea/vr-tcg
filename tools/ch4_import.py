#!/usr/bin/env python3
"""챕터 4 대본(md) → js/story-data-ch4.js
사용법: python3 tools/ch4_import.py <대본 파일 ch4_minchae.md>
단일 루트(주인공 이민채, 페이즈 10 은 임유리). 페이즈 10 의 '이민채(L)' = NPC 카드 [각성] 이민채 (data/npc_cards.csv), 나머지 이민채 = 일반 이민채(분신). '적: 이름, 이름(L)' 의 (L) = 상대 리더(전투 화면 상대 이름, 보스전이면 보스 카드).
페이즈별 강제 배정·추가 조건은 아래 RULES 표 (구글 시트 '어비스게이트 스토리' 탭 '챕터4' 기준).
"""
import csv, json, os, re, sys
ROOT = os.path.join(os.path.dirname(__file__), '..')
rows = list(csv.DictReader(open(os.path.join(ROOT, 'data/cards.csv'), encoding='utf-8-sig')))
npc = list(csv.DictReader(open(os.path.join(ROOT, 'data/npc_cards.csv'), encoding='utf-8-sig')))
ID = {r['name']: r['id'] for r in rows}
MC, YR, JS, YN = ID['이민채'], ID['임유리'], ID['김지수'], ID['오유나']
AWAKE = next(r['id'] for r in npc if r['name'] == '[각성] 이민채')
# 페이즈 → (필수 출전, 추가 조건, 전투 규칙 rules)
#  rules: mustLive(내 카드 id 가 쓰러지면 패배) · revive([{id, level: 1|'keep', times}] 적 카드 1턴 후 부활) · invuln(피해 없는 적 카드) · expire(invuln 카드 자동 사망 라운드)
ML = {'mustLive': [MC]}
RULES = {
  1: ([MC], {}, None), 2: ([MC], {}, None), 3: ([MC], {}, None),
  4: ([MC, YR], {}, ML), 5: ([MC, YR], {}, ML), 6: ([MC], {}, ML), 7: ([MC], {}, ML),
  8: ([MC], {}, {'revive': [{'id': JS, 'level': 1, 'delay': 2}]}),
  9: ([MC], {}, {'revive': [{'id': JS, 'level': 'keep', 'delay': 2}, {'id': YN, 'level': 'keep', 'delay': 2}]}),
  10: ([YR], {}, {'invuln': AWAKE, 'expire': 10, 'revive': [{'id': MC, 'level': 1, 'delay': 1}]}),
}
RULE_TXT = {4: '💔 이민채가 쓰러지면 패배', 5: '💔 이민채가 쓰러지면 패배', 6: '💔 이민채가 쓰러지면 패배', 7: '💔 이민채가 쓰러지면 패배',
  8: '🩸 김지수는 쓰러지면 2턴 후 Lv1 로 부활 · 그 전에 적을 모두 쓰러뜨리면 승리', 9: '🩸 김지수·오유나는 쓰러지면 2턴 후 레벨 그대로 부활 · 그 전에 적을 모두 쓰러뜨리면 승리',
  10: '🔥 각성 이민채는 피해를 입지 않고 10턴 후 스스로 쓰러져요 · 분신 이민채는 쓰러지면 1턴 후 Lv1 로 부활 · 10턴을 버티세요!'}
PHASE8 = ['윤은별', '황보예', '김지우', '오유나', '김지수']
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
    secs = parse(src); ch = {'id': 4, 'title': 'CHAPTER 4', 'subtitle': '카르밀라', 'rewardCard': None, 'hero': MC, 'single': True, 'phases': []}
    missing = set()
    for s in secs:
        h = s['head']
        if h.startswith('이민채'): continue
        if h.startswith('캐릭터 소개'): ch['tagline'] = '\n'.join(s['text']); continue
        if h.startswith('시작 스토리'): ch['start'] = s['lines']; continue
        if h.startswith('엔딩'): ch['ending'] = s['lines']; continue
        m = re.match(r'Phase\.(\d+)\s*「(.+?)」', h)
        if not m: continue
        no = int(m.group(1)); raw = s['enemies']
        if no == 10:
            assert [n.replace('(L)', '').strip() for n in raw] == ['이민채'] * 5 and '(L)' in raw[0], raw
            ids, lead = [AWAKE] + [MC] * 4, '[각성] 이민채'
        else:
            lead = next((n.replace('(L)', '').strip() for n in raw if '(L)' in n), None)
            names = [n.replace('(L)', '').strip() for n in raw]
            if no == 8: assert sorted(names) == sorted(PHASE8) and lead == '김지수', names
            missing |= {n for n in names if n not in ID}
            ids = [ID.get(n) for n in names]
        forced, cond, rules = RULES[no]
        p = {'no': no, 'type': 'normal', 'enemyName': lead or '적군', 'title': m.group(2), 'enemies': {'ids': ids},
             'lines': {'default': s['lines']}, 'party': {'forced': forced, **cond}, 'hero': forced}
        if lead: p['bossId'] = AWAKE if no == 10 else ID[lead]
        if rules: p['rules'] = rules
        if no in RULE_TXT: p['tip'] = RULE_TXT[no]
        if no == 10: p['final'] = True; p['bgm'] = 'boss'
        if s['after']: p['after'] = s['after']; p['afterTitle'] = '전투 후'
        ch['phases'].append(p)
    for L in [*ch.get('start', []), *ch.get('ending', []), *(x for p in ch['phases'] for x in p['lines']['default'] + p.get('after', []))]:
        if L['speaker'] != '내레이션' and L['speaker'] not in ID: missing.add(L['speaker'])
    if missing: raise SystemExit(f'카드 없음: {sorted(missing)}')
    assert len(ch['phases']) == 10 and all(len(p['enemies']['ids']) == 5 for p in ch['phases'])
    js = ('// ===== 스토리 챕터 4 「카르밀라」 (대본: vroyale/story/ch4_minchae.md, 글 문학순이 → python3 tools/ch4_import.py <파일> 로 생성. 직접 고쳐도 됨) =====\n'
          '// 단일 루트(single): 주인공 이민채 (페이즈 10 은 임유리). rules: mustLive · revive · invuln · expire (js/game.js storyTurnRules), final = 챕터 엔딩 페이즈\n'
          'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
    open(os.path.join(ROOT, 'js/story-data-ch4.js'), 'w', encoding='utf-8').write(js)
    print('ok', len(ch['phases']), 'phases')

main(sys.argv[1] if len(sys.argv) > 1 else '/workspace/vroyale/story/ch4_minchae.md')
