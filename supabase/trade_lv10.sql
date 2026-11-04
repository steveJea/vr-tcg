-- ===== 거래 계정 레벨 하한 20 → 10 (형님 결정 2026-11-04) =====
-- 일반 거래·즉시 구매·지정 거래(보내는 사람·받는 사람) 모두 _trade_gate 가 trade_config.min_level 을 읽으므로 값만 바꾸면 전부 적용
-- 여러 번 실행해도 안전 (값만 바꿈, 지우는 것 없음)
insert into public.trade_config (key, val, note) values ('min_level', 10, '계정 레벨 하한')
on conflict (key) do update set val = 10 where public.trade_config.val <> 10;
