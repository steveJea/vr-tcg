#!/usr/bin/env python3
"""구글 시트 '어비스게이트 스토리'(xlsx 내보내기) → js/story-data-ch2~7.js 대사 동기화.
사용법: python3 tools/sheet_story_sync.py <story.xlsx> [--dry]
- 기존 페이즈 구조(출전 규칙·보상 등)는 그대로 두고 대사만 맞춤: 같은 줄 유지, 고친 줄 텍스트 교체, 새 줄은 앞 줄 뒤에 삽입, 시트에 없는 줄 삭제.
- CH4·CH5 는 화자도 시트 기준(불량배 교체)으로 덮어쓰고, 적 구성(enemies.ids · 리더 · CH5 레벨 storyLevels)도 시트 '적' 칸에서 다시 만듦.
- 화자 표기 정규화: 불량배K → 불량배-K, 나레이션/NA → 내레이션, 수상한남자 → 수상한 남자. 'X(화남)' 의 괄호는 표정(expr)으로 분리.
- CH1 은 js/story-data.js(손으로 쓴 JS) 라 이 도구 대상 아님. CH0 은 삭제 없이 유지(황보예·송지아 대사).
"""
import csv, json, os, re, sys, difflib
import openpyxl
ROOT = os.path.join(os.path.dirname(__file__), '..')
DRY = '--dry' in sys.argv
src = [a for a in sys.argv[1:] if not a.startswith('--')][0]
cards = {r['name']: r['id'] for f in ('data/cards.csv', 'data/npc_cards.csv') for r in csv.DictReader(open(os.path.join(ROOT, f), encoding='utf-8-sig'))}
TABS = {2: ['CH2-1', 'CH2-2'], 3: ['CH3'], 4: ['CH4'], 5: ['CH5'], 6: ['CH6'], 7: ['CH7']}
REBUILD = {4, 5}
s_ = lambda v: '' if v is None else (str(int(v)) if isinstance(v, float) and v.is_integer() else str(v).strip())

def sheet(ws):
    rows = [[s_(c) for c in r] for r in ws.iter_rows(values_only=True)]
    leg = {}
    for r in rows[1:]:
        for i in range(16, len(r) - 1):
            if r[i] and r[i + 1] and re.fullmatch(r'[A-Z]{1,3}\d?|NA', r[i]): leg[r[i]] = r[i + 1]
    lines, enemies, phase = [], {}, ''
    for i, r in enumerate(rows[1:], 2):
        r = r + [''] * 16
        if r[0]: phase = r[0]
        en = [x for x in r[8:13] if x]
        if en and not all(re.fullmatch(r'\d+', x) for x in en): enemies[phase] = {'names': r[8:13], 'lv': None}
        elif en and phase in enemies: enemies[phase]['lv'] = r[8:13]
        if r[5]: lines.append(dict(row=i, phase=phase, sp=r[3], e=r[4], t=r[5], tm=r[6]))
    return leg, lines, enemies

def speaker(raw, leg):
    m = re.match(r'^(.*?)\s*\((화남|웃음)\)$', raw)
    name, ex = (m.group(1), m.group(2)) if m else (raw, None)
    name = leg.get(name, name)
    if name in ('나레이션', 'NA'): name = '내레이션'
    name = re.sub(r'^불량배-?([A-Z])$', r'불량배-\1', name)
    name = {'수상한남자': '수상한 남자', 'H': '불량배-H', 'J': '불량배-J', 'I': '불량배-I'}.get(name, name)
    return name, ex

# 시트 쪽이 오탈자(기존 게임 쪽이 교정본)인 줄: 게임 텍스트 유지 (CH, 시트 행)
KEEP = {(2, 13), (2, 9), (3, 121), (5, 37), (5, 73), (5, 92), (6, 28), (6, 62), (6, 67), (6, 69), (6, 75), (6, 89), (7, 29), (7, 31), (7, 54), (7, 169), (7, 170), (7, 172), (7, 184)}
norm = lambda x: re.sub(r'[\s.…·,!?~"\'“”‘’]', '', x)

def containers(o, acc):
    if isinstance(o, list):
        if o and all(isinstance(x, dict) and 'text' in x for x in o): acc.append(o); return
        for x in o: containers(x, acc)
    elif isinstance(o, dict):
        for k in o: containers(o[k], acc)

