#!/usr/bin/env python3
"""챕터 2 대본(md) → js/story-data-ch2.js
사용법: python3 tools/ch2_import.py <대본 폴더>   (ch2_myeongjin.md, ch2_kimhu.md, ch2_common.md)
대본 형식: '## Phase.N 「제목」' + '적: 이름, 이름(본진), ... (5)' + '[화자: 대사]' 줄. '## 막간 「제목」 (Phase.N 승리 후)', '## 루트 엔딩 (Phase.N 승리 후)', '## 챕터 엔딩 (승리 후)', '## 시작 스토리', '## 캐릭터 소개'
표정: '[화자(화남): 대사]' / '[화자(웃음): 대사]' 처럼 쓰면 그대로 들어감 (초상화가 있는 인물만 표정이 바뀜). 아래 EXPR 표는 대본에 표정이 없을 때 넣은 것.
"""
import csv, json, os, re, sys
ROOT = os.path.join(os.path.dirname(__file__), '..')
rows = list(csv.DictReader(open(os.path.join(ROOT, 'data/cards.csv'), encoding='utf-8-sig')))
ID = {r['name']: r['id'] for r in rows}
MJ, KH, YA, OR = ID['이명진'], ID['김후'], ID['이영아'], ID['박오류']
# 대본에 표정이 없어서 톤이 분명한 줄만 넣은 표정 (초상화 있는 인물만): (파일, 대사 앞부분) → 표정
EXPR = {('ch2_kimhu.md', '요즘 애들이 너 골목대장이래'): '웃음', ('ch2_kimhu.md', '아 왜… 잘 모른다니까'): '화남'}
LINE = re.compile(r'^\[([^:\]]+?)\s*(?:\((기본|화남|웃음)\))?:\s*(.*)\]$')

def parse(path):
    fn = os.path.basename(path); secs = []; cur = None
    for raw in open(path, encoding='utf-8'):
        s = raw.strip()
        if s.startswith('## '): cur = {'head': s[3:].strip(), 'lines': [], 'text': [], 'enemies': None}; secs.append(cur); continue
        if cur is None or not s: continue
        m = LINE.match(s)
        if m:
            L = {'speaker': m.group(1).strip(), 'text': m.group(3).strip()}
            ex = m.group(2) or next((v for (f, k), v in EXPR.items() if f == fn and L['text'].startswith(k)), None)
            if ex: L['expr'] = ex
            cur['lines'].append(L); continue
        if s.startswith('적:'):
            names = [n.strip() for n in re.sub(r'\(\d+\)\s*$', '', s[2:]).split(',') if n.strip()]
            cur['enemies'] = names; continue
        cur['text'].append(s)
    return secs

def title_of(h): m = re.search(r'「(.+?)」', h); return m.group(1) if m else ''
def phase_from(sec):
    no = int(re.match(r'Phase\.(\d+)', sec['head']).group(1))
    boss_name = next((n.replace('(본진)', '').strip() for n in sec['enemies'] if '(본진)' in n), None)
    names = [n.replace('(본진)', '').strip() for n in sec['enemies']]
    missing = [n for n in names if n not in ID]
    if missing: raise SystemExit(f'카드 없음: {missing}')
    p = {'title': title_of(sec['head']), 'enemies': {'ids': [ID[n] for n in names]}, 'lines': sec['lines']}
    if boss_name: p['enemyName'] = boss_name; p['bossId'] = ID[boss_name]
    return no, p

def route(path, hero, name):
    secs = parse(path); out = {'name': name, 'hero': hero, 'phases': {}}
    for s in secs:
        h = s['head']
        if h.startswith('캐릭터 소개'): out['tagline'] = '\n'.join(s['text'])
        elif h.startswith('시작 스토리'): out['start'] = s['lines']
        elif h.startswith('Phase.'): no, p = phase_from(s); out['phases'][no] = p
        elif h.startswith('막간') or h.startswith('루트 엔딩'):
            no = int(re.search(r'Phase\.(\d+)', h).group(1))
            out['phases'][no]['after'] = s['lines']
            out['phases'][no]['afterTitle'] = ('막간 「' + title_of(h) + '」') if h.startswith('막간') else '루트 엔딩'
    return out, secs

