#!/usr/bin/env python3
"""CH15 「검은 늪」 시트(csv) → js/story-data-ch15.js  (tools/ch14_import.py 기반)
사용: python3 tools/ch15_import.py <story__CH15.csv>
결정(10/31): 빈 보유마나 = MANA (단독 = 필수 코스트 ÷ 0.7) · P6 60 (시트) · P6 고세린 Lv80 · P11 윤진아·적 Lv83
  'HR (이하) 여성만 출전 가능' = maxGrade HIGH RARE + noMale · 'A, B 출전 금지' 둘 다 금지 · 'N턴 후 이름(lv L) 난입' (전투조건 칸) → joinAlly
  P16 불량배A Lv31(방패) 2턴 후 부활(rules.revive) · 10턴 생존 · 'OUT' = 사망
  평가관: 카드 없음 → PLACEHOLDER (임시 불량배-Z). 시트/카드에 '평가관' 생기면 PLACEHOLDER 에서 지우고 다시 실행
  엔딩 영상: 시트 'ending: <유튜브 링크>' 있으면 사용, 없으면 VIDEO (비어 있으면 영상 없음)
--- ch14_import.py 설명 ---
CH13 「예전의 너로」 시트(csv) → js/story-data-ch13.js
CH13 열: 13 보유마나(ph.mana, 제한 마나 고정) · 14 전투조건 · 15 승리조건 · 16 패배조건 · 17 비고
결정(10/31): 별점 STAR(내 턴 · 남은 마나 비율) · P15 Lv85 · 어린 안지수 (P1 an_jisu_7 · P2 an_jisu_12, 대사 slug = STORY_DATA.phaseSlug) · P14 임유리 대본(rules.aiScript)
--- ch12_import.py 설명 ---
CH12 「위대한 개츠비」 시트(csv) → js/story-data-ch12.js  (tools/ch9_11_import.py 기반)
사용: python3 tools/ch12_import.py <story__CH12.csv>
추가 조건: 코스트 N 이상 출전 불가(costBelow) · SR 이하만 출전 가능 / UR 출전 금지(maxGrade) · 이름(명중률 N% 하락)(rules.blind)
승리 조건: X턴 내 적 전멸(총 T턴)(rules.maxTurns) · 또는 N턴 생존(rules.survive). P21 은 시트가 비어 사용자 결정(10/31): Lv91 · 적 전멸 · 아군 전멸/턴 오버
--- 아래는 원본 설명 ---
사용: python3 tools/ch9_11_import.py <story__CH9.csv> <story__CH10.csv> <story__CH11.csv>
열 구성은 CH8 과 같음 (화자·적·강제배정 칸에 이니셜 대신 실명). 페이즈 수는 시트 그대로, 마지막 페이즈 = 보스.
출전 조건은 CH8 공용 규칙(noMale · exclude · solo · max). CH11 은 [염원] 최윤정 대여(chapter.loan, 챕터 끝나면 회수).
최윤희 복장은 사용자 결정(10/29)에 따라 페이즈별 초상화 slug (대사 줄 'slug')."""
import csv, json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__)); from power import card_power
SUB = {15: '검은 늪'}
VIDEO = {15: ''}
STAR = {1: (10, .3), 2: (9, .25), 3: (9, .25), 4: (8, .3), 5: (9, .25), 6: (7, .3), 7: (8, .3), 8: (10, .25), 9: (9, .25), 10: (5, 0), 11: (9, .25), 12: (8, .3), 13: (10, .2), 14: (5, 0), 15: (8, .3), 16: (10, 0)}
MANA = {1: 25, 2: 80, 3: 80, 4: 80, 5: 80, 7: 59, 8: 80, 9: 80, 10: 120, 11: 80, 12: 59, 13: 80, 14: 120, 15: 80, 16: 150}   # 시트가 빈 페이즈만
FLV = {6: 80, 11: 83}   # 필수 카드 레벨 칸이 빈 페이즈 (P11 적도 이 레벨)
PLACEHOLDER = {'평가관': '불량배-Z'}   # 카드 없는 적 → 임시 카드 (카드 생기면 지우기)
ALIAS = {'NA': '내레이션', '나레이션': '내레이션', '왼쪽날개': '왼쪽 날개', '내래이션': '내레이션', '오른쪽날개': '오른쪽 날개', '안혜찐': '안혜진', '한거린': '한서린'}
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
    k = k.strip()
    if k in PLACEHOLDER and k not in IDS: k = PLACEHOLDER[k]
    n = ALIAS.get(k.strip(), k.strip()); m = re.match(r'^불량배-?([A-Za-z])$', n)
    return f'불량배-{m.group(1).upper()}' if m else n
