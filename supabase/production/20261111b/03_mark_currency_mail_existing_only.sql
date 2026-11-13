-- (선택) 오늘 밤 보낸 재화 전체 우편(심연석 200 · 골드 50,000 · 피 50,000)을 '기존 가입자만'으로 바꾸기. 20261111b 설치 뒤 운영에서 한 번.
-- 보낸 뒤 가입한 계정이 아직 받지 않은(미수령) 사본은 지움. 이미 받은 사본은 되돌리지 않고 개수만 보여 줌. 다시 실행해도 안전.
do $mark_currency_mail$
declare n int; bid bigint; removed int; kept int;
begin
  if (select system_identifier::text from pg_control_system()) is distinct from '7692130048193495360' then raise exception 'STOP: production only'; end if;
  if not exists(select 1 from vr_rollout_private.releases where release_id='20261111b') then raise exception 'STOP: 20261111b 먼저 설치'; end if;
  select count(*), min(id) into n, bid from public.mail_broadcast
   where created_at >= timestamptz '2026-11-11 22:30+09' and created_at < timestamptz '2026-11-13 00:00+09'
     and payload = '{"gem":200,"cur":{"gold":50000,"blood":50000}}'::jsonb;
  if n <> 1 then raise exception 'STOP: 재화 우편이 정확히 1개여야 함 (찾은 수 %)', n; end if;
  update public.mail_broadcast set existing_only = true where id = bid;
  delete from public.player_mail m using auth.users u, public.mail_broadcast b
   where m.broadcast_id = bid and b.id = bid and u.id = m.user_id and u.created_at > b.created_at and m.claimed_at is null;
  get diagnostics removed = row_count;
  select count(*) into kept from public.player_mail m join auth.users u on u.id = m.user_id join public.mail_broadcast b on b.id = m.broadcast_id
   where m.broadcast_id = bid and u.created_at > b.created_at and m.claimed_at is not null;
  raise notice '재화 우편 % : 기존 가입자만으로 변경. 보낸 뒤 가입자 미수령 사본 % 개 삭제, 이미 받은 % 개는 그대로', bid, removed, kept;
end $mark_currency_mail$;
