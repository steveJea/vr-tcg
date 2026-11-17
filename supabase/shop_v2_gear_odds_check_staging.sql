-- STAGING 확인 (읽기 전용) · shop_v2_gear_odds_staging.sql 적용 후 실행. ok = true 면 정상.
select (select string_agg(grade||'='||tier||':'||price_gem||':'||weight, ',' order by grade) from public.shop_gear_grades) = 'HR=4:500:950,SR=5:1000:49,UR=6:5000:1' as ok,
 (select string_agg(grade||' '||trim_scale(round(weight*100.0/t,2))||'%', ' · ' order by grade) from public.shop_gear_grades, (select sum(weight) t from public.shop_gear_grades) s) as odds;
