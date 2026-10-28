#!/usr/bin/env python3
"""옛 카드 ID(10자리)가 저장소에 남았는지 검사. 남으면 exit 1.
사용: python3 tools/idmap/verify.py [저장소 경로]   (vr-tcg · vr-ideal-worldcup 둘 다)
대응표·별칭(js/id-alias.js)·이전 SQL 은 일부러 옛 ID 를 담으므로 뺌. 파일 이름도 검사."""
import csv, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OLD = {r['old_id'] for r in csv.DictReader(open(os.path.join(HERE, 'card_id_map.csv'), encoding='utf-8-sig'))}
RX = re.compile(r'(?<![0-9])([12][01]0[0-9]{7})(?![0-9])')
SKIP_DIRS = {'.git', 'node_modules', 'idmap'}
SKIP_FILES = {'js/id-alias.js', 'supabase/card_id_remap.sql'}
repo = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..'))
files = subprocess.run(['git', 'ls-files'], cwd=repo, capture_output=True, text=True).stdout.split('\n')
bad = 0
for f in filter(None, files):
    if f in SKIP_FILES or SKIP_DIRS & set(f.split('/')[:-1]): continue
    if any(m in OLD for m in RX.findall(os.path.basename(f))): print('파일 이름:', f); bad += 1
    try: txt = open(os.path.join(repo, f), encoding='utf-8').read()
    except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError): continue
    hits = [m for m in RX.findall(txt) if m in OLD]
    if hits: print(f'{f}: {len(hits)}개 (예: {hits[0]})'); bad += len(hits)
print('옛 ID 0개 — 통과' if not bad else f'옛 ID {bad}개 남음'); sys.exit(1 if bad else 0)
