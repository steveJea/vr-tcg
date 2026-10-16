-- =====================================================================
-- VR: Abyss Gate - 스토리 모드 저장 테이블 (추가분)
-- 사용법: Supabase 대시보드 > SQL Editor > New query 에 붙여넣고 Run. 여러 번 실행해도 안전.
-- 본인 행만 읽기/쓰기 가능 (RLS: user_id = auth.uid())
-- =====================================================================
create table if not exists public.story_progress (
  user_id     uuid primary key references auth.users(id) on delete cascade default auth.uid(),
  data        jsonb not null default '{}'::jsonb check (pg_column_size(data) < 200000),
  updated_at  timestamptz not null default now()
);
alter table public.story_progress enable row level security;
drop policy if exists "story_select_own" on public.story_progress;
create policy "story_select_own" on public.story_progress for select using (user_id = auth.uid());
drop policy if exists "story_insert_own" on public.story_progress;
create policy "story_insert_own" on public.story_progress for insert with check (user_id = auth.uid());
drop policy if exists "story_update_own" on public.story_progress;
create policy "story_update_own" on public.story_progress for update using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.story_progress to authenticated;
