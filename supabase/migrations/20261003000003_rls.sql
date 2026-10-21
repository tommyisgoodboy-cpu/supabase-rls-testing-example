-- =============================================================
-- 03 · Row Level Security
-- 原則：
--   - 每個 table 都開 RLS，admin 有一條 "for all" policy
--   - 公開資料（課程、班次、教練、場地、商品、設定）anon 都可以讀
--   - 會員只睇到自己 / 自己學員嘅資料
--   - 教練只睇到自己負責班嘅學員同點名
--   - 訪客報名、下單等寫入會喺之後階段用 security definer RPC 做，
--     唔直接開放 anon insert
-- =============================================================

alter table public.profiles          enable row level security;
alter table public.students          enable row level security;
alter table public.coaches           enable row level security;
alter table public.venues            enable row level security;
alter table public.courses           enable row level security;
alter table public.classes           enable row level security;
alter table public.class_sessions    enable row level security;
alter table public.enrollments       enable row level security;
alter table public.attendance        enable row level security;
alter table public.products          enable row level security;
alter table public.product_variants  enable row level security;
alter table public.orders            enable row level security;
alter table public.order_items       enable row level security;
alter table public.custom_requests   enable row level security;
alter table public.points_ledger     enable row level security;
alter table public.site_settings     enable row level security;

-- ---------- profiles ----------
-- insert 由 auth trigger（handle_new_user）負責；改 role 由 guard trigger 擋
create policy "profiles: 自己可讀" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

create policy "profiles: 自己可改" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "profiles: admin 全權" on public.profiles
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- students ----------
create policy "students: 家長可讀自己學員" on public.students
  for select to authenticated
  using (parent_id = (select auth.uid()));

create policy "students: 教練可讀自己班學員" on public.students
  for select to authenticated
  using (public.is_coach_of_student(id));

create policy "students: 家長可新增學員" on public.students
  for insert to authenticated
  with check (parent_id = (select auth.uid()));

create policy "students: 家長可改自己學員" on public.students
  for update to authenticated
  using (parent_id = (select auth.uid()))
  with check (parent_id = (select auth.uid()));

create policy "students: 家長可刪自己學員" on public.students
  for delete to authenticated
  using (parent_id = (select auth.uid()));

create policy "students: admin 全權" on public.students
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- coaches ----------
create policy "coaches: 公開讀取在職教練" on public.coaches
  for select to anon, authenticated
  using (is_active);

create policy "coaches: 教練可讀自己" on public.coaches
  for select to authenticated
  using (profile_id = (select auth.uid()));

create policy "coaches: admin 全權" on public.coaches
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- venues ----------
create policy "venues: 公開讀取" on public.venues
  for select to anon, authenticated
  using (true);

create policy "venues: admin 全權" on public.venues
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- courses ----------
create policy "courses: 公開讀取上架課程" on public.courses
  for select to anon, authenticated
  using (is_active);

create policy "courses: admin 全權" on public.courses
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- classes ----------
create policy "classes: 公開讀取" on public.classes
  for select to anon, authenticated
  using (true);

create policy "classes: admin 全權" on public.classes
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- class_sessions ----------
create policy "class_sessions: 公開讀取" on public.class_sessions
  for select to anon, authenticated
  using (true);

create policy "class_sessions: 教練可改自己班狀態" on public.class_sessions
  for update to authenticated
  using (public.is_coach_of_class(class_id))
  with check (public.is_coach_of_class(class_id));

create policy "class_sessions: admin 全權" on public.class_sessions
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- enrollments ----------
create policy "enrollments: 家長可讀自己學員報名" on public.enrollments
  for select to authenticated
  using (public.owns_student(student_id));

create policy "enrollments: 教練可讀自己班報名" on public.enrollments
  for select to authenticated
  using (public.is_coach_of_class(class_id));

-- 會員幫自己學員報名；client 只應送 pending，額滿時 BEFORE trigger 會改做 waitlist。
-- with check 喺 trigger 之後先評估，所以要同時容許 waitlist。
create policy "enrollments: 會員可為自己學員報名" on public.enrollments
  for insert to authenticated
  with check (
    public.owns_student(student_id)
    and source = 'member'
    and status in ('pending', 'waitlist')
  );

