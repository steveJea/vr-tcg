-- STAGING ONLY · 상점 v2 후속: 심연석 상점 '오늘의 장비' 칸 확률 변경 (2026-11-17 형님 결정)
-- 희귀(HR) 85% → 95% · 영웅(SR) 14% → 4.9% · 전설(UR) 1% → 0.1%. 가격·장비 단계는 그대로.
-- 선행: shop_v2_staging.sql (bd8e0700). 한 번에 실행 · 재실행 안전(같은 값으로 덮어씀). 다른 표·함수는 안 건드림.
-- 확률 = 가중치 / 가중치 합(1000). 이미 뽑힌 오늘 칸은 그대로, 내일(00시 한국 시간) 칸부터 새 확률.
begin;
do $guard$
begin
 if (select system_identifier::text from pg_catalog.pg_control_system()) is distinct from '7703759698107299042' then raise exception 'STOP: shop v2 gear odds staging only'; end if;
 if to_regclass('public.shop_gear_grades') is null then raise exception 'STOP: run shop_v2_staging.sql first'; end if;
end $guard$;
alter table public.shop_gear_grades drop constraint if exists shop_gear_grades_weight_check;
alter table public.shop_gear_grades add constraint shop_gear_grades_weight_check check (weight between 0 and 1000);
update public.shop_gear_grades set weight = case grade when 'HR' then 950 when 'SR' then 49 when 'UR' then 1 end where grade in ('HR','SR','UR');
commit;
select 'shop v2 gear odds: HR 95% · SR 4.9% · UR 0.1%' as result;
