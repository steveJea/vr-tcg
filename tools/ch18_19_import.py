#!/usr/bin/env python3
"""CH18 「BITTERSWEET」 · CH19 「한니발라이징」
대사: 스토리 시트 CH18 · CH19 (열: phase, 제목, 대상, 표정, 대화내용, 진행시점, 멀티미디어) / 전투: 전투정리2
사용: python3 tools/ch18_19_import.py /tmp/s64/x_CH18.csv /tmp/s64/x_CH19.csv
엔딩 영상: CH18 aqNDjoJVPk4 · CH19 YqHloiQZ-QM (시트 멀티미디어 칸)
형님 답변 (디버그 64번, 11/17):
- 18-15 · 19-13 은 16-11 처럼 진영 HP 보스전 (type=boss, 보스 카드는 진영 칸 불사).
- 19-13 [상념] 민홍기(10534): 쓰러지면 2턴 후 부활 (모든 사본, 횟수 제한 없음). 진영 칸 보스 사본은 불사라 쓰러지지 않음.
- 필수 출전 카드는 'UR 이상' 금지에서 예외 (story.js partyOf · 서버 security_phase2 모두 필수 카드는 조건 검사 제외).
- CH19 콘텐츠 주의 (19-8: 어머니가 남편과 딸을 따라 떠남).
- 민홍기 부모 = 아버지 민왕표 · 어머니 이미연 (시트 대사도 이미 새 이름).
- 18-5 승리 = 6턴 생존 (패배 조건에 '필수캐 사망' 없음 → mustLive 비움, 20턴 제한 없음).
"""
import csv, json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__)); from power import card_power

SUB = {18: 'BITTERSWEET', 19: '한니발라이징'}
VIDEO = {18: 'aqNDjoJVPk4', 19: 'YqHloiQZ-QM'}
WARN = {
    18: '이 챕터에는 괴롭힘·폭력·죽음 묘사가 포함되어 있어요.',
    19: '이 챕터에는 괴롭힘·폭력·죽음 묘사와 가족의 자살을 암시하는 내용이 포함되어 있어요.',
}
ALIAS = {'NA': '내레이션', '나레이션': '내레이션', '내래이션': '내레이션'}
for L in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ':
    ALIAS[f'불량배{L}'] = f'불량배-{L}'
    ALIAS[L] = f'불량배-{L}'

