-- =============================================================
-- 12 · 技術徽章
-- 教練 / 管理員按技術評核頒發徽章，家長喺會員區睇到。
-- 徽章種類固定（同 lib/constants.ts BADGES 一致），每個學員每種一個。
-- =============================================================

create table public.student_badges (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.students (id) on delete cascade,
  badge_key   text not null check (badge_key in (
    'dribble', 'layup', 'shooting', 'passing', 'defense', 'teamwork', 'attendance', 'level_up'
  )),
  note        text check (length(note) <= 200),
  awarded_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (student_id, badge_key)
);
create index student_badges_student_id_idx on public.student_badges (student_id);

alter table public.student_badges enable row level security;

create policy "student_badges: 家長可讀自己學員徽章" on public.student_badges
  for select to authenticated
  using (public.owns_student(student_id));

create policy "student_badges: 教練可讀自己班學員徽章" on public.student_badges
  for select to authenticated
  using (public.is_coach_of_student(student_id));

create policy "student_badges: 教練可頒發徽章" on public.student_badges
  for insert to authenticated
  with check (public.is_coach_of_student(student_id) and awarded_by = (select auth.uid()));

create policy "student_badges: 教練可收回自己頒發嘅徽章" on public.student_badges
  for delete to authenticated
  using (public.is_coach_of_student(student_id) and awarded_by = (select auth.uid()));

create policy "student_badges: admin 全權" on public.student_badges
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
