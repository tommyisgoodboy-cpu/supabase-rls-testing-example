-- =============================================================
-- 04 · Functions + triggers
--   1. 新用戶註冊 → 自動建立 profile
--   2. 建立 / 修改班次 → 自動生成每堂 class_sessions
--   3. 報名 → 檢查名額，額滿自動設為 waitlist
--   4. 出席設為 present → points_ledger +10（改返缺席會扣返）
--   5. 訂單變 paid → 扣庫存、加消費積分
--   6. Guard：非 admin 唔可以改自己 role、唔可以改訂單金額 / 狀態
-- =============================================================

-- ---------- 1. 新用戶 → profile ----------
-- role 一律預設 member，唔信 user metadata 入面嘅 role
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 2. 班次 → 每堂 session ----------
-- 按 start_date ~ end_date 之間每個 weekday 生成；
-- 改日期 / 星期時，刪走唔再符合而又未點名嘅 scheduled session
create or replace function public.sync_class_sessions(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.class_sessions (class_id, session_date)
  select c.id, d::date
  from public.classes c
  cross join lateral generate_series(c.start_date, c.end_date, interval '1 day') as d
  where c.id = p_class_id
    and extract(isodow from d) = c.weekday
  on conflict (class_id, session_date) do nothing;

  delete from public.class_sessions s
  using public.classes c
  where c.id = p_class_id
    and s.class_id = c.id
    and s.status = 'scheduled'
    and (
      s.session_date < c.start_date
      or s.session_date > c.end_date
      or extract(isodow from s.session_date) <> c.weekday
    )
    and not exists (select 1 from public.attendance a where a.session_id = s.id);
end;
$$;

revoke execute on function public.sync_class_sessions(uuid) from public, anon, authenticated;

create or replace function public.trg_classes_sync_sessions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.sync_class_sessions(new.id);
  return new;
end;
$$;

create trigger classes_sync_sessions
  after insert or update of weekday, start_date, end_date on public.classes
  for each row execute function public.trg_classes_sync_sessions();

-- ---------- 3. 報名 → 名額檢查 ----------
-- pending + confirmed 都佔名額；額滿就自動轉做 waitlist。
-- 鎖住班次 row，避免兩個人同時報最後一個位。
-- （admin 之後「候補轉正」係 update，唔經呢個 trigger）
create or replace function public.trg_enrollments_check_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_capacity integer;
  v_taken integer;
begin
  if new.status not in ('pending', 'confirmed') then
    return new;
  end if;

  select capacity into v_capacity
  from public.classes
  where id = new.class_id
  for update;

  select count(*) into v_taken
  from public.enrollments
  where class_id = new.class_id
    and status in ('pending', 'confirmed');

  if v_taken >= v_capacity then
    new.status := 'waitlist';
  end if;

  return new;
end;
$$;

create trigger enrollments_check_capacity
  before insert on public.enrollments
  for each row execute function public.trg_enrollments_check_capacity();

-- ---------- 4. 出席 → 積分 ----------
create or replace function public.trg_attendance_points()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid;
  v_points integer := public.points_rule('attendance', 10);
  v_label text;
begin
  select parent_id into v_parent from public.students where id = new.student_id;
  if v_parent is null then
    return new;
  end if;

  select co.title || ' ' || to_char(s.session_date, 'YYYY-MM-DD')
  into v_label
  from public.class_sessions s
  join public.classes c on c.id = s.class_id
  join public.courses co on co.id = c.course_id
  where s.id = new.session_id;

  if new.status = 'present'
     and (tg_op = 'INSERT' or old.status is distinct from 'present') then
    insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id, created_by)
    values (v_parent, v_points, '出席課堂：' || coalesce(v_label, ''), 'attendance', new.id, new.marked_by);

  elsif tg_op = 'UPDATE'
     and old.status = 'present'
     and new.status <> 'present' then
    insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id, created_by)
    values (v_parent, -v_points, '出席更正：' || coalesce(v_label, ''), 'attendance', new.id, new.marked_by);
  end if;

  return new;
end;
$$;

create trigger attendance_points
  after insert or update of status on public.attendance
  for each row execute function public.trg_attendance_points();

-- ---------- 5. 訂單 paid → 扣庫存 + 消費積分 ----------
-- 規則：每消費 $spend_per_point 得 1 分（預設 $10 = 1 分）
create or replace function public.trg_orders_on_paid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item record;
  v_unit integer := public.points_rule('spend_per_point', 10);
  v_points integer;
begin
  if new.status <> 'paid' or old.status = 'paid' then
    return new;
  end if;

  for v_item in
    select variant_id, qty from public.order_items where order_id = new.id
  loop
    update public.product_variants
    set stock = stock - v_item.qty
    where id = v_item.variant_id
      and stock >= v_item.qty;

    if not found then
      raise exception '庫存不足（款式 %）', v_item.variant_id;
    end if;
  end loop;

  v_points := floor(new.total / greatest(v_unit, 1))::integer;
  if v_points > 0 then
    insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id)
    values (new.profile_id, v_points, '商店消費 $' || new.total::text, 'order', new.id);
  end if;

  return new;
end;
$$;

create trigger orders_on_paid
  after update of status on public.orders
  for each row execute function public.trg_orders_on_paid();

-- ---------- 6. Guards ----------
-- auth.uid() 為 null 代表 service role / seed / migration，唔使擋
create or replace function public.trg_profiles_guard_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception '只有管理員可以更改用戶角色';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_role
  before update on public.profiles
  for each row execute function public.trg_profiles_guard_role();

create or replace function public.trg_orders_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if new.total is distinct from old.total
       or new.points_used is distinct from old.points_used
       or new.profile_id is distinct from old.profile_id
       or new.status is distinct from old.status then
      raise exception '會員只可以上載付款截圖';
    end if;
  end if;
  return new;
end;
$$;

create trigger orders_guard
  before update on public.orders
  for each row execute function public.trg_orders_guard();
