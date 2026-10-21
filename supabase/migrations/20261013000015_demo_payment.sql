-- 公開示範：報名付款（Stripe 測試模式 / 模擬成功）。
-- 呢啲 RPC 只係示範用：只喺 site_settings.site.demo_mode = true 先生效；
-- 正式客戶版會改用 service role + webhook 驗簽後先寫入，唔會俾 anon 直接 call。

alter table public.enrollments
  add column if not exists payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid')),
  add column if not exists payment_method text,
  add column if not exists payment_ref text,
  add column if not exists paid_at timestamptz;

create or replace function public.enrollment_payment_info(p_enrollment_id uuid)
returns table (
  enrollment_id uuid, status public.enrollment_status, payment_status text, paid_at timestamptz,
  course_title text, price numeric, sessions_count integer, student_name text
)
language sql stable security definer
set search_path = ''
as $$
  select e.id, e.status, e.payment_status, e.paid_at, c.title, c.price, c.sessions_count, s.name
  from public.enrollments e
  join public.classes cl on cl.id = e.class_id
  join public.courses c on c.id = cl.course_id
  join public.students s on s.id = e.student_id
  where e.id = p_enrollment_id;
$$;

create or replace function public.mark_enrollment_paid(p_enrollment_id uuid, p_method text, p_ref text)
returns table (enrollment_id uuid, status public.enrollment_status, payment_status text)
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_demo boolean := coalesce((select (value ->> 'demo_mode')::boolean from public.site_settings where key = 'site'), false);
begin
  if not v_demo then
    raise exception using errcode = 'EB004', message = '呢個動作只限示範站';
  end if;
  if p_method not in ('stripe', 'simulated') then
    raise exception using errcode = 'EB003', message = '付款方式唔正確';
  end if;

  -- 只處理「待確認」報名；候補 / 已取消唔可以俾錢確認
  update public.enrollments e
     set payment_status = 'paid', payment_method = p_method, payment_ref = left(p_ref, 120), paid_at = now(),
         status = case when e.status = 'pending' then 'confirmed'::public.enrollment_status else e.status end
   where e.id = p_enrollment_id and e.status in ('pending', 'confirmed') and e.payment_status = 'unpaid';

  return query select e.id, e.status, e.payment_status from public.enrollments e where e.id = p_enrollment_id;
end;
$$;

revoke execute on function public.enrollment_payment_info(uuid) from public;
revoke execute on function public.mark_enrollment_paid(uuid, text, text) from public;
grant execute on function public.enrollment_payment_info(uuid) to anon, authenticated;
grant execute on function public.mark_enrollment_paid(uuid, text, text) to anon, authenticated;
