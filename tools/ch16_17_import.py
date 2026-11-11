#!/usr/bin/env python3
"""CH16 「젊은 베르테르의 슬픔」 · CH17 「폭풍의 언덕」
대사: 스토리 시트 CSV / 전투: 전투정리2 (스토리 시트의 전투 칸은 비어 있음)
사용: python3 tools/ch16_17_import.py /tmp/ch1617-sheet/CH16.csv /tmp/ch1617-sheet/CH17.csv
엔딩 영상: CH16 Hr8_z9yFB_g · CH17 jhBi0xojOOM (형님 채팅 16:59 KST)
조윤이 ch16 = jo_yuni_school · 최윤희 ch17 = choi_yunhee_school
국선 엄마/아빠 · 영순 이모 = 초상화 없음
16-11 적5 이영아(10306) 유지. 16-11 승리는 최국선 사망(mustKill; 윤진아를 남기고 이길 수 있음). 16-1/16-2·CH17 빈 승리조건 → 적 전멸, 빈 패배조건은 다른 동형 페이즈와 같게.
"""
import csv, json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__)); from power import card_power

SUB = {16: '젊은 베르테르의 슬픔', 17: '폭풍의 언덕'}
VIDEO = {16: 'Hr8_z9yFB_g', 17: 'jhBi0xojOOM'}
ALIAS = {
    'NA': '내레이션', '나레이션': '내레이션', '내래이션': '내레이션',
    'D': '불량배-D',
}
for L in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
    ALIAS[f'불량배{L}'] = f'불량배-{L}'
    ALIAS[L] = f'불량배-{L}'

