#!/usr/bin/env python3
"""CH9 「기도」 · CH10 「마지막 랠리」 · CH11 「사라지지 않는 약속」 시트(csv) → js/story-data-ch9.js / ch10 / ch11.
사용: python3 tools/ch9_11_import.py <story__CH9.csv> <story__CH10.csv> <story__CH11.csv>
열 구성은 CH8 과 같음 (화자·적·강제배정 칸에 이니셜 대신 실명). 페이즈 수는 시트 그대로, 마지막 페이즈 = 보스.
출전 조건은 CH8 공용 규칙(noMale · exclude · solo · max). CH11 은 [염원] 최윤정 대여(chapter.loan, 챕터 끝나면 회수).
최윤희 복장은 사용자 결정(10/29)에 따라 페이즈별 초상화 slug (대사 줄 'slug')."""
import csv, json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__)); from power import card_power
SUB = {9: '기도', 10: '마지막 랠리', 11: '사라지지 않는 약속'}
VIDEO = {9: 'SZOOuvc5nak', 10: '1egJLy6rkPw', 11: 'w7kJ9vfJSgo'}   # 챕터 엔딩 영상 (YouTube id)
ALIAS = {'아빠': '윤희 아버지', 'NA': '내레이션', '나레이션': '내레이션', '왼쪽날개': '왼쪽 날개', '내래이션': '내레이션', '오른쪽날개': '오른쪽 날개'}
# 최윤희 복장 (0 = 챕터 시작 스토리). 없는 페이즈는 교복
OUT = {'school': {9: [0, 1, 2, 5, 9, 13, 15, 16, 17], 10: [6, 8]},
       'home': {9: [4, 6, 8, 12, 18], 10: [11, 13, 14, 16, 17, 18], 11: [5, 13, 16]},
       'casual': {9: [3, 7, 10, 11], 10: [2, 9], 11: [7]}, 'kid': {10: [1]}}
def outfit(c, n):
    for k, m in OUT.items():
        if n in m.get(c, []): return f'choi_yunhee_{k}'
    return 'choi_yunhee_school'
IDS, CARD = {}, {}
for f in ('data/cards.csv', 'data/npc_cards.csv'):
    for row in csv.DictReader(open(f, encoding='utf-8-sig')):
        IDS.setdefault(row['name'], row['id']); CARD.setdefault(row['id'], row)
def nm(k):
    n = ALIAS.get(k.strip(), k.strip()); m = re.match(r'^불량배-?([A-Za-z])$', n)
    return f'불량배-{m.group(1).upper()}' if m else n
