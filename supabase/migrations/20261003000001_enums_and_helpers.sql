-- =============================================================
-- 01 · Enums + 權限 helper functions
-- helper 用 plpgsql + security definer：RLS policy 入面查 profiles / classes
-- 唔會再觸發 RLS（避免遞迴），而 plpgsql 唔會喺建立時檢查 table 存唔存在。
-- =============================================================

-- ---------- Enums ----------
create type public.user_role as enum ('member', 'coach', 'admin');

-- 幼兒 4–6、小學 7–12、中學 13–17、成人
create type public.age_group as enum ('kids', 'primary', 'secondary', 'adult');

-- 技術等級：啟蒙 → 基礎 → 進階 → 精英
create type public.skill_level as enum ('starter', 'foundation', 'intermediate', 'elite');

create type public.session_status as enum ('scheduled', 'completed', 'cancelled');

create type public.enrollment_status as enum ('pending', 'confirmed', 'waitlist', 'cancelled');

create type public.enrollment_source as enum ('guest', 'member', 'admin');

create type public.attendance_status as enum ('present', 'absent', 'leave');

create type public.product_category as enum ('jersey', 'shorts', 'ball', 'training');

create type public.order_status as enum ('pending_payment', 'paid', 'shipped', 'cancelled');

create type public.custom_item_type as enum ('jersey', 'warmup', 'other');

-- 已提交 → 已報價 → 已接受 → 製作中 → 已完成（另加已取消）
create type public.custom_request_status as enum (
  'submitted', 'quoted', 'accepted', 'in_production', 'completed', 'cancelled'
);

-- ---------- Helper functions ----------

-- 目前登入用戶嘅 role；未登入回傳 null
create or replace function public.current_user_role()
returns public.user_role
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (select p.role from public.profiles p where p.id = auth.uid());
end;
$$;

create or replace function public.is_admin()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce(
    (select p.role = 'admin' from public.profiles p where p.id = auth.uid()),
    false
  );
end;
$$;

-- 目前用戶係咪呢個班嘅負責教練
create or replace function public.is_coach_of_class(p_class_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1
    from public.classes c
    join public.coaches co on co.id = c.coach_id
    where c.id = p_class_id
      and co.profile_id = auth.uid()
  );
end;
$$;

-- 目前用戶係咪呢一堂所屬班嘅教練
create or replace function public.is_coach_of_session(p_session_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1
    from public.class_sessions s
    join public.classes c on c.id = s.class_id
    join public.coaches co on co.id = c.coach_id
    where s.id = p_session_id
      and co.profile_id = auth.uid()
  );
end;
$$;

-- 目前用戶（教練）有冇教呢個學員（有效報名）
create or replace function public.is_coach_of_student(p_student_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1
    from public.enrollments e
    join public.classes c on c.id = e.class_id
    join public.coaches co on co.id = c.coach_id
    where e.student_id = p_student_id
      and e.status <> 'cancelled'
      and co.profile_id = auth.uid()
  );
end;
$$;

-- 目前用戶係咪呢個學員嘅家長
create or replace function public.owns_student(p_student_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1 from public.students s
    where s.id = p_student_id
      and s.parent_id = auth.uid()
  );
end;
$$;

-- 由 site_settings.points_rules 讀積分規則，冇設定就用預設值
create or replace function public.points_rule(p_key text, p_default integer)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v integer;
begin
  select (value ->> p_key)::integer into v
  from public.site_settings
  where key = 'points_rules';
  return coalesce(v, p_default);
end;
$$;