def main(src):
    mj, _ = route(os.path.join(src, 'ch2_myeongjin.md'), MJ, '이명진')
    kh, _ = route(os.path.join(src, 'ch2_kimhu.md'), KH, '김후')
    common = parse(os.path.join(src, 'ch2_common.md'))
    title = title_of(open(os.path.join(src, 'ch2_common.md'), encoding='utf-8').readline())
    # 이명진 루트 Phase 4~7: 이명진 없음(수감), 영아·오류가 주인공 → 영아·오류 필수, 이명진 출전 불가. 대사 왼쪽 자리는 영아·오류
    for n in (4, 5, 6, 7): mj['phases'][n].update({'hero': [OR, YA], 'party': {'forced': [YA, OR], 'exclude': [MJ]}})
    base = []; ending = []
    cp = {}
    for s in common:
        if s['head'].startswith('Phase.'): no, p = phase_from(s); cp[no] = p
        elif s['head'].startswith('챕터 엔딩'): ending = s['lines']
    for n in range(1, 11):
        p = {'no': n, 'type': 'boss' if n == 10 else 'normal', 'enemyName': '적군', 'title': '', 'enemies': {'count': 5, 'rank': [60, 203]}, 'lines': {'default': []}}
        if n in cp:
            c = dict(cp[n]); lines = c.pop('lines'); p.update(c); p['lines'] = {'default': lines}
            # 공통 페이즈: 두 사람이 함께 싸움 (대본상 명진·김후 모두 등장) → 둘 다 필수, 대사 왼쪽 자리도 둘
            p['party'] = {'forced': [MJ, KH]}; p['hero'] = [MJ, KH]
        if n == 10: p['tip'] = '보스전! 👑 정치욱은 진영 안에서 쓰러지지 않아요. 상대 진영 HP를 0으로 만드세요.'
        base.append(p)
    # 일반 페이즈 상대 이름: 세력 이름
    GROUP = {}
    for g, names in [('일진 무리', '염상휘 윤동훈 구성원 고한홍 염태영 전성국 유형수 주연욱 전호영'), ('정치욱 패거리', '김민규 최훈남 허요한 마형은 정재헌 최훈필 신성진 김홍민 김들 한하루'),
                     ('가리봉 불량배', '최민우 천재황 곽명구 한석열 남궁무열 인창민 안현 장동만 복규철 김희건'), ('정치욱 일가', '정치성 정치환 남궁형남 성재수 선영운 배승규 강철하 추정욱 안재수')]:
        for n in names.split(): GROUP[ID[n]] = g
    for ph in [*mj['phases'].values(), *kh['phases'].values(), *base]:
        if 'bossId' not in ph and ph.get('enemies', {}).get('ids'):
            gs = [GROUP.get(i, '적군') for i in ph['enemies']['ids']]; ph['enemyName'] = max(set(gs), key=gs.count)
    for r in (mj, kh): r['subtitle'] = title
    ch2 = {'id': 2, 'title': 'CHAPTER 2', 'subtitle': title, 'rewardCard': None,
           'routeTitle': '챕터 2: 누구의 이야기를 따라갈까요?',
           'routeNote': '고른 루트의 주인공은 출전 카드에 자동으로 들어가요 (없으면 게스트). 페이즈를 하나라도 깨면 루트를 바꿀 수 없어요.',
           'routeOrder': [MJ, KH], 'ending': ending, 'phases': base, 'byRoute': {MJ: mj, KH: kh}}
    head = """// ===== 스토리 챕터 2 「검은 밴」 (대본: vroyale/story/ch2_*.md → python3 tools/ch2_import.py <폴더> 로 생성. 직접 고쳐도 됨) =====
// 루트(byRoute[카드 id]): 챕터 2 처음 들어갈 때 이명진 / 김후 중 고름. hero = 루트 주인공(출전 카드 필수, 없으면 게스트) · 대사에서 왼쪽 자리
// 페이즈 party: { forced: [필수 카드 id], exclude: [출전 불가 카드 id] } 가 있으면 루트 기본(주인공 필수) 대신 사용. 페이즈 hero: 대사 왼쪽 자리(여러 명 가능)
// 페이즈 after: 그 페이즈를 처음 이겼을 때 나오는 대사 (막간·루트 엔딩). 챕터 ending: 보스(Phase.10) 첫 클리어 후
// 대사 한 줄: { "speaker": "이름" | "내레이션", "text": "...", "expr": "화남" | "웃음" (선택, 초상화 있는 인물만 표정 변화) }
"""
    js = head + 'window.STORY_DATA.chapters.push(' + json.dumps(ch2, ensure_ascii=False, indent=1) + ');\n'
    js += "// 카드가 아닌 화자: 초상화 없이 이름만\nwindow.STORY_DATA.noPortrait = [...new Set([...(window.STORY_DATA.noPortrait || []), '밴에서 내린 남자'])];\n"
    open(os.path.join(ROOT, 'js/story-data-ch2.js'), 'w', encoding='utf-8').write(js)
    # 확인용 출력
    sp = {}
    for r in (mj, kh):
        for L in r.get('start', []): sp.setdefault(L['speaker'], 0); sp[L['speaker']] += 1
        for p in r['phases'].values():
            for L in p['lines'] + p.get('after', []): sp.setdefault(L['speaker'], 0); sp[L['speaker']] += 1
    for p in base:
        for L in p['lines']['default']: sp.setdefault(L['speaker'], 0); sp[L['speaker']] += 1
    for L in ending: sp.setdefault(L['speaker'], 0); sp[L['speaker']] += 1
    print(json.dumps({'speakers': {k: (ID.get(k, 'NO CARD'), v) for k, v in sp.items()}}, ensure_ascii=False))
    return mj, kh, base

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '/workspace/vroyale/story')