# 전투정리2 (C,P,…). 16-1/16-2 승패는 시트 빈칸 → 16-3과 동일하게 채움. 17 빈 승리 = 적 전멸.
# keys: forced, flv, elv, blv, boss, enemies, first, bans, win, lose, note, pts, mana, story
BATTLE = {
16: {
  1:  dict(forced=['최국선'], flv=40, elv=45, enemies=['강두식','A','B','C','D'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  2:  dict(forced=['최국선'], flv=40, elv=45, enemies=['E','A','B','C','D'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  3:  dict(forced=['최국선'], flv=40, elv=45, enemies=['M','L','M','A','B'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  4:  dict(forced=['최국선'], flv=40, elv=45, enemies=['O','C','D','N','J'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  5:  dict(forced=['최국선'], flv=40, elv=45, enemies=['P','Q','R','E','F'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  6:  dict(forced=['박성관','고정태','서태우'], flv=50, elv=45, enemies=['조윤이'], first='아군', bans=['추가 편성 불가'], win='조윤이 사망', lose='필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=200),
  7:  dict(forced=['최국선'], flv=40, elv=45, enemies=['H','G','C','B','A'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  8:  dict(forced=['최국선'], flv=40, elv=45, enemies=['I','S','T','U','V'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  9:  dict(forced=['최국선'], flv=40, elv=45, enemies=['J','D','W','X','Y'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
 10:  dict(forced=['최국선'], flv=40, elv=45, blv=2, enemies=['고정태','A','B','K','L'], first='아군', bans=['여성','SR 초과'], win='적 전멸', lose='최국선 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
 11:  dict(forced=['소민섭'], flv=60, elv=45, boss='최국선', enemies=['윤진아','조윤이','동지선','주예서','이영아'], first='아군', bans=['여성'], win='최국선 사망', lose='소민섭 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', note='각성윤진아', pts=3, mana=200),
 12:  dict(story=True, pts=3, mana=100),
},
17: {
  1:  dict(forced=['이영하'], flv=45, elv=40, enemies=['E','D','C','B','A'], first='아군', bans=['남성','SR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  2:  dict(forced=['이영하'], flv=45, elv=40, enemies=['J','G','F','R','D'], first='아군', bans=['남성','SR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  3:  dict(forced=['이영하'], flv=45, elv=40, enemies=['고정태','J','J','J','J'], first='아군', bans=['남성'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  4:  dict(forced=['이영하'], flv=45, elv=40, enemies=['P','O','N','M','L'], first='아군', bans=['HR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  5:  dict(forced=['이영하'], flv=45, elv=40, enemies=['P','G','E','D','K'], first='아군', bans=['HR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  6:  dict(forced=['이영하'], flv=45, elv=40, enemies=['S','G','G','G','G'], first='아군', bans=['HR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  7:  dict(story=True, pts=3),
  8:  dict(forced=['이영하'], flv=45, elv=40, enemies=['고정태','V','V','V','V'], first='아군', bans=['SR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
  9:  dict(forced=['이영하'], flv=45, elv=40, enemies=['X','X','X','X','X'], first='아군', bans=['HR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
 10:  dict(forced=['이영하'], flv=45, elv=45, enemies=['고정태','X','X','X','X'], first='아군', bans=['HR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
 11:  dict(forced=['이영하'], flv=45, elv=45, enemies=['고정태','X','X','X','X'], first='아군', bans=['HR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
 12:  dict(story=True, pts=3),
 13:  dict(forced=['이영하'], flv=45, elv=50, enemies=['소민섭','고정태','I','I','I'], first='아군', bans=['SR 초과'], win='적 전멸', lose='이영하 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과', pts=3, mana=100),
 14:  dict(forced=['이영하'], flv=45, elv=50, boss='소민섭', enemies=['고정태','I','I','I','I'], first='적군', bans=['추가 편성 불가'], win='적 전멸', lose='필수캐 미소환(2턴), 이지영 사망, 20턴 초과', note='이지영난입', pts=3, mana=200),
 15:  dict(story=True, pts=3),
},
}

IDS, CARD = {}, {}
for f in ('data/cards.csv', 'data/npc_cards.csv'):
    for row in csv.DictReader(open(f, encoding='utf-8-sig')):
        IDS.setdefault(row['name'].strip(), row['id']); CARD.setdefault(row['id'], row)

def nm(k):
    k = (k or '').strip()
    n = ALIAS.get(k, k)
    m = re.match(r'^불량배-?([A-Za-z])$', n)
    return f'불량배-{m.group(1).upper()}' if m else n

def cid(name):
    n = nm(name)
    if n not in IDS:
        raise SystemExit(f'MISSING CARD: {name!r} -> {n!r}')
    return IDS[n]

RATE = {'NORMAL': 0.01, 'RARE': 0.02, 'HIGH RARE': 0.03, 'SUPER RARE': 0.04, 'ULTRA RARE': 0.05, 'MYTHIC RARE': 0.06}

def party_of(b):
    if b.get('story'): return {}
    forced = [cid(x) for x in b['forced']]
    p = {'forced': forced, 'mustLive': list(forced), 'levels': {i: b['flv'] for i in forced}, 'battleLevels': {i: 1 for i in forced}}
    bans = [x.replace(' ', '') for x in b.get('bans') or []]
    for tok in bans:
        if tok in ('여성',): p['noFemale'] = True
        elif tok in ('남성',): p['noMale'] = True
        elif tok in ('추가편성불가', '단독출전', '단독출현'): p['solo'] = True
        elif tok in ('S초과', 'SR초과'): p['maxGrade'] = 'SUPER RARE'
        elif tok in ('H초과', 'HR초과'): p['maxGrade'] = 'HIGH RARE'
        elif tok in ('UR초과',): p['maxGrade'] = 'ULTRA RARE'
    # 17-14: 이영하는 죽어도 되고, 이지영이 난입 후 필수 생존
    if b.get('note') == '이지영난입':
        p['mustLive'] = [cid('이지영')]
    return p

def boost_of(ids, elv):
    b = {}
    for k in ids:
        c = CARD[k]; l = elv; m = 1 + round(RATE[c['grade']] * (l - 1) * 100) / 100
        row = {'HP': round(int(c['HP']) * m), 'ATK': round(int(c['ATK']) * m), 'DEF': round(int(c['DEF']) * m), 'storyLv': l}
        row['power'] = card_power(c, **row)
        b[k] = row
    return b

def parse_lines(path):
    R = list(csv.reader(open(path, encoding='utf8')))
    start, phases, cur, after = [], [], None, False
    rows = R[1:]
    for i, r in enumerate(rows):
        r = r + [''] * 8
        no = int(r[0]) if re.fullmatch(r'\d+', r[0].strip() or '') else None
        if no:
            cur = {'no': no, 'title': r[1].strip(), 'lines': [], 'after': []}
            phases.append(cur); after = False
            # 페이즈 제목 행의 대사가 있으면 전/후에 따라 넣음. '후'만 있어도 오프닝은 전투 전에 보여 줌.
            if r[3].strip() and r[5].strip():
                L = line_of(r)
                if r[6].strip() == '후':
                    cur['after'].append(L)
                else:
                    cur['lines'].append(L)
            continue
        if not r[3].strip() or not r[5].strip():
            continue
        if r[6].strip() == '후' and cur:
            after = True
        if cur is None:
            start.append(line_of(r)); continue
        (cur['after'] if after else cur['lines']).append(line_of(r))
    return start, phases

def line_of(r):
    sp = nm(r[3]); L = {'speaker': sp, 'text': r[5].strip()}
    e = r[4].strip()
    if e and sp not in ('내레이션', '???'): L['expr'] = e
    return L

def decorate_lines(chn, no, lines):
    out = []
    for L in lines:
        L = dict(L)
        if chn == 16 and L.get('speaker') == '조윤이':
            L['slug'] = 'jo_yuni_school'
        if chn == 17 and L.get('speaker') == '최윤희':
            L['slug'] = 'choi_yunhee_school'
        out.append(L)
    return out

def build(chn, path, hero_name):
    start, dlg = parse_lines(path)
    by_no = {p['no']: p for p in dlg}
    phases = []
    for no, b in BATTLE[chn].items():
        d = by_no.get(no) or {'title': '', 'lines': [], 'after': []}
        lines = decorate_lines(chn, no, d['lines'])
        after = decorate_lines(chn, no, d['after'])
        if b.get('story'):
            cur = {'no': no, 'type': 'normal', 'scene': True, 'title': d['title'] or f'Phase {no}', 'lines': {'default': lines}, 'hero': [cid(hero_name)]}
            if after:
                cur['after'] = after; cur['afterTitle'] = '그 후'
            phases.append(cur)
            continue
        enames = list(b['enemies'])
        if b.get('boss'):
            enames = [b['boss']] + enames
        ids = [cid(x) for x in enames]
        party = party_of(b)
        rules = {}
        if '20턴 초과' in (b.get('lose') or ''):
            rules['maxTurns'] = 20
        cur = {
            'no': no, 'type': 'normal', 'enemyName': CARD[ids[0]]['name'], 'title': d['title'],
            'enemies': {'ids': ids, 'boost': boost_of(ids, b['elv'])},
            'lines': {'default': lines}, 'party': party, 'hero': [cid(hero_name)],
            'bossId': cid(b['boss']) if b.get('boss') else ids[0],
        }
        if b.get('blv'):
            cur['enemies']['levels'] = {i: b['blv'] for i in ids}
        if b.get('first') == '적군':
            cur['enemyFirst'] = True
        if b.get('mana') is not None:
            cur['mana'] = b['mana']
        if after:
            cur['after'] = after; cur['afterTitle'] = '전투 후'
        if b.get('note') == '각성윤진아':
            # type은 normal 유지 (보스 타입은 불사+진영 HP). 최국선을 쓰러뜨리면 승리.
            rules['mustKill'] = [cid('최국선')]
            rules.setdefault('revive', []).append({
                'id': cid('윤진아'), 'become': cid('[각성] 윤진아'), 'delay': 0,
                'storyLevel': 100, 'battleLevel': 10,
            })
        if b.get('note') == '이지영난입':
            cur['awaken'] = {'on': cid('이영하'), 'id': cid('이지영'), 'storyLevel': 50, 'battleLevel': 1}
        if rules:
            cur['rules'] = rules
        phases.append(cur)
    phases[-1]['final'] = True
    hero = cid(hero_name)
    ch = {
        'id': chn, 'title': f'CHAPTER {chn}', 'subtitle': SUB[chn], 'rewardCard': None,
        'hero': hero, 'single': True, 'phases': phases, 'tagline': '',
        'warning': '이 챕터에는 괴롭힘·폭력·죽음 묘사가 포함되어 있습니다.',
        'start': decorate_lines(chn, 0, start), 'ending': [], 'endingVideo': VIDEO[chn],
    }
    hdr = (f'// ===== 스토리 챕터 {chn} 「{SUB[chn]}」 (시트 CH{chn} + 전투정리2 → python3 tools/ch16_17_import.py 로 생성. 직접 고쳐도 됨) =====\n'
           f'// 단일 루트(single) · 페이즈 {len(phases)}개. 초상화 = chapterPortraits[{chn}]. 적 레벨은 전투정리2 적LV → enemies.boost\n')
    open(f'js/story-data-ch{chn}.js', 'w', encoding='utf8').write(hdr + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
    print(f'CH{chn}', len(phases), 'start', len(start), 'endingVideo', VIDEO[chn])
    for p in phases:
        if p.get('scene'):
            print(' ', p['no'], 'STORY', p['title'], 'lines', len(p['lines']['default']), 'after', len(p.get('after') or []))
        else:
            print(' ', p['no'], p['title'], [CARD[i]['name'] for i in p['enemies']['ids']],
                  {k: v['storyLv'] for k, v in p['enemies']['boost'].items()}, json.dumps(p['party'], ensure_ascii=False))

if __name__ == '__main__':
    build(16, sys.argv[1], '최국선')
    build(17, sys.argv[2], '이영하')
