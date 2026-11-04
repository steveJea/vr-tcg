#!/usr/bin/env python3
"""카드 그림 작은 버전(썸네일) 만들기 → img/thumb/<id>.webp (가로 300px, 카드칸 78~150px의 2배)

원본은 그대로 두고, 작은 칸(전투 손패/필드, 덱, 목록 등)에서만 썸네일을 씀.
썸네일이 없으면 화면에서 자동으로 원본을 다시 불러오므로(img-fallback.js) 빠져도 깨지지 않음.

사용법 (새 캐릭터 추가 후 다시 실행, 이미 있는 건 원본이 더 새로울 때만 다시 만듦):
  git clone --depth 1 --filter=blob:none --sparse https://github.com/steveJea/vr-ideal-worldcup ../viw
  (cd ../viw && git sparse-checkout set img/bt_img)
  pip install pillow
  python3 tools/make_thumbs.py --bt-img ../viw/img/bt_img
  # --force 로 전부 다시

원본 고르는 순서 (화면에 실제로 뜨는 그림과 같게):
  1) js/img-fallback.js 의 OVERRIDE id → img/npc/<id>.webp
  2) vr-ideal-worldcup img/bt_img/<id>.webp
  3) img/npc/<id>.webp   4) img/cards/<id>.webp
"""
import argparse, os, re, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, Q = 300, 80

def ids_in(d):
    return {f[:-5] for f in os.listdir(d) if f.endswith('.webp') and f[:-5].isdigit()} if d and os.path.isdir(d) else set()

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--bt-img', help='vr-ideal-worldcup/img/bt_img 폴더'); ap.add_argument('--force', action='store_true'); a = ap.parse_args()
    npc, cards, out = (os.path.join(ROOT, 'img', x) for x in ('npc', 'cards', 'thumb'))
    os.makedirs(out, exist_ok=True)
    ov = set(re.findall(r"'(\d+)'", re.search(r'OVERRIDE = new Set\(\[([^\]]*)\]', open(os.path.join(ROOT, 'js/img-fallback.js'), encoding='utf-8').read()).group(1)))
    if not a.bt_img: print('주의: --bt-img 없음 → 이 저장소 그림(img/npc, img/cards)만 만듦', file=sys.stderr)
    bt, nn, cc = ids_in(a.bt_img), ids_in(npc), ids_in(cards)
    made = skip = 0
    for i in sorted(bt | nn | cc):
        src = (os.path.join(npc, i + '.webp') if i in ov and i in nn else
               os.path.join(a.bt_img, i + '.webp') if i in bt else
               os.path.join(npc, i + '.webp') if i in nn else os.path.join(cards, i + '.webp'))
        dst = os.path.join(out, i + '.webp')
        if not a.force and os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src): skip += 1; continue
        im = Image.open(src); im.load()
        if im.mode not in ('RGB', 'RGBA'): im = im.convert('RGBA')
        if im.width > W: im = im.resize((W, round(im.height * W / im.width)), Image.LANCZOS)
        im.save(dst, 'WEBP', quality=Q, method=6); made += 1
    print(f'썸네일 {made}개 만듦, {skip}개 그대로 → img/thumb/')

if __name__ == '__main__': main()
