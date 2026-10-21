-- 課程預設教練（10/16）：開新班次時自動帶入，仍然可以逐班改。可為空（未設 = 開班時自己揀）。
alter table public.courses
  add column if not exists default_coach_id uuid references public.coaches (id) on delete set null;

create index if not exists courses_default_coach_id_idx on public.courses (default_coach_id);
