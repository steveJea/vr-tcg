-- PR 3/3: PvP 랭커 정보 팝업 + 공지 게시판. 여러 번 실행해도 안전. RLS 켬.
-- 필요: pvp.sql, phaseE_2.sql(player_state), guild.sql, admin.sql(_admin_guard)

-- 1) PvP 랭커 정보 — 로그인 유저만. 순위로 조회(유저 id 노출 없음). 공개 필드만 반환:
--    닉네임 · 계정 레벨 · 리더 카드 id · 해당 리그/모드 PvP 덱(카드 id·레벨) · 소속 조직(이름·엠블럼)
create or replace function public.pvp_user_info(p_league text, p_mode text, p_rank int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); s date := _pvp_season(); t uuid; g record; deck jsonb; lead text;
begin
  if uid is null then raise exception 'login required' using errcode = '42501'; end if;
  perform _pvp_ok(p_league, p_mode);
  if p_rank is null or p_rank < 1 or p_rank > 100 then raise exception 'bad rank'; end if;
  select x.user_id into t from (select r.user_id, row_number() over (order by r.rating desc, r.wins desc, r.user_id) rn
      from pvp_ratings r where r.league = p_league and r.mode = p_mode and r.season = s and r.wins + r.losses > 0) x where x.rn = p_rank;
  if t is null then raise exception 'not found'; end if;
  select o->>'id' into lead from story_progress sp, jsonb_array_elements(case when jsonb_typeof(sp.data->'owned') = 'array' then sp.data->'owned' else '[]'::jsonb end) o
    where sp.user_id = t and o->>'uid' = sp.data->>'leader' limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('slot', d.slot, 'cards',
      (select coalesce(jsonb_agg(jsonb_build_object('id', c->>'id', 'level', coalesce((c->>'level')::int, 1))), '[]'::jsonb)
         from jsonb_array_elements(case when jsonb_typeof(d.snap->'cards') = 'array' then d.snap->'cards' when jsonb_typeof(d.snap) = 'array' then d.snap else '[]'::jsonb end) c)) order by d.slot), '[]'::jsonb)
    into deck from pvp_decks d where d.user_id = t and d.league = p_league and d.mode = p_mode;
  select gg.name, gg.emblem into g from guild_members m join guilds gg on gg.id = m.guild_id where m.user_id = t;
  return jsonb_build_object('ok', true, 'rank', p_rank, 'me', t = uid,
    'name', coalesce((select nickname from profiles where id = t), '플레이어'),
    'level', coalesce((select level from player_state where user_id = t), 1),
    'leader', lead, 'decks', deck,
    'guild', case when g.name is null then null else jsonb_build_object('name', g.name, 'emblem', g.emblem) end);
end $$;
revoke all on function public.pvp_user_info(text, text, int) from public, anon;
grant execute on function public.pvp_user_info(text, text, int) to authenticated;

-- 2) 공지 게시판 — 누구나 읽기, 쓰기·수정·삭제는 관리자 RPC 만
create table if not exists public.notices (
  id         bigint generated always as identity primary key,
  body       text not null check (char_length(body) between 1 and 200),
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notices_order_idx on public.notices (pinned desc, created_at desc);
alter table public.notices enable row level security;
revoke all on public.notices from public, anon, authenticated;
grant select on public.notices to anon, authenticated;
drop policy if exists "notices_read_all" on public.notices;
create policy "notices_read_all" on public.notices for select to anon, authenticated using (true);

-- 저장: p_id null = 새 글, 아니면 수정
create or replace function public.admin_notice_save(p_id bigint, p_body text, p_pinned boolean) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare r notices; b text := btrim(coalesce(p_body, ''));
begin
  perform public._admin_guard();
  if char_length(b) not between 1 and 200 then raise exception 'body 1~200'; end if;
  if p_id is null then
    insert into notices (body, pinned) values (b, coalesce(p_pinned, false)) returning * into r;
  else
    update notices set body = b, pinned = coalesce(p_pinned, pinned), updated_at = now() where id = p_id returning * into r;
    if r.id is null then raise exception 'not found'; end if;
  end if;
  return to_jsonb(r);
end $$;
create or replace function public.admin_notice_delete(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
begin
  perform public._admin_guard();
  delete from notices where id = p_id;
  return jsonb_build_object('ok', found);
end $$;
revoke all on function public.admin_notice_save(bigint, text, boolean), public.admin_notice_delete(bigint) from public, anon;
grant execute on function public.admin_notice_save(bigint, text, boolean), public.admin_notice_delete(bigint) to authenticated;