def sync(cid, ch, tabs, wb, log):
    leg, S, EN = {}, [], {}
    for t in tabs:
        l, s, e = sheet(wb[t]); leg.update(l); S += s; EN.update(e)
    conts = []; containers(ch, conts)
    G = [(c, L) for c in conts for L in c]
    sn = {norm(l['t']) for l in S}; gn = {norm(L['text']) for _, L in G}
    short = lambda t: len(norm(t)) < 3   # '.....' '!!!?' 같은 말줄임 줄은 손대지 않음
    ug = [L for _, L in G if norm(L['text']) not in sn and not short(L['text'])]
    us = [l for l in S if norm(l['t']) not in gn and not short(l['t'])]
    pairs = sorted(((difflib.SequenceMatcher(None, norm(L['text']), norm(l['t'])).ratio(), i, j) for i, L in enumerate(ug) for j, l in enumerate(us)), reverse=True)
    gi, sj, match = set(), set(), {}
    for r, i, j in pairs:
        if r < 0.55: break
        if i in gi or j in sj: continue
        gi.add(i); sj.add(j); match[id(ug[i])] = us[j]
    # 같은 텍스트 게임 줄 전부(루트 중복) 고침
    for i in list(gi):
        L = ug[i]; l = match[id(L)]
        for _, L2 in G:
            if L2 is not L and L2['text'] == L['text'] and id(L2) not in match: match[id(L2)] = l
    stext = {}
    for l in S: stext.setdefault(norm(l['t']), []).append(l)
    used = {}
    for c, L in G:
        l = match.get(id(L))
        if not l and norm(L['text']) in stext:
            q = stext[norm(L['text'])]; k = used.get(norm(L['text']), 0); used[norm(L['text'])] = k + 1; l = q[min(k, len(q) - 1)]
        if not l: continue
        if l['t'] != L['text'] and not short(L['text']) and re.sub(r'\s', '', l['t']) != re.sub(r'\s', '', L['text']) and (cid, l['row']) not in KEEP: log.append(f'[CH{cid} r{l["row"]}] 수정 {L["text"]!r} → {l["t"]!r}'); L['text'] = l['t']
        if cid in REBUILD:
            sp, ex = speaker(l['sp'], leg)
            if sp and sp != L.get('speaker') and sp != '': log.append(f'[CH{cid} r{l["row"]}] 화자 {L.get("speaker")} → {sp}'); L['speaker'] = sp
            if ex and L.get('expr') != ex: L['expr'] = ex
    # 삽입
    news = [l for j, l in enumerate(us) if j not in sj]
    for l in news:
        k = S.index(l); sp, ex = speaker(l['sp'], leg)
        NL = {'speaker': sp, 'text': l['t']}
        if ex: NL['expr'] = ex
        done = False
        for p in range(k - 1, -1, -1):
            prev = norm(S[p]['t'])
            if short(S[p]['t']): continue
            hits = [(c, L) for c, L in G if norm(L['text']) == prev]
            if hits:
                for c, L in hits: c.insert(c.index(L) + 1, dict(NL))
                G = [(c, L) for c in conts for L in c]; done = True; break
        if not done:  # 앞 줄 없음 → 다음 줄 앞
            nxt = next(norm(x['t']) for x in S[k + 1:] if not short(x['t'])); c, L = next((c, L) for c, L in G if norm(L['text']) == nxt)
            c.insert(c.index(L), dict(NL)); G = [(c, L) for c in conts for L in c]
        log.append(f'[CH{cid} r{l["row"]} P{l["phase"]}] 신규 {sp}: {l["t"]}')
    # 삭제
    if cid != 0:
        for i, L in enumerate(ug):
            if i in gi: continue
            for c in conts:
                if L in c and any(x is L for x in c): c[:] = [x for x in c if x is not L]
            log.append(f'[CH{cid}] 삭제 {L.get("speaker")}: {L["text"]}')
    if cid in REBUILD:
        for p in ch['phases']:
            e = EN.get(str(p['no']))
            if not e or cid == 4 and p['no'] == 10: continue
            ids, lead, lv = [], None, {}
            for k, raw in enumerate(e['names']):
                if not raw: continue
                nm = re.sub(r'\s*\((?:리더|강화[^)]*)\)', '', raw).strip(); nm = re.sub(r'\s*\(리더\)', '', nm).strip()
                nm, _ = speaker(nm, leg)
                cid_ = cards.get(nm); assert cid_, (cid, p['no'], nm)
                ids.append(cid_)
                if '(리더)' in raw: lead = (nm, cid_)
                if e['lv'] and e['lv'][k] and cid_ not in p['enemies'].get('boost', {}): lv[cid_] = int(e['lv'][k])
            old = p['enemies']['ids']; p['enemies']['ids'] = ids
            if 'boost' in p['enemies']: p['enemies']['boost'] = {k: v for k, v in p['enemies']['boost'].items() if k in ids}
            if lv: p['enemies']['storyLevels'] = lv
            if lead: p['enemyName'], p['bossId'] = lead
            log.append(f'[CH{cid} P{p["no"]}] 적 {old} → {ids} 리더 {lead} 레벨 {lv}')

wb = openpyxl.load_workbook(src, data_only=True)
log = []
for cid, tabs in TABS.items():
    path = os.path.join(ROOT, f'js/story-data-ch{cid}.js'); txt = open(path, encoding='utf-8').read()
    m = re.search(r'window\.STORY_DATA\.chapters\.push\((\{.*?\n\})\);\n', txt, re.S)
    ch = json.loads(m.group(1))
    sync(cid, ch, tabs, wb, log)
    if not DRY: open(path, 'w', encoding='utf-8').write(txt[:m.start(1)] + json.dumps(ch, ensure_ascii=False, indent=1) + txt[m.end(1):])
print('\n'.join(log))
