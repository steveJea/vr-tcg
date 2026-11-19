-- 읽기만 함. production 전용. camp_auto_exp_production.sql 적용 후 한 줄 확인. 기대: ok=true
-- installed md5(c4d0ab2c…) 이거나, 본문에 auto-exp 표시가 있으면 설치됨.
-- 원본 md5(135e0269…) 이면 아직 미설치(ok=false). 다른 md5 이면 딩순이에게 알려 주세요.
select (
  (select system_identifier::text from pg_catalog.pg_control_system()) = '7692130048193495360'
  and (
    (select md5(replace(prosrc, chr(13), '')) from pg_proc where oid = to_regprocedure('public.camp_status()')) = 'c4d0ab2c2d27d3f6ff62c0f6f78d7dd4'
    or position('57: 훈련소를 열지 않아도' in coalesce((select prosrc from pg_proc where oid = to_regprocedure('public.camp_status()')), '')) > 0
  )
) as ok,
(select md5(replace(prosrc, chr(13), '')) from pg_proc where oid = to_regprocedure('public.camp_status()')) as camp_status_md5;
