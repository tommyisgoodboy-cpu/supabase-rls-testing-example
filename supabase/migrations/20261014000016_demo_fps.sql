-- 示範：轉數快(FPS)轉帳通知。FPS 入帳程式讀唔到，所以係「通知 → 管理員核對 → 確認」；
-- 管理員將報名確認時，如果付款方式係 fps，自動記為已付款。

drop function if exists public.enrollment_payment_info(uuid);
create function public.enrollment_payment_info(p_enrollment_id uuid)
returns table (
  enrollment_id uuid, status public.enrollment_status, payment_status text, payment_method text, paid_at timestamptz,
  course_title text, price numeric, sessions_count integer, student_name text
)
language sql stable security definer
set search_path = ''
as $$
  select e.id, e.status, e.payment_status, e.payment_method, e.paid_at, c.title, c.price, c.sessions_count, s.name
  from public.enrollments e
  join public.classes cl on cl.id = e.class_id
  join public.courses c on c.id = cl.course_id
  join public.students s on s.id = e.student_id
  where e.id = p_enrollment_id;
$$;
revoke execute on function public.enrollment_payment_info(uuid) from public;
grant execute on function public.enrollment_payment_info(uuid) to anon, authenticated;

create or replace function public.report_fps_transfer(p_enrollment_id uuid, p_ref text)
returns table (enrollment_id uuid, payment_status text, payment_method text)
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_demo boolean := coalesce((select (value ->> 'demo_mode')::boolean from public.site_settings where key = 'site'), false);
begin
  if not v_demo then
    raise exception using errcode = 'EB004', message = '呢個動作只限示範站';
  end if;
  update public.enrollments e
     set payment_method = 'fps', payment_ref = left(coalesce(nullif(btrim(p_ref), ''), 'FPS 轉帳通知'), 120)
   where e.id = p_enrollment_id and e.status = 'pending' and e.payment_status = 'unpaid';
  return query select e.id, e.payment_status, e.payment_method from public.enrollments e where e.id = p_enrollment_id;
end;
$$;
revoke execute on function public.report_fps_transfer(uuid, text) from public;
grant execute on function public.report_fps_transfer(uuid, text) to anon, authenticated;

create or replace function public.fps_confirm_marks_paid() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'confirmed' and old.status <> 'confirmed' and new.payment_method = 'fps' and new.payment_status = 'unpaid' then
    new.payment_status := 'paid';
    new.paid_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists enrollments_fps_paid on public.enrollments;
create trigger enrollments_fps_paid before update of status on public.enrollments
  for each row execute function public.fps_confirm_marks_paid();
