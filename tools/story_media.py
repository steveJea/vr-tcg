#!/usr/bin/env python3
"""시트 '멀티미디어' 칸(H열) → 스토리 대사 줄에 image / video 붙이기 (임포터로 다시 만든 뒤 실행)
사용: python3 tools/story_media.py <챕터번호> <story__CHn.csv> <드라이브 폴더에서 받은 원본 폴더>
- 시트 숫자 N → 그 행 대사 줄에 img/story/chN-NN.webp (원본 N.jpg) 또는 video/story/chN-NN.mp4 (원본 N.mp4)
- 'N(5초 플레이)' → 영상 앞 5초만 잘라서 넣음. '엔딩: URL' 행은 건너뜀 (챕터 endingVideo 따로)
- 이미지: 1280x720 webp q80 · 영상: 752x416 h264 crf 28 + aac 96k (기존 ch5·ch9 영상과 같은 규격)
"""
import csv, json, os, re, subprocess, sys
chn, path, src = int(sys.argv[1]), sys.argv[2], sys.argv[3]
js = f'js/story-data-ch{chn}.js'
raw = open(js, encoding='utf8').read()
head, body = raw.split('window.STORY_DATA.chapters.push(', 1)
ch = json.loads(body.rsplit(');', 1)[0])
seq = list(ch.get('start', []))
for p in ch['phases']: seq += p['lines']['default'] + p.get('after', [])
R = [r + [''] * 10 for r in csv.reader(open(path, encoding='utf8'))][1:]
pos, out, miss = 0, [], []
for r in R:
    t = r[5].strip()
    if not (r[3].strip() and t): continue
    j = next((k for k in range(pos, len(seq)) if seq[k]['text'] == t), None)
    if j is None: continue
    pos = j + 1
    m = re.match(r'^\s*(\d+)\s*(?:\((\d+)초\s*플레이\))?\s*$', r[7])
    if not m: continue
    n, secs = int(m.group(1)), m.group(2)
    name = f'ch{chn}-{n:02d}'
    for k in ('image', 'video'): seq[j].pop(k, None)
    if os.path.exists(f'{src}/{n}.mp4'):
        dst = f'video/story/{name}.mp4'
        cmd = ['ffmpeg', '-loglevel', 'error', '-y', '-i', f'{src}/{n}.mp4'] + (['-t', secs] if secs else []) + ['-vf', 'scale=752:416:force_original_aspect_ratio=decrease:flags=lanczos,pad=752:416:(ow-iw)/2:(oh-ih)/2', '-c:v', 'libx264', '-preset', 'slow', '-crf', '28', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', dst]
        subprocess.run(cmd, check=True); seq[j]['video'] = dst
    elif os.path.exists(f'{src}/{n}.jpg'):
        dst = f'img/story/{name}.webp'
        subprocess.run(['python3', '-c', f"from PIL import Image;Image.open('{src}/{n}.jpg').convert('RGB').resize((1280,720),Image.LANCZOS).save('{dst}','WEBP',quality=80,method=6)"], check=True)
        seq[j]['image'] = dst
    else: miss.append(n); continue
    out.append((n, dst, os.path.getsize(dst), t[:24]))
open(js, 'w', encoding='utf8').write(head + 'window.STORY_DATA.chapters.push(' + json.dumps(ch, ensure_ascii=False, indent=1) + ');\n')
for o in out: print(*o)
if miss: print('MISSING in Drive:', miss)
