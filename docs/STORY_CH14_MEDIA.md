# CH14 「작은 아씨들」 멀티미디어

2026-11-07 KST. `origin/main` 기준의 별도 `story/ch14-images-20261107` 브랜치.
원본 `/workspace/ch14-media`의 1~10 순서를 유지했고, 기존 CH13과 **같은 `tools/story_media.py`**로 변환했다.
`story_1107.xlsx`의 CH14 멀티미디어 칸 숫자 1~10이 지정한 **정확한 대사 줄**에 연결했다.
기존 대사·전투 전/후 분리·적/마나/보상·엔딩 YouTube ID는 바꾸지 않았다.

## 파일 → 장면

줄 번호는 각 start / lines.default(전) / after(후) 배열에서 1부터 센 값이다.

| 순서 / 원본 | 결과 파일 | 장면 | 대사 cue | 시트 행 |
|---|---|---|---|---|
| 1.jpg | `img/story/ch14-01.webp` | 챕터 시작 2번째 줄 | 그리고 이혜경. 16살… 자신의 전부를 걸었던 소녀. | 3 |
| 2.mp4 | `video/story/ch14-02.mp4` | P4 전, 5번째 줄 | 언니, 언니는 안 무서워? | 53 |
| 3.mp4 | `video/story/ch14-03.mp4` | P6 후, 8번째 줄 | 한참이 지나서야… 그리고 언니에게 기어갔다. | 80 |
| 4.jpg | `img/story/ch14-04.webp` | P6 후, 16번째 줄 | 진경아…! 진경아, 가지 마! 언니 여기 있어! | 88 |
| 5.jpg | `img/story/ch14-05.webp` | P7 후, 3번째 줄 | 1일. 2일. 5일. 10일. 김성진의 검은 기운이… | 104 |
| 6.jpg | `img/story/ch14-06.webp` | P8 전, 5번째 줄 | 야, 이진경. 네 언니 죽었다며? 배척지에서 주워 온 애라며? | 115 |
| 7.jpg | `img/story/ch14-07.webp` | P13 전, 6번째 줄 | 담벼락 위에 소녀 하나가 내려앉았다… 이지영이었다. | 178 |
| 8.jpg | `img/story/ch14-08.webp` | P13 후, 2번째 줄 | 너의 염원이 너무 강력해서… 환생하는 걸 도와줄게. | 184 |
| 9.jpg | `img/story/ch14-09.webp` | P13 후, 9번째 줄 | 앗…아..어쩌지… | 191 |
| 10.jpg | `img/story/ch14-10.webp` | P18 후, 16번째 줄 | 아…진..진…뭐였더라..몇..살이랬지… | 286 |

## 변환 / 재현

- 이미지: RGB, LANCZOS 1280×720, WebP quality 80 / method 6.
- 영상: 752×416 fit/pad, libx264 preset slow / CRF 28 / yuv420p,
  오디오가 있는 원본은 AAC 96k, `+faststart`. 두 영상 모두 자르지 않고 전체 길이 유지.
- CH13과 동일한 `image` / `video` 속성을 해당 대사에 넣어 기존 렌더러/재생·리플레이 경로를 사용한다.
- `tools/ch14_media_manifest.json`: 원본/변환본 SHA-256, 파일 크기, 정확한 scene/line/text, 시트 행,
  영상 길이를 기록했다. 원본은 저장소에 넣지 않는다.
- `tools/make_thumbs.py` 실행: 카드 썸네일 89개 유지, 새 생성 0개. 스토리 이미지는 해당 도구의 카드 썸네일 대상이 아니다.
- 기존 staging SQL/분할 설치본을 재생성하고 manifest SHA-256을 대조했다. 해시는 동일하며 기존 bytes 표기의 3바이트 차이만 갱신했다. 게임 SQL 내용 변경이나 DB 적용은 없다.

```bash
# CH14 시트 값을 문자열 CSV로 내보낸 뒤, 이전 CH13과 같은 도구 사용
python3 tools/story_media.py 14 /path/to/CH14.csv /path/to/ch14-media
python3 tools/make_thumbs.py
node tools/build_staging_sql.mjs
node tools/build_staging_parts.mjs
node tools/test_ch14_media.mjs  # ffprobe 필요: 위치/순서/해시/인코딩/faststart
node tools/test_ch14.mjs        # 기존 챕터 전투/스토리 SQL 회귀 검사
npm run check:staging
npm run test:staging
npm run build:staging
```

배포/push는 수행하지 않았다. 미디어 파일만 배포 대상 웹 자산에 포함되며 추가 SQL 실행은 필요 없다.