num = lambda x: int(float(x)) if re.fullmatch(r'\d+(\.\d+)?', x.strip() or '-') else None
RATE = {'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06}

def party_of(cond, forced, defeat):
    p = {'forced': forced}; c = cond.replace(' ', '')
    if re.search(r'남성출전(불가|금지)', c): p['noMale'] = True
    if re.search(r'여성출전(불가|금지)', c): p['noFemale'] = True
    for who in re.findall(r'([^,/]+?)출전금지', c):
        if who in ('남성', '여성'): continue
        ex = [IDS[nm(w)] for w in who.split('·') if nm(w) in IDS]
        if ex: p['exclude'] = sorted(set(p.get('exclude', []) + ex))
    if '단독출전' in c or '단독출현' in c: p['solo'] = True
    m = re.search(r'(N|R|HR|SR|UR)이상출전(불가|금지)', c)   # 이 등급 이상 출전 불가 → maxGrade = 한 단계 아래 (필수 카드는 예외)
    if m: p['maxGrade'] = {'R': 'NORMAL', 'HR': 'RARE', 'SR': 'HIGH RARE', 'UR': 'SUPER RARE'}[m.group(1)]
    m = re.search(r'최대(\d)명', c)
    if m: p['max'] = int(m.group(1))
    p['mustLive'] = [IDS[nm(x.replace('사망', ''))] for x in defeat.split('/') if '사망' in x and nm(x.replace('사망', '')) in IDS]
    return p

def build(chn, path, loan=()):
    R = [r + [''] * 22 for r in csv.reader(open(path, encoding='utf8'))]
    start, phases, cur, after = [], [], None, False
    rows = R[1:]
    for i, r in enumerate(rows):
        no = num(r[0])
        if no:
            nxt = rows[i + 1] if i + 1 < len(rows) else [''] * 22
            en = [x.strip() for x in r[8:13] if x.strip()]; ids = [IDS[nm(x)] for x in en]
            forced = [IDS[nm(x)] for x in r[2].split(',') if x.strip()]
            flv = [num(x) for x in nxt[2].split(',') if x.strip()]
            party = party_of(r[13], forced, r[15])
            lv = {f: l for f, l in zip(forced, flv) if l}
            for lid in loan:   # 대여 인재 레벨 = 이 페이즈 필수 카드 레벨
                if lid not in lv and flv and flv[0]: lv[lid] = flv[0]
            if lv: party['levels'] = lv
            elv = {}
            for k, x in zip(ids, [num(x) for x in nxt[8:13]]):
                if x: elv[k] = max(elv.get(k, 0), x)
            cur = {'no': no, 'type': 'normal', 'enemyName': CARD[ids[0]]['name'], 'title': r[1].strip(), 'enemies': {'ids': ids, 'storyLv': elv},
                   'lines': {'default': []}, 'party': party, 'hero': forced[:1], 'bossId': ids[0]}
            m = re.search(r'(\d+)턴\s*후\s*(?:배틀레벨\s*(\d+)\s*)?(.+?)\s*\(\s*LV\s*(\d+)\s*\)\s*난입', r[16], re.I)   # 비고: N턴 후 [배틀레벨 B] 이름(LV L) 난입 → 아군 합류
            if m and nm(m.group(3)) in IDS: cur['joinAlly'] = {'id': IDS[nm(m.group(3))], 'afterTurn': int(m.group(1)), 'storyLevel': int(m.group(4)), 'battleLevel': int(m.group(2) or 1)}
            phases.append(cur); after = False
        if not r[3].strip() or not r[5].strip(): continue
        if r[6].strip() == '후' and cur: after = True; cur.setdefault('after', []); cur['afterTitle'] = '전투 후'
        sp = nm(r[3]); L = {'speaker': sp, 'text': r[5].strip()}
        e = r[4].strip()
        if e and sp != '내레이션': L['expr'] = e
        if sp == '최윤희': L['slug'] = outfit(chn, cur['no'] if cur else 0)
        (start if cur is None else cur['after'] if after else cur['lines']['default']).append(L)
    phases[-1].update(type='boss', final=True)
    last = 40
    for p in phases:
        flv = next(iter(p['party'].get('levels', {}).values()), None)   # 적 레벨 칸이 비면 이 페이즈 필수 카드 레벨
        lv = p['enemies'].pop('storyLv') or {k: flv or last for k in p['enemies']['ids']}
        last = max(lv.values()); b = {}
        for k, l in lv.items():
            c = CARD[k]; m = 1 + round(RATE[c['grade']] * (l - 1) * 100) / 100
            b[k] = {'HP': round(int(c['HP']) * m), 'ATK': round(int(c['ATK']) * m), 'DEF': round(int(c['DEF']) * m), 'storyLv': l}
            b[k]['power'] = card_power(c, **b[k])
        p['enemies']['boost'] = b
    hero = phases[0]['party']['forced'][0]
    ch = {'id': chn, 'title': f'CHAPTER {chn}', 'subtitle': SUB[chn], 'rewardCard': None, 'hero': hero, 'single': True, 'phases': phases,
          'tagline': '', 'warning': '이 챕터에는 괴롭힘·폭력·죽음 묘사가 포함되어 있습니다.', 'start': start, 'ending': [], 'endingVideo': VIDEO[chn]}
    if loan: ch['loan'] = list(loan)
    hdr = (f'// ===== 스토리 챕터 {chn} 「{SUB[chn]}」 (시트 CH{chn} → python3 tools/ch9_11_import.py <csv9> <csv10> <csv11> 로 생성. 직접 고쳐도 됨) =====\n'
           f'// 단일 루트(single) · 페이즈 {len(phases)}개 (마지막 보스). 최윤희 복장 = 대사 slug. 적 레벨은 시트 값 → enemies.boost' + (' · loan: 챕터 한정 대여 인재' if loan else '') + '\n')
    open(f'js/story-data-ch{chn}.js', 'w', encoding='utf8').write(hdr + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
    print(f'CH{chn}', len(phases), 'start', len(start))
    for p in phases: print(' ', p['no'], p['type'], p['title'], [CARD[i]['name'] for i in p['enemies']['ids']][:2], {k: v['storyLv'] for k, v in p['enemies']['boost'].items()}, json.dumps(p['party'], ensure_ascii=False))
    sps = {L['speaker'] for p in phases for L in p['lines']['default'] + p.get('after', [])} | {L['speaker'] for L in start}
    print('  speakers', sorted(sps))

# 한 챕터만: python3 tools/ch9_11_import.py --ch 11 <csv11>
if sys.argv[1] == '--ch':
    c = int(sys.argv[2]); build(c, sys.argv[3], loan=('10491',) if c == 11 else ()); sys.exit()
for chn, path in zip((9, 10, 11), sys.argv[1:4]):
    build(chn, path, loan=('10491',) if chn == 11 else ())