LOSE_STD = '필수캐 미소환(2턴), 필수캐 사망, 아군 전멸, 20턴 초과'
LOSE_19 = '민홍기 사망, 필수캐 미소환(2턴), 아군 전멸, 20턴 초과'
B18 = dict(flv=50, elv=50, first='아군', win='적 전멸', lose=LOSE_STD, pts=3, mana=150)
B19 = dict(flv=50, elv=60, blv=1, first='아군', win='적 전멸', lose=LOSE_19, pts=3, mana=100)
UR = 'UR 이상'
# 전투정리2 18·19행 그대로 (초기 지급마나 = 18-1 60 · 그 외 150 / 19 100 · 19-13 60)
BATTLE = {
18: {
  1:  dict(B18, forced=['임예리','장초롱','민지은'], enemies=['I','H','H','H','H'], bans=['추가편성 불가'], mana=60),
  2:  dict(story=True, pts=3),
  3:  dict(B18, forced=['어린 임예리'], enemies=['D','D','D','D','D'], bans=['임예리','장초롱','민지은',UR]),
  4:  dict(B18, forced=['어린 임예리','어린 장초롱'], enemies=['I','H','H','H','H'], bans=['임예리','장초롱','민지은',UR]),
  5:  dict(B18, forced=['어린 임예리','어린 장초롱','어린 민지은'], enemies=['임재만','구정휘'], bans=['남성',UR], win='6턴 간 생존', lose='필수캐 미소환(2턴), 아군 전멸'),
  6:  dict(B18, forced=['임예리','장초롱','민지은'], enemies=['J','P','P','P','P'], bans=['추가편성 불가']),
  7:  dict(B18, forced=['민지은','장초롱'], enemies=['신아은','신예은','P','P','P'], bans=[UR]),
  8:  dict(B18, forced=['장초롱'], enemies=['E','E','E','E','E'], bans=[UR,'민지은']),
  9:  dict(B18, forced=['임예리'], enemies=['V','D','D','D','D'], bans=['추가편성 불가']),
 10:  dict(story=True, pts=3),
 11:  dict(story=True, pts=3),
 12:  dict(B18, forced=['임예리'], enemies=['신아은','신예은'], bans=['추가편성 불가']),
 13:  dict(B18, forced=['김성진'], flv=70, enemies=['J','J','J','J','J'], bans=['추가편성 불가']),
 14:  dict(story=True, pts=3),
 15:  dict(B18, forced=['김성진'], flv=70, boss='임예리', enemies=['장초롱','민지은'], bans=['추가편성 불가'], win='boss 격퇴'),
 16:  dict(B18, forced=['임유리'], enemies=['J','I','K','L','M'], bans=['추가편성 불가']),
},
19: {
  1:  dict(B19, forced=['민홍기'], enemies=['F','G','H','I','J'], bans=[UR]),
  2:  dict(story=True, pts=3),
  3:  dict(B19, forced=['민홍기'], enemies=['F','G','H','I','J'], bans=[UR]),
  4:  dict(story=True, pts=3),
  5:  dict(B19, forced=['민홍기'], enemies=['F','G','H','I','J'], bans=[UR]),
  6:  dict(story=True, pts=3),
  7:  dict(B19, forced=['민홍기'], enemies=['J','J','J','J','J'], bans=['여성',UR]),
  8:  dict(B19, forced=['민홍기'], enemies=['[상념] 민홍기'], bans=['민유연']),
  9:  dict(B19, forced=['민홍기'], enemies=['경호원D','경호원A','경호원A','경호원A','경호원A'], bans=['여성']),
 10:  dict(B19, forced=['민홍기'], enemies=['경호원D','경호원B','경호원B','경호원B','경호원B'], bans=['여성']),
 11:  dict(B19, forced=['민홍기'], enemies=['경호원D','경호원C','경호원C','경호원C','경호원C'], bans=['여성']),
 12:  dict(B19, forced=['민홍기'], enemies=['경호원E','강태안','강태준','이민수','김철민'], bans=['여성']),
 13:  dict(B19, forced=['김신현'], flv=70, boss='[상념] 민홍기', enemies=['[상념] 민홍기','[상념] 민홍기','[상념] 민홍기'], bans=['추가편성 불가'],
          win='보스 격퇴', lose='김신현 사망, 20턴 초과', note='상념부활', mana=60),
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
    ex = []
    for tok in [x.replace(' ', '') for x in b.get('bans') or []]:
        if tok == '여성': p['noFemale'] = True
        elif tok == '남성': p['noMale'] = True
        elif tok in ('추가편성불가', '단독출전'): p['solo'] = True
        elif tok in ('UR이상', 'SR초과'): p['maxGrade'] = 'SUPER RARE'   # 필수 카드는 예외 (partyOf · 서버 동일)
        elif tok in ('SR이상', 'HR초과'): p['maxGrade'] = 'HIGH RARE'
        else: ex.append(cid(tok))   # 이름 = 그 인물 출전 금지
    if ex: p['exclude'] = ex
    if '사망' not in (b.get('lose') or ''): p['mustLive'] = []   # 18-5: 생존전, 필수 카드가 쓰러져도 패배 아님
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
    for r in R[1:]:
        r = r + [''] * 8
        no = int(r[0]) if re.fullmatch(r'\d+', r[0].strip() or '') else None
        if no:
            cur = {'no': no, 'title': r[1].strip(), 'lines': [], 'after': []}
            phases.append(cur); after = False
        when = r[5].strip()
        if when == '후': after = True
        elif when == '전': after = False
        if not r[2].strip() or not r[4].strip():
            continue
        L = line_of(r)
        if cur is None: start.append(L)
        else: (cur['after'] if after else cur['lines']).append(L)
    return start, phases

def line_of(r):
    sp = nm(r[2]); L = {'speaker': sp, 'text': r[4].strip()}
    e = r[3].strip()
    if e and sp not in ('내레이션', '???'): L['expr'] = e
    return L

def build(chn, path, hero_name):
    start, dlg = parse_lines(path)
    by_no = {p['no']: p for p in dlg}
    assert sorted(by_no) == sorted(BATTLE[chn]), (chn, sorted(by_no))
    phases = []
    for no, b in BATTLE[chn].items():
        d = by_no[no]
        lines, after = d['lines'], d['after']
        if b.get('story'):
            cur = {'no': no, 'type': 'normal', 'scene': True, 'title': d['title'] or f'Phase {no}', 'lines': {'default': lines}, 'hero': [cid(hero_name)]}
            if after: cur['after'] = after; cur['afterTitle'] = '그 후'
            phases.append(cur); continue
        enames = ([b['boss']] if b.get('boss') else []) + list(b['enemies'])
        ids = [cid(x) for x in enames]
        rules = {}
        if '20턴 초과' in (b.get('lose') or ''): rules['maxTurns'] = 20
        m = re.match(r'(\d+)턴 간 생존', b.get('win') or '')
        if m: rules['survive'] = int(m.group(1))
        cur = {
            'no': no, 'type': 'boss' if b.get('boss') else 'normal', 'enemyName': CARD[ids[0]]['name'], 'title': d['title'],
            'enemies': {'ids': ids, 'boost': boost_of(ids, b['elv'])},
            'lines': {'default': lines}, 'party': party_of(b), 'hero': [cid(hero_name)],
            'bossId': ids[0],
        }
        if b.get('blv'): cur['enemies']['levels'] = {i: b['blv'] for i in ids}
        if b.get('first') == '적군': cur['enemyFirst'] = True
        if b.get('mana') is not None: cur['mana'] = b['mana']
        if after: cur['after'] = after; cur['afterTitle'] = '전투 후'
        if b.get('note') == '상념부활':
            rules['revive'] = [{'id': cid('[상념] 민홍기'), 'delay': 2}]
        if rules: cur['rules'] = rules
        phases.append(cur)
    phases[-1]['final'] = True
    ch = {
        'id': chn, 'title': f'CHAPTER {chn}', 'subtitle': SUB[chn], 'rewardCard': None,
        'hero': cid(hero_name), 'single': True, 'phases': phases, 'tagline': '',
        'warning': WARN[chn], 'start': start, 'ending': [], 'endingVideo': VIDEO[chn],
    }
    hdr = (f'// ===== 스토리 챕터 {chn} 「{SUB[chn]}」 (시트 CH{chn} + 전투정리2 → python3 tools/ch18_19_import.py 로 생성. 직접 고쳐도 됨) =====\n'
           f'// 단일 루트(single) · 페이즈 {len(phases)}개. 초상화 = STORY_DATA.portraits · chapterPortraits[{chn}]. 적 레벨은 전투정리2 적LV → enemies.boost\n')
    open(f'js/story-data-ch{chn}.js', 'w', encoding='utf8').write(hdr + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
    print(f'CH{chn}', len(phases), 'start', len(start), 'endingVideo', VIDEO[chn])
    for p in phases:
        if p.get('scene'):
            print(' ', p['no'], 'STORY', p['title'], 'lines', len(p['lines']['default']), 'after', len(p.get('after') or []))
        else:
            print(' ', p['no'], p['type'], p['title'], [CARD[i]['name'] for i in p['enemies']['ids']], p.get('mana'), json.dumps(p['party'], ensure_ascii=False), json.dumps(p.get('rules'), ensure_ascii=False))

if __name__ == '__main__':
    build(18, sys.argv[1], '임예리')
    build(19, sys.argv[2], '민홍기')
