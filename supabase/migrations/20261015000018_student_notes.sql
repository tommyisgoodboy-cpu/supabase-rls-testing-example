-- 學員備注（10/15）：教練 / 管理員記低「手受傷」「逢週五 19:00 要補習」呢類資料；只有職員睇到。
create table public.student_notes (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.students (id) on delete cascade,
  kind        text not null default 'general' check (kind in ('health', 'schedule', 'general')),
  body        text not null check (length(body) between 1 and 200),
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index student_notes_student_id_idx on public.student_notes (student_id);

alter table public.student_notes enable row level security;

create policy "student_notes: 教練可讀自己班學員備注" on public.student_notes
  for select to authenticated
  using (public.is_coach_of_student(student_id));

create policy "student_notes: 教練可加備注" on public.student_notes
  for insert to authenticated
  with check (public.is_coach_of_student(student_id) and created_by = (select auth.uid()));

create policy "student_notes: 教練可刪自己寫嘅備注" on public.student_notes
  for delete to authenticated
  using (public.is_coach_of_student(student_id) and created_by = (select auth.uid()));

create policy "student_notes: admin 全權" on public.student_notes
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
