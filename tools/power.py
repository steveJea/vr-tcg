"""카드 power(전투력) 공식 「옵션 B」 — data/cards.csv · npc_cards.csv · 스토리 boost 가 모두 이 식을 따름 (js/rules.js calcPower 와 같음)
전투값 = (ATK×1.2 + DEF + HP×0.5) × (1 + (PHY+MEN)/200) × (0.8 + MOR/250)
power  = 버림(전투값 × 등급배율 × SCALE)
사용법: python3 tools/power.py          → 두 CSV 에서 공식과 다른 행 출력 (--fix 로 power 덮어씀)"""
import csv, math, os, sys
GRADE_MULT = {'NORMAL': 1, 'RARE': 2.5, 'HIGH RARE': 4, 'SUPER RARE': 6, 'ULTRA RARE': 8, 'MYTHIC RARE': 8}
SCALE = 11.4527618

def power(grade, HP, ATK, DEF, PHY, MEN, MOR):
    b = (float(ATK) * 1.2 + float(DEF) + float(HP) * 0.5) * (1 + (float(PHY) + float(MEN)) / 200) * (0.8 + float(MOR) / 250)
    return math.trunc(b * GRADE_MULT[grade.strip()] * SCALE)

def card_power(c, **over):
    """c: csv 행(dict). over: HP/ATK/DEF 등 덮어쓸 스탯 (스토리 boost)"""
    s = {k: over.get(k, c[k]) for k in ('HP', 'ATK', 'DEF', 'PHY', 'MEN', 'MOR')}
    return power(c['grade'], **s)

if __name__ == '__main__':
    root = os.path.join(os.path.dirname(__file__), '..')
    for f in ('data/cards.csv', 'data/npc_cards.csv'):
        p = os.path.join(root, f); txt = open(p, encoding='utf-8-sig').read(); lines = txt.split('\n'); h = lines[0].split(','); pi = h.index('power')
        for i, l in enumerate(lines[1:], 1):
            if not l: continue
            v = l.split(','); want = card_power(dict(zip(h, v)))
            if str(want) != v[pi]: print(f, v[0], v[1], v[pi], '->', want); v[pi] = str(want); lines[i] = ','.join(v)
        if '--fix' in sys.argv: open(p, 'w', encoding='utf-8').write('\n'.join(lines))
