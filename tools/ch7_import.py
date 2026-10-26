#!/usr/bin/env python3
"""CH7 시트(csv export gid=1405852543) → js/story-data-ch7.js.  사용: python3 tools/ch7_import.py ch7.csv
열: 0 phase · 1 제목 · 2 강제배정(다음 줄: 레벨) · 3 대상 · 4 표정 · 5 대화 · 6 진행시점 · 7 멀티미디어 · 8~12 적(다음 줄: 레벨) · 13 전투조건 · 14 승리 · 15 패배 · 17/18 이니셜 범례 · 19 부제"""
import csv, json, re, sys
R = list(csv.reader(open(sys.argv[1], encoding='utf8')))
R = [r + [''] * 22 for r in R]
LEG = {r[17].strip(): r[18].strip() for r in R[1:] if r[17].strip() and r[18].strip()}
LEG.update({'NA': '내레이션', '소녀': '소녀1', '아버지': '유연 아버지', '어머니': '유연 어머니'})   # '소녀'(7페이즈 첫 대사) = 소녀1 로 가정
def nm(k):
    n = LEG.get(k.strip(), k.strip()); m = re.match(r'^불량배([A-Z])$', n)
    return f'불량배-{m.group(1)}' if m else n
IDS = {}
for f in ('data/cards.csv', 'data/npc_cards.csv'):
    for l in open(f, encoding='utf-8-sig').read().strip().splitlines()[1:]:
        v = l.split(','); IDS.setdefault(v[1], v[0]); IDS.setdefault(v[0], v[0])
def cid(n): return IDS[nm(n)]
EXPR = {'징닌': '장난'}
FIX = [('같은애', '같은 애'), ('이런게', '이런 게'), ('건들였어', '건드렸어'), ('거에요', '거예요'), ('기고만장 했', '기고만장했'), ('어쩔건데', '어쩔 건데'), ('그 분은', '그분은'),
       ('홍기오라버니', '홍기 오라버니'), ('에워쌓았다', '에워쌌다'), ('왜이러세요', '왜 이러세요'), ('무슨일인뎅', '무슨 일인뎅'), ('손 끝', '손끝'), ('10년만에', '10년 만에'),
       ('화 내는', '화내는'), ('영화보러', '영화 보러'), ('태안오빠', '태안 오빠'), ('남내의', '남매의'), ('직업때문인', '직업 때문인'), ('조차 무뚝뚝', '조차도 무뚝뚝'),
       ('좋은아침', '좋은 아침'), ('건냈다', '건넸다'), ('일찍와라', '일찍 와라'), ('왜이러실까', '왜 이러실까'), ('하염 없이', '하염없이'), ('연락 하기', '연락하기'), ('내말', '내 말'),
       ('봄 비가', '봄비가'), ('재미 없는', '재미없는'), ('아 컸네', '다 컸네'), ('말 안해도', '말 안 해도'), ('먹어주겠지', '먹어 주겠지'), ('입금은 따로 해줄게', '입금은 따로 해 줄게')]
def fx(t):
    for a, b in FIX: t = t.replace(a, b)
    return t.strip()
YY, GE, HK = IDS['민유연'], IDS['유가을'], IDS['민홍기']
def party_of(cond, forced, defeat, n_=None):
    p = {'forced': forced}
    c = cond.replace(' ', '')
    if '남성출전금지' in c: p['noMale'] = True
    if '여성출전금지' in c: p['noFemale'] = True          # (민유연 제외) = 필수 카드는 조건 예외
    ex = [IDS[n] for n in ('민유연', '유가을', '민홍기') if f'{n}' in c and '출전금지' in c and not (n == '민유연' and '민유연제외' in c)]
    if '유가을,민홍기출전금지' in c: ex = [GE, HK]
    if ex: p['exclude'] = ex
    m = re.search(r'최대(\d)명', c)
    if m: p['max'] = int(m.group(1))
    if 'UR출전금지' in c: p['maxGrade'] = 'SUPER RARE'   # UR 이상 출전 불가로 처리 (CH5 와 같은 방식)
    if '추가편성금지' in c: p['noExtra'] = True; p['max'] = len(forced)
    if n_ == 7:   # 사용자 결정(10/26): 쓰레기 4인방 필수 + 품성(MOR) 40 미만 남성 1장 추가 (최대 5장)
        p.pop('noExtra', None); p['noFemale'] = True; p['maxMor'] = 39; p['max'] = len(forced) + 1   # 4인방 필수 + 1장
    live = [IDS[nm(k)] for k in re.findall(r'([A-Z]{2})\s*사망', defeat)]
    p['mustLive'] = live
    return p
