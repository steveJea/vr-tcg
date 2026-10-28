# 카드 ID 바꾸기 (10자리 → 10001~10474)

- `card_id_map.csv` — 고정 대응표 (old_id,new_id,name,gender,base_id). 가나다순 한 줄 번호, 변형은 원본 바로 뒤. **이후 수정 금지.**
- 성별 접두어 없앰 — 성별은 카드 데이터 `gender` 에서 읽음. 세력전 NPC 덱(`_war_npc_deck`)은 남자 ID 목록으로 섞음.
- 앞으로 새 카드(각성/염원/파멸 포함): `python3 tools/next_card_id.py [--base 원본ID]` → 다음 번호, `base_id` 칸에 원본.
- `remap.py <repo> [--apply]` — 내용 바꾸기 + 파일 이름 `git mv` (미리보기 기본).
- `verify.py [repo]` — 옛 ID 0개 확인 (두 저장소).
- `test_remap_sql.mjs` — `supabase/card_id_remap.sql` 을 PGlite 옛 DB 에 돌려 확인.
- 클라이언트: `js/id-alias.js` — 옛 ID → 새 ID (localStorage 1회 변환 + cardById/story 정규화).

## 적용 순서 (점검 시간)
1. 점검 공지 → 서비스 멈춤 (새 저장 막기).
2. Supabase SQL Editor 에서 `supabase/card_id_remap.sql` 한 번 실행 (한 트랜잭션; 옛 ID 남으면 전부 되돌림). 결과 표에서 변경 전/후 확인 (변경 후 모두 0).
3. 바로 이어서 **월드컵 PR 먼저 머지 → vr-tcg PR 머지** (게임이 월드컵 raw 그림을 씀).
4. raw.githubusercontent / Pages 캐시 약 5~10분 대기 → 강력 새로고침으로 카드 그림·스토리 확인.
5. `python3 tools/idmap/verify.py` (두 저장소) + SQL 확인: `select count(*) from card_id_alias;` = 474.
6. 점검 해제. `card_id_alias` 표와 `js/id-alias.js` 는 몇 주 유지 (열린 탭·localStorage·공유 링크용) 후 제거.

되돌리기: 2단계 실패 시 자동 롤백. 2단계 후 문제면 PR revert + `card_id_alias` 로 반대 방향 변환.
