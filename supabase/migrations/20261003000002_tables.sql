-- =============================================================
-- 02 · 16 個 table + index + view
-- 全部 uuid primary key（site_settings 用 key 做 PK）、created_at timestamptz。
-- 積分餘額唔儲存，由 points_ledger 加總（view: member_points_balance）。
-- =============================================================

-- ---------- 用戶 ----------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text,
  phone       text,
  role        public.user_role not null default 'member',
  created_at  timestamptz not null default now()
);
comment on table public.profiles is '所有已註冊用戶；role = member / coach / admin';

-- parent_id 可為 null：訪客報名時未有帳戶，家長資料記喺 enrollments
create table public.students (
  id             uuid primary key default gen_random_uuid(),
  parent_id      uuid references public.profiles (id) on delete set null,
  name           text not null,
  birth_year     integer not null check (birth_year between 1940 and 2030),
  years_playing  integer not null default 0 check (years_playing >= 0),
  level          public.skill_level not null default 'starter',
  notes          text,
  created_at     timestamptz not null default now()
);
comment on table public.students is '學員（小朋友或成人學員）；parent_id 為 null 代表訪客報名、未連結帳戶';
comment on column public.students.years_playing is '球齡（年）';
create index students_parent_id_idx on public.students (parent_id);

create table public.coaches (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid unique references public.profiles (id) on delete set null,
  name            text not null,
  bio             text,
  photo_url       text,
  certifications  text[] not null default '{}',
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

-- ---------- 課程 ----------
create table public.venues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  district    text not null,
  address     text not null,
  map_url     text,
  created_at  timestamptz not null default now()
);

create table public.courses (
  id              uuid primary key default gen_random_uuid(),
  title           text not null,
  age_group       public.age_group not null,
  level           public.skill_level not null,
  description     text,
  price           numeric(10, 2) not null check (price >= 0),
  sessions_count  integer not null check (sessions_count > 0),
  cover_url       text,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

-- weekday 用 ISO：1 = 星期一 … 7 = 星期日
create table public.classes (
  id          uuid primary key default gen_random_uuid(),
  course_id   uuid not null references public.courses (id) on delete cascade,
  coach_id    uuid references public.coaches (id) on delete set null,
  venue_id    uuid references public.venues (id) on delete set null,
  weekday     smallint not null check (weekday between 1 and 7),
  start_time  time not null,
  end_time    time not null,
  start_date  date not null,
  end_date    date not null,
  capacity    integer not null check (capacity > 0),
  created_at  timestamptz not null default now(),
  check (end_time > start_time),
  check (end_date >= start_date)
);
create index classes_course_id_idx on public.classes (course_id);
create index classes_coach_id_idx on public.classes (coach_id);
create index classes_venue_id_idx on public.classes (venue_id);

create table public.class_sessions (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  session_date  date not null,
  status        public.session_status not null default 'scheduled',
  created_at    timestamptz not null default now(),
  unique (class_id, session_date)
);
create index class_sessions_date_idx on public.class_sessions (session_date);

-- 訪客報名嘅家長資料存喺 parent_* 欄位
create table public.enrollments (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  student_id    uuid not null references public.students (id) on delete cascade,
  status        public.enrollment_status not null default 'pending',
  source        public.enrollment_source not null default 'guest',
  parent_name   text,
  parent_phone  text,
  parent_email  text,
  notes         text,
  created_at    timestamptz not null default now()
);
-- 同一學員同一班只可以有一個有效報名
create unique index enrollments_active_unique
  on public.enrollments (class_id, student_id)
  where status <> 'cancelled';
create index enrollments_student_id_idx on public.enrollments (student_id);
create index enrollments_status_idx on public.enrollments (status);

create table public.attendance (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.class_sessions (id) on delete cascade,
  student_id  uuid not null references public.students (id) on delete cascade,
  status      public.attendance_status not null,
  marked_by   uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (session_id, student_id)
);
create index attendance_student_id_idx on public.attendance (student_id);

-- ---------- 商店 ----------
create table public.products (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text,
  price        numeric(10, 2) not null check (price >= 0),
  images       text[] not null default '{}',
  category     public.product_category not null,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.product_variants (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products (id) on delete cascade,
  size        text,
  color       text,
  stock       integer not null default 0 check (stock >= 0),
  created_at  timestamptz not null default now(),
  unique nulls not distinct (product_id, size, color)
);

create table public.orders (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles (id) on delete restrict,
  total              numeric(10, 2) not null check (total >= 0),
  points_used        integer not null default 0 check (points_used >= 0),
  status             public.order_status not null default 'pending_payment',
  payment_proof_url  text,
  created_at         timestamptz not null default now()
);
create index orders_profile_id_idx on public.orders (profile_id);
create index orders_status_idx on public.orders (status);

create table public.order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders (id) on delete cascade,
  variant_id  uuid not null references public.product_variants (id) on delete restrict,
  qty         integer not null check (qty > 0),
  unit_price  numeric(10, 2) not null check (unit_price >= 0),
  created_at  timestamptz not null default now()
);
create index order_items_order_id_idx on public.order_items (order_id);

-- 團體訂製查詢；訪客都可以提交（profile_id 為 null）
create table public.custom_requests (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid references public.profiles (id) on delete set null,
  team_name       text not null,
  contact_name    text not null,
  contact_phone   text not null,
  contact_email   text,
  item_type       public.custom_item_type not null,
  qty             integer not null check (qty > 0),
  size_breakdown  jsonb not null default '{}'::jsonb,
  colors          text,
  logo_url        text,
  roster          jsonb not null default '[]'::jsonb,
  due_date        date,
  notes           text,
  quote_amount    numeric(10, 2) check (quote_amount >= 0),
  quote_note      text,
  status          public.custom_request_status not null default 'submitted',
  created_at      timestamptz not null default now()
);
comment on column public.custom_requests.size_breakdown is '尺碼分佈，例如 {"S": 3, "M": 5}';
comment on column public.custom_requests.roster is '號碼名單，例如 [{"number": 7, "name": "CHAN"}]';
create index custom_requests_profile_id_idx on public.custom_requests (profile_id);

-- ---------- 積分 ----------
create table public.points_ledger (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  delta       integer not null check (delta <> 0),
  reason      text not null,
  ref_type    text,
  ref_id      uuid,
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);
create index points_ledger_profile_id_idx on public.points_ledger (profile_id);
create index points_ledger_ref_idx on public.points_ledger (ref_type, ref_id);

-- ---------- 網站設定 ----------
create table public.site_settings (
  key         text primary key,
  value       jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------- Views ----------
-- security_invoker：查詢者只會睇到 RLS 容許佢睇嘅流水帳
create view public.member_points_balance
with (security_invoker = true) as
select profile_id, sum(delta)::integer as balance
from public.points_ledger
group by profile_id;
