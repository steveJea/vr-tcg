#!/usr/bin/env python3
"""parse_lines 전/후 상속: 제목행에만 후가 있어도 이후 빈 칸은 after 로 간다."""
import csv
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ch16_17_import import parse_lines

rows = [
    ['페이즈', '제목', 'x', '화자', '표정', '대사', '시점'],
    ['6', '빈소', '', '내레이션', '', '제목과 함께 있는 후 대사', '후'],
    ['', '', '', '내레이션', '', '표시 없는 둘째 줄', ''],
    ['', '', '', '최국선', '슬픔', '표시 없는 셋째 줄', ''],
    ['7', '다음', '', '내레이션', '', '전 대사', '전'],
    ['', '', '', '최국선', '보통', '전으로 상속된 줄', ''],
    ['', '', '', '내레이션', '', '후로 바뀐 줄', '후'],
    ['', '', '', '최국선', '보통', '후 상속 줄', ''],
]
fd, path = tempfile.mkstemp(suffix='.csv')
import os
os.close(fd)
with open(path, 'w', encoding='utf8', newline='') as f:
    csv.writer(f).writerows(rows)
try:
    start, phases = parse_lines(path)
    by = {p['no']: p for p in phases}
    p6, p7 = by[6], by[7]
    assert p6['lines'] == [], p6['lines']
    assert [L['text'] for L in p6['after']] == ['제목과 함께 있는 후 대사', '표시 없는 둘째 줄', '표시 없는 셋째 줄']
    assert [L['text'] for L in p7['lines']] == ['전 대사', '전으로 상속된 줄']
    assert [L['text'] for L in p7['after']] == ['후로 바뀐 줄', '후 상속 줄']
    print('ALL OK')
finally:
    os.remove(path)