num = lambda x: int(float(x)) if re.fullmatch(r'\d+(\.\d+)?', x.strip() or '-') else None
RATE = {'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06}

def party_of(cond, forced, defeat):
    p = {'forced': forced}; c = cond.replace(' ', '')
    if re.search(r'남성출전(불가|금지)', c): p['noMale'] = True
    if re.search(r'여성출전(불가|금지)', c): p['noFemale'] = True
    pend = []   # 'A,B출전금지' → A·B 둘 다
    for tok in re.split(r'[,/]', c):
        m = re.match(r'^(.+?)출전(?:금지|불가)', tok)
        if not m:
            pend = pend + [tok] if nm(tok) in IDS else []; continue
        ex = [IDS[nm(w)] for w in pend + m.group(1).split('·') if nm(w) in IDS]; pend = []
        if ex: p['exclude'] = sorted(set(p.get('exclude', []) + ex))
    if '단독출전' in c or '단독출현' in c: p['solo'] = True
    m = re.search(r'(N|R|HR|SR|UR)이상출전(불가|금지)', c)   # 이 등급 이상 출전 불가 → maxGrade = 한 단계 아래 (필수 카드는 예외)
    if m: p['maxGrade'] = {'R': 'NORMAL', 'HR': 'RARE', 'SR': 'HIGH RARE', 'UR': 'SUPER RARE'}[m.group(1)]
    m = re.search(r'코스트(\d+)이상출전(불가|금지)', c)
    if m: p['costBelow'] = int(m.group(1))
    if re.search(r'SR이하만출전가능', c) or re.search(r'(?<![A-Z])UR출전(불가|금지)', c): p['maxGrade'] = 'SUPER RARE'
    if re.search(r'HR(이하)?여성만출전가능', c): p['maxGrade'] = 'HIGH RARE'; p['noMale'] = True
    m = re.search(r'최대(\d)명', c)
    if m: p['max'] = int(m.group(1))
    p['mustLive'] = [IDS[nm(x.replace('사망', ''))] for x in re.split(r'[/,]', defeat) if '사망' in x and nm(x.replace('사망', '')) in IDS]
    return p

def build(chn, path, loan=()):
    R = [r + [''] * 22 for r in csv.reader(open(path, encoding='utf8'))]
    start, phases, cur, after = [], [], None, False
    rows = R[1:]
    for r in R:
        for x in r:
            m = re.search(r'ending:\s*https?://(?:youtu\.be/|www\.youtube\.com/watch\?v=)([\w-]{6,20})', x)
            if m: VIDEO[chn] = m.group(1)
    for i, r in enumerate(rows):
        no = num(r[0])
        if no:
            nxt = rows[i + 1] if i + 1 < len(rows) else [''] * 22
            en = [x.strip() for x in r[8:13] if x.strip()]; ids = [IDS[nm(x)] for x in en]
            forced = [IDS[nm(x)] for x in r[2].split(',') if x.strip() and x.strip() != '없음']
            flv = [num(x) for x in nxt[2].split(',') if x.strip()] or ([FLV[no]] if no in FLV else [])   # P15 레벨 비어 있음 → 85
            party = party_of(r[14], forced, r[16].replace('KO', '사망').replace('OUT', '사망'))   # '안지수 KO' = 사망 패배
            rules = {}
            for who, pct in re.findall(r'([^,(]+?)\(\s*명중률\s*(\d+)%\s*(?:하락|저하)\s*\)', r[14]):
                if nm(who) in IDS: rules.setdefault('blind', {})[IDS[nm(who)]] = int(pct) / 100
            m = re.search(r'총\s*(\d+)\s*턴', r[15])
            if m: rules['maxTurns'] = int(m.group(1))
            m = re.search(r'(\d+)\s*턴\s*생존', r[15])
            if m: rules['survive'] = int(m.group(1))
            party['mustLive'] = [x for x in party['mustLive'] if x in forced] or party['mustLive']
            lv = {f: l for f, l in zip(forced, flv) if l}
            for lid in loan:   # 대여 인재 레벨 = 이 페이즈 필수 카드 레벨
                if lid not in lv and flv and flv[0]: lv[lid] = flv[0]
            if lv: party['levels'] = lv
            elv = {}
            for k, x in zip(ids, [num(x) for x in nxt[8:13]]):
                if x: elv[k] = max(elv.get(k, 0), x)
            cur = {'no': no, 'type': 'normal', 'enemyName': CARD[ids[0]]['name'], 'title': r[1].strip(), 'enemies': {'ids': ids, 'storyLv': elv},
                   'lines': {'default': []}, 'party': party, 'hero': forced[:1], 'bossId': ids[0]}
            m = re.search(r'(\d+)턴\s*후\s*(?:배틀레벨\s*(\d+)\s*)?(.+?)\s*\(\s*LV\s*(\d+)\s*\)\s*난입', r[14] + ' ' + r[17], re.I)   # 비고: N턴 후 [배틀레벨 B] 이름(LV L) 난입 → 아군 합류
            if m and nm(m.group(3)) in IDS: cur['joinAlly'] = {'id': IDS[nm(m.group(3))], 'afterTurn': int(m.group(1)), 'storyLevel': int(m.group(4)), 'battleLevel': int(m.group(2) or 1)}
            for who, d in re.findall(r'([^,]+?)\s*(\d+)\s*턴\s*후\s*부활', r[14]):
                if nm(who) in IDS: rules.setdefault('revive', []).append({'id': IDS[nm(who)], 'delay': int(d), 'level': 'keep'})
            if rules: cur['rules'] = rules
            if num(r[13]) is not None: cur['mana'] = num(r[13])
            elif no in MANA: cur['mana'] = MANA[no]
            if no in STAR: cur['starTurns'], cur['starMana'] = STAR[no]
            cur['enemies']['storyLv'] = elv
            phases.append(cur); after = False
        if not r[3].strip() or not r[5].strip(): continue
        if r[6].strip() == '후' and cur: after = True; cur.setdefault('after', []); cur['afterTitle'] = '전투 후'
        sp = nm(r[3]); L = {'speaker': sp, 'text': r[5].strip()}
        e = r[4].strip()
        if e and sp != '내레이션': L['expr'] = e
        (start if cur is None else cur['after'] if after else cur['lines']['default']).append(L)
    phases[-1].update(final=True)   # CH15 P16: 10턴 생존
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
    hdr = (f'// ===== 스토리 챕터 {chn} 「{SUB[chn]}」 (시트 CH{chn} → python3 tools/ch15_import.py <csv15> 로 생성. 직접 고쳐도 됨) =====\n'
           f'// 단일 루트(single) · 페이즈 {len(phases)}개 (마지막 보스). 초상화 = chapterPortraits[15]. 적 레벨은 시트 값 → enemies.boost' + (' · loan: 챕터 한정 대여 인재' if loan else '') + '\n')
    open(f'js/story-data-ch{chn}.js', 'w', encoding='utf8').write(hdr + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
    print(f'CH{chn}', len(phases), 'start', len(start))
    for p in phases: print(' ', p['no'], p['type'], p['title'], [CARD[i]['name'] for i in p['enemies']['ids']][:2], {k: v['storyLv'] for k, v in p['enemies']['boost'].items()}, json.dumps(p['party'], ensure_ascii=False))
    sps = {L['speaker'] for p in phases for L in p['lines']['default'] + p.get('after', [])} | {L['speaker'] for L in start}
    print('  speakers', sorted(sps))

build(15, sys.argv[1])
