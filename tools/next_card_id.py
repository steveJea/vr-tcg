#!/usr/bin/env python3
"""새 카드 ID 받기: data/cards.csv · data/npc_cards.csv 에서 가장 큰 ID + 1.
사용: python3 tools/next_card_id.py              → 다음 번호
      python3 tools/next_card_id.py --base 10325  → 다음 번호 + 그 카드의 base_id 칸에 넣을 값(원본 캐릭터 확인)
      python3 tools/next_card_id.py -n 3          → 연속 3개
변형(각성/염원/파멸)도 그냥 다음 번호를 받고, base_id 에 원본 ID 를 적어 묶음."""
import csv, os, sys, argparse
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
rows = []
for f in ('data/cards.csv', 'data/npc_cards.csv'):
    p = os.path.join(ROOT, f)
    if os.path.exists(p): rows += list(csv.DictReader(open(p, encoding='utf-8-sig')))
ids = [int(r['id']) for r in rows if r.get('id', '').isdigit()]
if any(i >= 10 ** 9 for i in ids): sys.exit('옛 10자리 ID 가 남아 있음 — tools/idmap/verify.py 먼저')
ap = argparse.ArgumentParser(); ap.add_argument('--base'); ap.add_argument('-n', type=int, default=1); a = ap.parse_args()
nxt = max(ids, default=10000) + 1
print(' '.join(str(nxt + k) for k in range(a.n)))
if a.base:
    b = next((r for r in rows if r['id'] == a.base), None)
    if not b: sys.exit(f'base {a.base} 없음')
    print(f"base_id={a.base} ({b['name']}, {b['gender']})")
