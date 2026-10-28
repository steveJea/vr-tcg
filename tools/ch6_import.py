#!/usr/bin/env python3
"""CH6 시트(csv, gviz &sheet=CH6&headers=0) → js/story-data-ch6.js.  사용: python3 tools/ch6_import.py ch6.csv"""
import csv, json, re, sys
R = list(csv.reader(open(sys.argv[1], encoding='utf8')))
LEG = {r[16].strip(): r[17].strip() for r in R[1:] if len(r) > 17 and r[16].strip() and r[17].strip()}
LEG.update({'Y': '불량배Y', 'Z': '불량배Z', 'NA': '내레이션'})
def nm(k):
    n = LEG.get(k.strip(), k.strip()); m = re.match(r'^불량배([A-Z])$', n)
    return f'불량배-{m.group(1)}' if m else ('수상한 남자' if n == '수상한남자' else n)
IDS = {}
for f in ('data/cards.csv', 'data/npc_cards.csv'):
    for l in open(f, encoding='utf-8-sig').read().strip().splitlines()[1:]:
        v = l.split(','); IDS.setdefault(v[1], v[0])
def cid(n): return IDS[nm(n)]
FIX = [('한 때', '한때'), ('사고칠라', '사고 칠라'), ('다에요', '다예요'), ('모른척', '모른 척'), ('가만 두지', '가만두지'), ('정신차리자', '정신 차리자'), ('사흘 째', '사흘째'),
       ('빠져 나', '빠져나'), ('사라진지', '사라진 지'), ('밤 새', '밤새'), ('쓰러져있다', '쓰러져 있다'), ('온건데', '온 건데'), ('선그라스', '선글라스'), ('제가 내 동생', '네가 내 동생'),
       ('둘러 쌓았다', '둘러쌌다'), ('감쌓았다', '감쌌다'), ('될줄은', '될 줄은'), ('한자루', '한 자루'), ('싶은거야', '싶은 거야'), ('온 몸', '온몸'), ('건들이기', '건드리기'), ('왜그런', '왜 그런'), ('재미 없어졌어', '재미없어졌어'), ('비오는', '비 오는')]
def fx(t):
    for a, b in FIX: t = t.replace(a, b)
    return t.strip()
def line(r):
    sp = r[3].strip(); m = re.match(r'^(.+?)\s*\((화남|웃음)\)$', sp)
    L = {'speaker': nm(m.group(1) if m else sp), 'text': fx(r[4])}
    if m: L['expr'] = m.group(2)
    return L
BAN = {'임유리': '10325', '문지예': '10111', '문지철': '10112'}
start, phases, cur, after = [], [], None, False
for r in R[1:]:
    r = r + [''] * 20
    if r[0].strip().isdigit():
        n = int(r[0]); en = [x.strip() for x in r[7:12] if x.strip()]; ids = [cid(x) for x in en]
        forced = [cid(x) for x in r[2].split(',') if x.strip()]
        party = {'forced': forced}
        ex = [BAN[k] for k in BAN if k in r[12]]
        if ex: party['exclude'] = ex
        cur = {'no': n, 'type': 'boss' if n == 10 else 'normal', 'enemyName': nm(en[0]), 'title': fx(r[1]), 'enemies': {'ids': ids},
               'lines': {'default': []}, 'party': party, 'hero': forced[:1], 'bossId': ids[0]}
        if n == 10: cur['final'] = True
        phases.append(cur); after = False
    if not r[3].strip(): continue
    if r[5].strip() == '후' and cur: after = True; cur.setdefault('after', []); cur['afterTitle'] = '전투 후'
    L = line(r)
    (start if cur is None else cur['after'] if after else cur['lines']['default']).append(L)
tag = [l for l in R[1:] if len(l) > 18 and l[18].strip() == '스토리'][0][19].strip()
ch = {'id': 6, 'title': 'CHAPTER 6', 'subtitle': '마지막 대답', 'rewardCard': None, 'hero': IDS['문지아'], 'single': True, 'phases': phases,
      'tagline': fx(tag), 'warning': '이 챕터에는 폭력·죽음 묘사가 포함되어 있습니다.', 'start': start, 'ending': [], 'endingVideo': '5UXd2Yv5p3E'}
hdr = ('// ===== 스토리 챕터 6 「마지막 대답」 (시트 CH6 → python3 tools/ch6_import.py <csv> 로 생성. 직접 고쳐도 됨) =====\n'
       '// 단일 루트(single): 주인공 문지아 (1~4 페이즈는 문지예·문지철). 같은 NPC 적 여러 명 가능(ids 중복). 10페이즈 승리 후 대사에서 지아 사망 → 엔딩 영상\n')
open('js/story-data-ch6.js', 'w', encoding='utf8').write(hdr + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
print(len(start), [(p['no'], p['title'], [nm for nm in p['enemies']['ids']], len(p['lines']['default']), len(p.get('after', []))) for p in phases])