create policy "enrollments: admin 全權" on public.enrollments
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- attendance ----------
create policy "attendance: 家長可讀自己學員出席" on public.attendance
  for select to authenticated
  using (public.owns_student(student_id));

create policy "attendance: 教練可讀自己班出席" on public.attendance
  for select to authenticated
  using (public.is_coach_of_session(session_id));

create policy "attendance: 教練可點名" on public.attendance
  for insert to authenticated
  with check (
    public.is_coach_of_session(session_id)
    and public.is_coach_of_student(student_id)
  );

create policy "attendance: 教練可改點名" on public.attendance
  for update to authenticated
  using (public.is_coach_of_session(session_id))
  with check (public.is_coach_of_session(session_id));

create policy "attendance: admin 全權" on public.attendance
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- products / product_variants ----------
create policy "products: 公開讀取上架商品" on public.products
  for select to anon, authenticated
  using (is_active);

create policy "products: admin 全權" on public.products
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "product_variants: 公開讀取" on public.product_variants
  for select to anon, authenticated
  using (
    exists (
      select 1 from public.products p
      where p.id = product_id and p.is_active
    )
  );

create policy "product_variants: admin 全權" on public.product_variants
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- orders / order_items ----------
-- 下單（計價、扣積分）會喺第 5 階段用 RPC 做，所以會員冇直接 insert 權
create policy "orders: 會員可讀自己訂單" on public.orders
  for select to authenticated
  using (profile_id = (select auth.uid()));

-- 會員只可以喺待付款時上載付款截圖；改其他欄位由 guard trigger 擋
create policy "orders: 會員可上載付款截圖" on public.orders
  for update to authenticated
  using (profile_id = (select auth.uid()) and status = 'pending_payment')
  with check (profile_id = (select auth.uid()) and status = 'pending_payment');

create policy "orders: admin 全權" on public.orders
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "order_items: 會員可讀自己訂單明細" on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_id and o.profile_id = (select auth.uid())
    )
  );

create policy "order_items: admin 全權" on public.order_items
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- custom_requests ----------
-- 訪客同會員都可以提交，但唔可以自己填報價或狀態
create policy "custom_requests: 任何人可提交" on public.custom_requests
  for insert to anon, authenticated
  with check (
    status = 'submitted'
    and quote_amount is null
    and quote_note is null
    and (profile_id is null or profile_id = (select auth.uid()))
  );

create policy "custom_requests: 會員可讀自己查詢" on public.custom_requests
  for select to authenticated
  using (profile_id = (select auth.uid()));

create policy "custom_requests: admin 全權" on public.custom_requests
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- points_ledger ----------
-- 自動加分由 security definer trigger 寫入；手動調整只限 admin
create policy "points_ledger: 會員可讀自己積分" on public.points_ledger
  for select to authenticated
  using (profile_id = (select auth.uid()));

create policy "points_ledger: admin 全權" on public.points_ledger
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- site_settings ----------
-- WhatsApp 號碼、FPS 資料、積分規則全部都係前台要顯示嘅公開資料
create policy "site_settings: 公開讀取" on public.site_settings
  for select to anon, authenticated
  using (true);

create policy "site_settings: admin 全權" on public.site_settings
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------- 剩餘名額（公開） ----------
-- anon 睇唔到 enrollments，所以用 security definer function 只回傳數字
create or replace function public.class_availability()
returns table (class_id uuid, capacity integer, taken integer, remaining integer, waitlist integer)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id,
    c.capacity,
    count(e.id) filter (where e.status in ('pending', 'confirmed'))::integer,
    greatest(c.capacity - count(e.id) filter (where e.status in ('pending', 'confirmed')), 0)::integer,
    count(e.id) filter (where e.status = 'waitlist')::integer
  from public.classes c
  left join public.enrollments e on e.class_id = c.id
  group by c.id, c.capacity;
$$;

grant execute on function public.class_availability() to anon, authenticated;
