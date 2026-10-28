#!/usr/bin/env python3
"""카드 ID 일괄 변경 (옛 10자리 → 새 5자리, tools/idmap/card_id_map.csv 기준)
사용: python3 tools/idmap/remap.py <repo 경로> [--apply]
  - 기본은 미리보기(바꿀 파일 이름·글자 수만 셈). --apply 면 git mv + 내용 치환
  - 파일 이름: <옛id>... → <새id>... (예: data/voice/2000100001_1.mp3 → 10325_1.mp3, img/bt_img/_2000100001.webp → _10325.webp)
  - 내용: 앞뒤가 숫자가 아닌 옛 ID 만 바꿈 (2000100001_1 도 바뀜, 더 긴 숫자 안의 일부는 안 바뀜)
  - 건너뜀: 이 폴더(tools/idmap), js/id-alias.js, supabase/card_id_remap.sql (옛 ID 를 일부러 담고 있음), .git, node_modules, 바이너리
  - vr-tcg 의 data/cards.csv · data/npc_cards.csv 에는 base_id 열(변형 카드 → 원래 캐릭터)을 붙임
"""
import csv, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
MAP = {r['old_id']: r for r in csv.DictReader(open(os.path.join(HERE, 'card_id_map.csv'), encoding='utf-8'))}
RX = re.compile(r'(?<![0-9])(' + '|'.join(sorted(MAP, key=len, reverse=True)) + r')(?![0-9])')
SKIP_DIRS = {'.git', 'node_modules', 'idmap'}
SKIP_FILES = {'js/id-alias.js', 'supabase/card_id_remap.sql'}
sub = lambda s: RX.sub(lambda m: MAP[m.group(1)]['new_id'], s)

def main(repo, apply):
    repo = os.path.abspath(repo)
    files = subprocess.run(['git', '-C', repo, 'ls-files'], capture_output=True, text=True, check=True).stdout.splitlines()
    renames, edits, refs = [], [], 0
    for f in files:
        if f in SKIP_FILES or SKIP_DIRS & set(f.split('/')[:-1]): continue
        d, b = os.path.split(f); nb = sub(b)
        if nb != b: renames.append((f, os.path.join(d, nb)))
        try: t = open(os.path.join(repo, f), encoding='utf-8').read()
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError): continue
        n = len(RX.findall(t))
        if n: edits.append((f, n)); refs += n
    print(f'{repo}: 이름 바꿀 파일 {len(renames)}개 · 내용 바꿀 파일 {len(edits)}개 · 참조 {refs}곳')
    by = {}
    for f, n in edits: k = f.split('/')[0] if '/' in f else '(root)'; by[k] = by.get(k, 0) + n
    for k, n in sorted(by.items(), key=lambda x: -x[1]): print(f'  {k}: {n}')
    if not apply: return
    for f, n in edits:
        p = os.path.join(repo, f); t = open(p, encoding='utf-8').read(); open(p, 'w', encoding='utf-8').write(sub(t))
    for a, b in renames: subprocess.run(['git', '-C', repo, 'mv', a, b], check=True)
    for f in ('data/cards.csv', 'data/npc_cards.csv'):   # 변형 카드 → 원래 캐릭터 (ID 붙어 있음에 기대지 않음)
        p = os.path.join(repo, f)
        if not os.path.exists(p): continue
        base = {r['new_id']: r['base_id'] for r in MAP.values()}
        rows = list(csv.reader(open(p, encoding='utf-8')))
        if 'base_id' in rows[0]: continue
        rows[0].append('base_id')
        for r in rows[1:]: r.append(base.get(r[0], ''))
        with open(p, 'w', newline='', encoding='utf-8') as fh: csv.writer(fh, lineterminator='\n').writerows(rows)
    print('적용 완료')

if __name__ == '__main__':
    if len(sys.argv) < 2: sys.exit(__doc__)
    main(sys.argv[1], '--apply' in sys.argv)