start, phases, cur, after = [], [], None, False
rows = R[1:]
for i, r in enumerate(rows):
    if r[0].strip().isdigit():
        n = int(r[0]); nxt = rows[i + 1] if i + 1 < len(rows) else [''] * 22
        en = [x.strip() for x in r[8:13] if x.strip()]; ids = [cid(x) for x in en]
        forced = [cid(x) for x in r[2].split(',') if x.strip()]
        flv = [x.strip() for x in nxt[2].split(',') if x.strip()]
        elv = [x.strip() for x in nxt[8:13]]
        party = party_of(r[13], forced, r[15], n)
        if n == 6: party['mustLive'] = []   # 사용자 결정(10/26): 6페이즈는 민유연이 쓰러져도 패배 아님 (아군 전멸만)
        if flv: party['levels'] = {f: int(l) for f, l in zip(forced, flv)}
        lv = {}
        for k, x in zip(ids, elv):
            if x.isdigit(): lv[k] = max(lv.get(k, 0), int(x))
        cur = {'no': n, 'type': 'boss' if n == 10 else 'normal', 'enemyName': nm(en[0]), 'title': fx(r[1]), 'enemies': {'ids': ids, 'storyLv': lv or None},
               'lines': {'default': []}, 'party': party, 'hero': forced[:1], 'bossId': ids[0]}
        if n == 10: cur['final'] = True
        phases.append(cur); after = False
    if not r[3].strip() or not r[5].strip(): continue
    if r[6].strip() == '후' and cur: after = True; cur.setdefault('after', []); cur['afterTitle'] = '전투 후'
    sp = nm(r[3]); L = {'speaker': sp, 'text': fx(r[5])}
    e = EXPR.get(r[4].strip(), r[4].strip())
    if e and sp != '내레이션': L['expr'] = e
    mm = re.match(r'CH07-(\d+)', r[7].strip())
    if mm: L['video' if mm.group(1) == '15' else 'image'] = f"video/story/ch7-{mm.group(1)}.mp4" if mm.group(1) == '15' else f"img/story/ch7-{mm.group(1)}.webp"
    (start if cur is None else cur['after'] if after else cur['lines']['default']).append(L)
# 적 스토리 레벨 → boost (스토리 레벨 규칙: 등급별 레벨당 기본 스탯 +%, js/pvp-core.js snapCard 와 같음). 레벨 없는 페이즈(6~10)는 직전 페이즈의 최고 레벨
RATE = {'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06}
CARD = {}
for f in ('data/cards.csv', 'data/npc_cards.csv'):
    for row in csv.DictReader(open(f, encoding='utf-8-sig')): CARD.setdefault(row['id'], row)
last = 1
for p in phases:
    lv = p['enemies'].pop('storyLv') or {k: last for k in p['enemies']['ids']}
    last = max(lv.values())
    if p['no'] == 6: lv = {k: 30 for k in lv}   # 사용자 결정(10/26): 6페이즈 유가을 Lv30 (다음 페이즈 기본 레벨 60 은 그대로)
    b = {}
    for k, l in lv.items():
        c = CARD[k]; m = 1 + round(RATE[c['grade']] * (l - 1) * 100) / 100
        b[k] = {'HP': round(int(c['HP']) * m), 'ATK': round(int(c['ATK']) * m), 'DEF': round(int(c['DEF']) * m), 'power': round(int(c['power']) * m), 'storyLv': l}
    p['enemies']['boost'] = b
sub = R[1][19].strip() or 'THE BELL JAR'
ch = {'id': 7, 'title': 'CHAPTER 7', 'subtitle': sub, 'rewardCard': None, 'hero': YY, 'single': True, 'phases': phases,
      'tagline': '', 'warning': '이 챕터에는 학교 폭력·협박·자해 암시 묘사가 포함되어 있습니다.', 'start': start, 'ending': [], 'endingVideo': '0aHko1s4-tA'}
hdr = ('// ===== 스토리 챕터 7 「THE BELL JAR」 (시트 CH7 → python3 tools/ch7_import.py <csv> 로 생성. 직접 고쳐도 됨) =====\n'
       '// 단일 루트(single): 주인공 민유연 (5페이즈 유가을 단독, 7페이즈 강태안·강태준·이민수·김철민). 적 레벨은 시트 값 → enemies.boost (스토리 Lv 스탯)\n')
open('js/story-data-ch7.js', 'w', encoding='utf8').write(hdr + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
for p in phases: print(p['no'], p['title'], [nm_ for nm_ in p['enemies']['ids']], {k: v['storyLv'] for k, v in p['enemies']['boost'].items()}, json.dumps(p['party'], ensure_ascii=False), len(p['lines']['default']), len(p.get('after', [])))
print('start', len(start))
