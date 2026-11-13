# 카드 원본 그림을 vr-ideal-worldcup(읽기만) 에서 이 저장소 img/bt_img/ 로 옮겨 오기 + 크기 규칙(576x864 이하·100KB 이하)
# 사용: python3 tools/sync_card_art.py [커밋SHA]   (기본: tools/card_art_source.json 의 sha) · 새 카드가 생기면 다시 돌리면 됨
import io, json, os, sys, urllib.request
from PIL import Image
SRC = json.load(open('tools/card_art_source.json'))
sha = sys.argv[1] if len(sys.argv) > 1 else SRC['sha']
tree = json.load(urllib.request.urlopen(f"https://api.github.com/repos/{SRC['repo']}/git/trees/{sha}?recursive=1"))
paths = [x['path'] for x in tree['tree'] if x['type'] == 'blob' and x['path'].startswith('img/bt_img/') and not os.path.basename(x['path']).startswith('_') and x['path'].endswith('.webp')]
os.makedirs('img/bt_img', exist_ok=True); n = 0
for p in paths:
    raw = urllib.request.urlopen(f"https://raw.githubusercontent.com/{SRC['repo']}/{sha}/{p}").read()
    im = Image.open(io.BytesIO(raw)); out = raw
    if im.width > 576 or im.height > 864 or len(raw) > 100000:
        im.thumbnail((576, 864), Image.Resampling.LANCZOS)
        for q in range(86, 30, -4):
            b = io.BytesIO(); im.save(b, 'WEBP', quality=q, method=6)
            if b.tell() <= 100000: break
        out = b.getvalue()
    open('img/bt_img/' + os.path.basename(p), 'wb').write(out); n += 1
json.dump({**SRC, 'sha': sha, 'count': n}, open('tools/card_art_source.json', 'w'), ensure_ascii=False, indent=2)
print(f'{n} card images from {sha[:8]}')
