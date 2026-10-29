#!/usr/bin/env python3
"""CH8 「주홍글씨」 시트(csv) → js/story-data-ch8.js.  사용: python3 tools/ch8_import.py story__CH8.csv
열: 0 phase · 1 제목 · 2 강제배정(다음 줄: 레벨) · 3 대상 · 4 표정 · 5 대화 · 6 진행시점(전/후) · 7 멀티미디어 · 8~12 적(다음 줄: 레벨) · 13 전투조건 · 14 승리 · 15 패배 · 17/18 이니셜 범례 · 19 부제
페이즈 수는 시트 그대로(15). 마지막 페이즈 = 보스. 출전 조건은 공용 규칙(noMale · exclude · solo · max)으로 변환 → CH9~11 도 같은 함수 재사용."""
import csv, json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__)); from power import card_power
CHN = 8
R = [r + [''] * 22 for r in csv.reader(open(sys.argv[1], encoding='utf8'))]
LEG = {r[17].strip(): r[18].strip() for r in R[1:] if r[17].strip() and r[18].strip()}
# 사용자 결정(10/29): JY4 = [염원] 안지윤 · 학부모N = 가해자 부모N(주홍글씨N 초상화) · 악마1/2 = 하급/상급 몽마(카드 그림)
LEG.update({'NA': '내레이션', 'JY4': '[염원] 안지윤', 'DV1': '하급 몽마', 'DV2': '상급 몽마'})
ENEMY = {f'A{i}': f'가해자 부모{i}' for i in range(1, 7)}   # 적 칸 A1~A6 → 카드 이름
def nm(k):
    n = LEG.get(k.strip(), k.strip()); m = re.match(r'^불량배-?([A-Z])$', n)
    return f'불량배-{m.group(1)}' if m else n
IDS, CARD = {}, {}
for f in ('data/cards.csv', 'data/npc_cards.csv'):
    for row in csv.DictReader(open(f, encoding='utf-8-sig')):
        IDS.setdefault(row['name'], row['id']); CARD.setdefault(row['id'], row)
def cid(k): return IDS[ENEMY.get(k.strip()) or nm(k)]
num = lambda x: int(float(x)) if re.fullmatch(r'\d+(\.\d+)?', x.strip() or '-') else None

def party_of(cond, forced, defeat):
    """공용 출전 규칙: '남성 출전 불가' → noMale · 'X 출전 금지' → exclude · 'X 단독 출전' → solo · '최대 N명' → max"""
    p = {'forced': forced}; c = cond.replace(' ', '')
    if re.search(r'남성출전(불가|금지)', c): p['noMale'] = True
    if re.search(r'여성출전(불가|금지)', c): p['noFemale'] = True
    for who in re.findall(r'([^,/]+?)출전금지', c):
        if who in ('남성', '여성'): continue
        ex = [IDS[nm(w)] for w in who.split('·') if nm(w) in IDS]
        if ex: p['exclude'] = sorted(set(p.get('exclude', []) + ex))
    if '단독출전' in c: p['solo'] = True
    m = re.search(r'최대(\d)명', c)
    if m: p['max'] = int(m.group(1))
    p['mustLive'] = [IDS[nm(k)] for k in re.findall(r'([A-Z]{1,3}\d?)\s*사망', defeat)]
    return p

start, phases, cur, after, lastF = [], [], None, False, {}
rows = R[1:]
for i, r in enumerate(rows):
    no = num(r[0])
    if no:
        nxt = rows[i + 1] if i + 1 < len(rows) else [''] * 22
        en = [x.strip() for x in r[8:13] if x.strip()]; ids = [cid(x) for x in en]
        forced = [IDS[nm(x)] for x in r[2].split(',') if x.strip()]
        flv = [num(x) for x in nxt[2].split(',') if x.strip()]
        party = party_of(r[13], forced, r[15])
        lv = {f: l for f, l in zip(forced, flv) if l} or {f: lastF[f] for f in forced if f in lastF}   # 레벨 없는 칸(P4) = 직전 페이즈 레벨
        if lv: party['levels'] = lv; lastF.update(lv)
        elv = {}
        for k, x in zip(ids, [num(x) for x in nxt[8:13]]):
            if x: elv[k] = max(elv.get(k, 0), x)
        cur = {'no': no, 'type': 'normal', 'enemyName': cid(en[0]) and CARD[cid(en[0])]['name'], 'title': r[1].strip(), 'enemies': {'ids': ids, 'storyLv': elv},
               'lines': {'default': []}, 'party': party, 'hero': forced[:1], 'bossId': ids[0]}
        phases.append(cur); after = False
    if not r[3].strip() or not r[5].strip(): continue
    if r[6].strip() == '후' and cur: after = True; cur.setdefault('after', []); cur['afterTitle'] = '전투 후'
    sp = nm(r[3]); L = {'speaker': sp, 'text': r[5].strip()}
    e = r[4].strip()
    if e and sp != '내레이션': L['expr'] = e
    mm = re.match(r'CH08-(\d+)', r[7].strip())
    if mm: L['image'] = f'img/story/ch8-{mm.group(1)}.webp'
    (start if cur is None else cur['after'] if after else cur['lines']['default']).append(L)
phases[-1].update(type='boss', final=True)   # 마지막 페이즈 = 보스 (CH7 P10 과 같은 방식)
RATE = {'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06}
last = 40
for p in phases:
    lv = p['enemies'].pop('storyLv') or {k: last for k in p['enemies']['ids']}
    last = max(lv.values()); b = {}
    for k, l in lv.items():
        c = CARD[k]; m = 1 + round(RATE[c['grade']] * (l - 1) * 100) / 100
        b[k] = {'HP': round(int(c['HP']) * m), 'ATK': round(int(c['ATK']) * m), 'DEF': round(int(c['DEF']) * m), 'storyLv': l}
        b[k]['power'] = card_power(c, **b[k])
    p['enemies']['boost'] = b
JY = IDS['안지윤']
ch = {'id': CHN, 'title': f'CHAPTER {CHN}', 'subtitle': R[1][19].strip() or '주홍글씨', 'rewardCard': None, 'hero': JY, 'single': True, 'phases': phases,
      'tagline': '', 'warning': '이 챕터에는 따돌림·괴롭힘·죽음 묘사가 포함되어 있습니다.', 'start': start, 'ending': []}
hdr = (f'// ===== 스토리 챕터 {CHN} 「{ch["subtitle"]}」 (시트 CH{CHN} → python3 tools/ch8_import.py <csv> 로 생성. 직접 고쳐도 됨) =====\n'
       f'// 단일 루트(single): 주인공 안지윤 · 페이즈 {len(phases)}개 (마지막 보스). 안소라 페이즈(1·2·9·11)는 안소라 게스트. 적 레벨은 시트 값 → enemies.boost\n')
open(f'js/story-data-ch{CHN}.js', 'w', encoding='utf8').write(hdr + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
for p in phases: print(p['no'], p['type'], p['title'], p['enemies']['ids'], {k: v['storyLv'] for k, v in p['enemies']['boost'].items()}, json.dumps(p['party'], ensure_ascii=False), len(p['lines']['default']), len(p.get('after', [])))
print('start', len(start), 'speakers', sorted({L['speaker'] for p in phases for L in p['lines']['default'] + p.get('after', [])} | {L['speaker'] for L in start}))
