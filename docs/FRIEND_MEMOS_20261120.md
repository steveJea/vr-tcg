# 친구 1:1 쪽지 (1단계, 스테이징)

오늘(2026-11-20) 실섭 업데이트(PR #676 / `release/2026-11-20`)에는 넣지 않습니다. 테섭 SQL만 형님이 실행합니다.

## 플래그

- 이름: `friend_memos`
- 기본값: **OFF**. 일반 유저에게는 쪽지 버튼·함이 보이지 않습니다.
- 꺼져 있어도 관리자 `stevejean77@gmail.com` 은 테스트할 수 있습니다.

켜는 방법 (테섭, SQL 설치 후):

1. 관리자 페이지(`admin.html`) → **✉️ 쪽지** 탭 → **일반 유저에게 열기**
2. 또는 SQL Editor:

```sql
select public.admin_feature_flag_set('friend_memos', true);
```

끄기:

```sql
select public.admin_feature_flag_set('friend_memos', false);
```

확인: `supabase/friend_memos_check_staging.sql` (한 줄). `ok = true` 이고 `flag_on` 이 현재 열림 여부입니다.

운영 SQL(`friend_memos_production.sql`)은 아직 실행하지 마세요.

## 제한

- 친구만 발송. 차단은 양쪽 모두 발송 거부.
- 본문 1~200자. `nick_banned` + `_memo_norm`(공백·기호·숫자 제거) 금칙어.
- 초당 1, 분당 10, 같은 상대 하루(KST) 20통.
- 30일 지난 쪽지는 `memo_purge_expired()` 로 지우되, 신고된 쪽지는 남깁니다. (인증 유저에게는 열려 있지 않음)

약관·개인정보 초안은 `docs/CHAT_TERMS_PRIVACY_DRAFT.md` 에만 있고, 실제 `terms.html` / `privacy.html` 에는 아직 반영하지 않았습니다.
