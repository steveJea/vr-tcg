#!/usr/bin/env python3
"""구글 시트 '어비스게이트 스토리'(xlsx) → js/story-data-ch8~15.js 대사 동기화 (진행시점 전/후 반영).
사용법: python3 tools/sheet_story_sync_ch8plus.py <story.xlsx> [--dry] [--ch 8,9,14,15]
- 페이즈 구조·적·보상·이미지/영상/slug 는 그대로. 대사만 시트 기준: 챕터 시작(start) / 페이즈 전투 전(lines.default) / '후' 행부터 전투 후(after).
- 페이즈는 시트 번호가 아니라 순서로 맞춤 (시트 번호 건너뜀 대응).
- 같은 문장이 게임에 있으면 그 줄(화자 표기·표정·미디어)을 그대로 옮기고, 고친 문장은 비슷한 줄의 텍스트만 교체, 새 줄은 시트 화자/표정으로 추가.
- 시트에 없는 'Chapter N. fin' 줄은 유지. KEEP = 시트 쪽 오탈자(게임 텍스트 유지).
"""
import json, os, re, sys, difflib, subprocess
import openpyxl
ROOT = os.path.join(os.path.dirname(__file__), '..')
DRY = '--dry' in sys.argv
CHS = [8, 9, 10, 11, 12, 13, 14, 15]
if '--ch' in sys.argv: CHS = [int(x) for x in sys.argv[sys.argv.index('--ch') + 1].split(',')]
src = [a for a in sys.argv[1:] if a.endswith('.xlsx')][0]
wb = openpyxl.load_workbook(src, data_only=True)
s_ = lambda v: '' if v is None else (str(int(v)) if isinstance(v, float) and v.is_integer() else str(v).strip())
ALIAS = {'NA': '내레이션', '나레이션': '내레이션', '내래이션': '내레이션', '왼쪽날개': '왼쪽 날개', '오른쪽날개': '오른쪽 날개', '안혜찐': '안혜진', '한거린': '한서린'}
KEEP = {(9, 'P2의 얼굴'), (9, "좋아해서 그래.' '그냥")}   # 시트 쪽 오탈자/자리표시: 게임 텍스트 유지
norm = lambda x: re.sub(r'[\s.…·,!?~"\'“”‘’]', '', x)
FIN = re.compile(r'^Chapter \d+\. fin$')

def nm(k):
    n = ALIAS.get(k.strip(), k.strip()); m = re.match(r'^불량배-?([A-Za-z])$', n)
    return f'불량배-{m.group(1).upper()}' if m else n

def parse(tab):
    rows = [[s_(c) for c in r] + [''] * 20 for r in wb[tab].iter_rows(values_only=True)][1:]
    leg = {}
    for r in rows:
        for i in range(16, len(r) - 1):
            if r[i] and r[i + 1] and re.fullmatch(r'[A-Z]{1,3}\d?|NA', r[i]): leg[r[i]] = r[i + 1]
    out, k, after = {'start': []}, 0, False
    for i, r in enumerate(rows, 2):
        if re.fullmatch(r'\d+', r[0]): k += 1; out[(k, 'pre')] = []; out[(k, 'after')] = []; after = False
        if not r[3] or not r[5]: continue
        if r[6] == '후' and k: after = True
        out['start' if not k else (k, 'after' if after else 'pre')].append(dict(row=i, sp=nm(leg.get(r[3], r[3])), e=r[4], t=r[5], m=r[7]))
    return out

def load(c):
    p = os.path.join(ROOT, f'js/story-data-ch{c}.js'); txt = open(p, encoding='utf-8').read()
    a = txt.index('window.STORY_DATA.chapters.push(') + len('window.STORY_DATA.chapters.push(')
    b = txt.rindex(');')
    return p, txt[:a], json.loads(txt[a:b]), txt[b:]

for c in CHS:
    S = parse(f'CH{c}'); path, head, ch, tail = load(c)
    had_start = 'start' in ch
    blocks = {'start': ch.setdefault('start', [])}
    for i, p in enumerate(ch['phases'], 1):
        blocks[(i, 'pre')] = p['lines']['default']; blocks[(i, 'after')] = p.get('after') or []
    assert len(ch['phases']) == len([k for k in S if k != 'start']) // 2, f'CH{c} 페이즈 수 다름'
    pool = [(k, j, L) for k, B in blocks.items() for j, L in enumerate(B)]
    used = set(); new = {}; log = []
    for k in blocks:
        G = blocks[k]; out = []
        for s in S.get(k, []):
            hit = next((x for x in pool if id(x[2]) not in used and x[0] == k and x[2]['text'] == s['t']), None) or \
                  next((x for x in pool if id(x[2]) not in used and len(norm(s['t'])) >= 6 and x[2]['text'] == s['t']), None)
            if hit: used.add(id(hit[2])); out.append(hit[2]); continue
            cand = [(difflib.SequenceMatcher(None, norm(x[2]['text']), norm(s['t'])).ratio(), x) for x in pool if id(x[2]) not in used and x[0] == k]
            r, x = max(cand, key=lambda t: t[0], default=(0, None))
            if r >= 0.5:
                used.add(id(x[2])); L = dict(x[2])
                if not any(cc == c and frag in s['t'] for cc, frag in KEEP):
                    L['text'] = s['t']; log.append(f"[CH{c} {k} r{s['row']}] 수정 {x[2]['text']!r} → {s['t']!r}")
                out.append(L); continue
            L = {'speaker': s['sp'], 'text': s['t']}
            if s['e'] and s['sp'] != '내레이션': L['expr'] = s['e']
            log.append(f"[CH{c} {k} r{s['row']}] 추가 {s['sp']}: {s['t']!r}" + (f"  (멀티미디어 칸: {s['m']})" if s['m'] else ''))
            out.append(L)
        new[k] = out
    for k, j, L in pool:
        if id(L) in used: continue
        if FIN.match(L['text']): new[k].append(L); used.add(id(L)); continue
    # 위치만 옮겨진 줄 / 삭제된 줄 표시
    for k, B in blocks.items():
        for L in B:
            nk = next((kk for kk, o in new.items() if any(x is L or x.get('text') == L['text'] for x in o)), None)
            if nk is None: log.append(f"[CH{c} {k}] 삭제 {L['speaker']}: {L['text']!r}")
            elif nk != k: log.append(f"[CH{c}] 이동 {k} → {nk}: {L['text'][:40]!r}")
    ch['start'] = new['start']
    if not ch['start'] and not had_start: ch.pop('start')
    for i, p in enumerate(ch['phases'], 1):
        p['lines']['default'] = new[(i, 'pre')]
        if new[(i, 'after')]: p['after'] = new[(i, 'after')]; p.setdefault('afterTitle', '전투 후')
        else: p.pop('after', None); p.pop('afterTitle', None)
    print('\n'.join(log) or f'CH{c} 변경 없음')
    if not DRY: open(path, 'w', encoding='utf-8').write(head + json.dumps(ch, ensure_ascii=False, indent=1) + tail)
