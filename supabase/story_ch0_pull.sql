-- =====================================================================
-- 챕터 0 클리어 후 강제 10회 프리미엄 영입 — 끝 표시(ch0Pull)를 서버 진행에 저장. 여러 번 실행해도 안전
-- 소환권 10장은 기존 규칙(챕터 전체 첫 클리어마다 +10, _story_ticket_sync · 계정당 한 번)이 그대로 지급 → 추가 지급 없음
-- story_mark_seen 허용 키에 'ch0Pull' 추가 (그 외 동작 동일)
-- =====================================================================
create or replace function public.story_mark_seen(p_key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d jsonb;
begin
  if p_key not in ('openingSeen', 'startSeen', 'ch0Pull') then raise exception 'invalid key'; end if;
  d := _story_lock(uid);
  return _story_save(uid, jsonb_set(d, array[p_key], 'true'::jsonb));
end $$;
revoke all on function public.story_mark_seen(text) from public, anon;
grant execute on function public.story_mark_seen(text) to authenticated;
