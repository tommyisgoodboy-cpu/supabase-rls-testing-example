-- =============================================================
-- 09 · 後台核心
--   1. 首次報名 +50 分（報名轉 confirmed 時，每個家長帳戶一次）
--   2. 點名後自動將該堂設為 completed
--   3. admin_list_members()：管理員睇會員登入電郵
--   4. 場地管理權限：逐個帳戶開 can_manage_venues（管理員一律可以）
-- =============================================================

-- ---------- 1. 首次報名獎勵 ----------
create or replace function public.trg_enrollments_first_enrollment_points()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid;
begin
  if new.status <> 'confirmed' or (tg_op = 'UPDATE' and old.status = 'confirmed') then
    return new;
  end if;

  select parent_id into v_parent from public.students where id = new.student_id;
  if v_parent is null then
    return new;
  end if;

  -- 每個家長帳戶只送一次（seed 嘅示範資料用 ref_type = 'enrollment'，一併計入）
  if exists (
    select 1 from public.points_ledger
    where profile_id = v_parent and ref_type in ('first_enrollment', 'enrollment') and delta > 0
  ) then
    return new;
  end if;

  insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id, created_by)
  values (v_parent, public.points_rule('first_enrollment', 50), '首次報名獎勵', 'first_enrollment', new.id, auth.uid());

  return new;
end;
$$;

revoke execute on function public.trg_enrollments_first_enrollment_points() from public, anon, authenticated;

create trigger enrollments_first_enrollment_points
  after insert or update of status on public.enrollments
  for each row execute function public.trg_enrollments_first_enrollment_points();

-- ---------- 2. 點名後完結該堂 ----------
create or replace function public.trg_attendance_complete_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.class_sessions
  set status = 'completed'
  where id = new.session_id and status = 'scheduled';
  return new;
end;
$$;

revoke execute on function public.trg_attendance_complete_session() from public, anon, authenticated;

create trigger attendance_complete_session
  after insert on public.attendance
  for each row execute function public.trg_attendance_complete_session();

-- ---------- 3. 會員列表（連電郵） ----------
-- 電郵存喺 auth.users，前台讀唔到；只有管理員可以經呢個 function 讀。
create or replace function public.admin_list_members()
returns table (
  id uuid,
  email text,
  full_name text,
  phone text,
  role public.user_role,
  can_manage_venues boolean,
  created_at timestamptz,
  students_count integer,
  points_balance integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception using errcode = '42501', message = '只有管理員可以睇會員列表';
  end if;

  return query
  select
    p.id, u.email::text, p.full_name, p.phone, p.role, p.can_manage_venues, p.created_at,
    (select count(*)::integer from public.students s where s.parent_id = p.id),
    coalesce((select sum(delta)::integer from public.points_ledger l where l.profile_id = p.id), 0)
  from public.profiles p
  join auth.users u on u.id = p.id
  order by p.created_at desc;
end;
$$;

-- ---------- 4. 場地管理權限 ----------
alter table public.profiles add column can_manage_venues boolean not null default false;
comment on column public.profiles.can_manage_venues is '可以新增 / 修改場地（管理員一律可以，其他帳戶由管理員逐個開）';

create or replace function public.can_manage_venues()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce(
    (select p.role = 'admin' or p.can_manage_venues from public.profiles p where p.id = auth.uid()),
    false
  );
end;
$$;

-- admin_list_members 用到新欄位，所以喺欄位建立後先設定權限
revoke execute on function public.admin_list_members() from public, anon;
grant execute on function public.admin_list_members() to authenticated;
revoke execute on function public.can_manage_venues() from public, anon;
grant execute on function public.can_manage_venues() to authenticated;

create policy "venues: 有場地權限可新增" on public.venues
  for insert to authenticated
  with check ((select public.can_manage_venues()));

create policy "venues: 有場地權限可修改" on public.venues
  for update to authenticated
  using ((select public.can_manage_venues()))
  with check ((select public.can_manage_venues()));

-- 刪除只限冇班次用緊嘅場地（班次 FK 係 on delete set null，刪咗會令班次冇場地）
create policy "venues: 有場地權限可刪除未使用場地" on public.venues
  for delete to authenticated
  using (
    (select public.can_manage_venues())
    and not exists (select 1 from public.classes c where c.venue_id = venues.id)
  );

-- 只有管理員可以改 role 同 can_manage_venues
create or replace function public.trg_profiles_guard_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.role is distinct from old.role or new.can_manage_venues is distinct from old.can_manage_venues)
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception '只有管理員可以更改用戶角色或權限';
  end if;
  return new;
end;
$$;
