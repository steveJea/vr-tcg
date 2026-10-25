#!/usr/bin/env python3
"""퀘스트 시트 → data/quest.json 변환
사용: python3 tools/quest_import.py [시트.csv]   (인자 없으면 공개 CSV 내보내기 주소에서 받음)
시트: 1zgFOStd6Go3hK4GkV8JsZzb8Glog2pKLdncwIy4NgQI  열: 스테이지, 적 리더 파워(max), 적 리더 등급, 적 조건 등급(리더와 동일 수준/리더보다 약함), 인연여부(o/x)
기존 quest.json 의 층별 수동 필드(enemies: 고정 적, boss, rewards, note)는 그대로 유지(덮어쓰지 않음)
"""
import csv, io, json, sys, urllib.request, os
SHEET = '1zgFOStd6Go3hK4GkV8JsZzb8Glog2pKLdncwIy4NgQI'
OUT = os.path.join(os.path.dirname(__file__), '..', 'data', 'quest.json')
GRADE = {'N': 'NORMAL', 'R': 'RARE', 'HR': 'HIGH RARE', 'SR': 'SUPER RARE', 'UR': 'ULTRA RARE', 'MR': 'MYTHIC RARE'}
REL = {'리더와 동일 수준': 'same', '리더보다 약함': 'weak'}
KEEP = ('enemies', 'boss', 'rewards', 'note', 'title')

def main():
    txt = open(sys.argv[1], encoding='utf-8').read() if len(sys.argv) > 1 else urllib.request.urlopen(f'https://docs.google.com/spreadsheets/d/{SHEET}/export?format=csv').read().decode('utf-8')
    old = {}
    if os.path.exists(OUT):
        for f in json.load(open(OUT, encoding='utf-8')).get('floors', []): old[f['floor']] = f
    floors, errs = [], []
    for row in csv.reader(io.StringIO(txt)):
        row = [c.strip() for c in row] + [''] * 6
        if not row[1].isdigit(): continue
        n, pw, g, rel, bond = int(row[1]), row[2].replace(',', ''), row[3].upper(), row[4], row[5].lower()
        if g not in GRADE: errs.append(f'{n}: 등급 {g!r}'); continue
        if rel not in REL: errs.append(f'{n}: 적 조건 {rel!r}'); continue
        f = {'floor': n, 'power': int(float(pw)), 'grade': GRADE[g], 'others': REL[rel], 'bond': bond == 'o'}
        for k in KEEP:
            if k in old.get(n, {}): f[k] = old[n][k]
        floors.append(f)
    floors.sort(key=lambda f: f['floor'])
    nums = [f['floor'] for f in floors]
    if nums != list(range(1, len(nums) + 1)): errs.append('층 번호가 1부터 연속이 아님')
    if errs: print('오류:', *errs, sep='\n  '); sys.exit(1)
    data = {
        '_doc': '퀘스트(시련의 탑). tools/quest_import.py 로 생성. power=적 리더 목표 전투력(레벨 포함), grade=적 리더 등급, others=same(리더의 90~100%)/weak(60~80%), bond=인연 조합 포함. '
                '층별 선택 필드: enemies=[{id,level}] 고정 적(5장, 첫 장이 리더), boss=카드id(보스 표시), rewards={tickets,gold} 보상 덮어쓰기',
        'sheet': SHEET, 'level': {'base': 5, 'step': 5, 'every': 10}, 'enemyCount': 5, 'maxTurns': 40,
        'ranges': {'same': [0.9, 1.0], 'weak': [0.6, 0.8]},
        'rewards': {'every': [[50, {'tickets': 10}], [10, {'tickets': 5}]]},
        'floors': floors,
    }
    with open(OUT, 'w', encoding='utf-8') as fp:
        fl = data.pop('floors')
        body = json.dumps(data, ensure_ascii=False, indent=1)[:-2]
        fp.write(body + ',\n "floors": [\n' + ',\n'.join('  ' + json.dumps(f, ensure_ascii=False) for f in fl) + '\n ]\n}\n')
    print(f'{len(floors)}층 → {os.path.normpath(OUT)}')
main()
