-- 시트 36~42 (스테이징 전용). Supabase SQL Editor 에 이 파일 전체를 한 번에 붙여 실행.
-- 임시표를 쓰지 않는다. 보상 규칙·슬롯·인원 상한은 바꾸지 않는다.
-- 1) 일일·주간 미션 이름. 2) 파견 새로고침이 이미 보낸 의뢰(taken)의 지역을 덮어쓰지 않게 막음.

create or replace function public._daily_defs() returns jsonb language sql immutable as $$ select '[
  {"key":"arcade","name":"아케이드 플레이 x 1","goal":1,"per":1,"reward":{"gold":1000}},
  {"key":"win","name":"전투 승리 x 3","goal":3,"per":1,"reward":{"gold":2000}},
  {"key":"story","name":"스토리 스테이지 클리어 x 2","goal":2,"per":1,"reward":{"gold":2000,"gem":10}},
  {"key":"tower","name":"시련의 탑 도전 x 1","goal":1,"per":1,"reward":{"gold":1500,"gem":10}},
  {"key":"skill","name":"고유기술 사용 x 10","goal":10,"per":20,"reward":{"gold":1500}}
]'::jsonb $$;

create or replace function public._weekly_defs() returns jsonb language sql immutable as $$ select '[
  {"key":"arcade","name":"아케이드 플레이 x 7","goal":7,"per":2,"reward":{"gold":8000,"tickets":1}},
  {"key":"win","name":"전투 승리 x 15","goal":15,"per":3,"reward":{"gold":10000,"gem":30}},
  {"key":"story","name":"스토리 스테이지 클리어 x 10","goal":10,"per":2,"reward":{"gold":10000,"gem":30}},
  {"key":"tower","name":"시련의 탑 도전 x 5","goal":5,"per":1,"reward":{"gold":8000,"gem":20}},
  {"key":"skill","name":"고유기술 사용 x 50","goal":50,"per":40,"reward":{"gold":8000,"gem":20}}
]'::jsonb $$;

-- 하단 새로고침(dispatch_refresh)은 p_all = false 로 이 함수를 부른다.
-- taken 칸은 건너뛰고, 혹시 갱신 문이 닿아도 taken 행은 고치지 않는다.
-- 하루가 바뀌어 게시판을 전부 다시 뽑는 경우(p_all)는 예전과 같다.
create or replace function public._dsp_fill(p_uid uuid, p_all boolean) returns void language plpgsql security definer set search_path = public as $$
declare best int; s int; z text; els text[] := array['WIND','FIRE','ICE','DARK','LIGHT']; cl text[] := array['CHARGE','CRUSH','DEFENSE','SUPPORT','DISTURB','FASCINATION'];
begin
  select coalesce(max(m.grade), 0) into best from jsonb_array_elements(_dsp_owned(p_uid)) o join dispatch_card_meta m on m.id = o->>'id' where m.grade <= 4;
  if p_all then delete from dispatch_offers where user_id = p_uid; end if;
  for s in 1..6 loop
    if not p_all and exists (select 1 from dispatch_offers where user_id = p_uid and slot = s and taken) then continue; end if;
    select id into z from dispatch_zones where grp = case when s <= 4 then 'exile' else 'safe' end and min_grade <= best
      order by -ln(greatest(random(), 1e-9)) / (1 + min_grade) limit 1;
    insert into dispatch_offers (user_id, slot, day, zone, el, cls, taken) values (p_uid, s, _dsp_day(), z, els[1 + floor(random() * 5)::int], cl[1 + floor(random() * 6)::int], false)
      on conflict (user_id, slot) do update set day = excluded.day, zone = excluded.zone, el = excluded.el, cls = excluded.cls, taken = false
      where dispatch_offers.taken = false;
  end loop;
end $$;
