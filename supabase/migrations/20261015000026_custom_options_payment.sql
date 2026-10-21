-- 團體訂製：面料 / 功能選擇 + 系統估價 + 接受報價後網上付款（Testing Payment Gate）（10/15）
-- 估價只係參考：職員喺後台確認後先發出正式報價；會員接受報價後可以直接付款。
alter table public.custom_requests
  add column if not exists fabric text,
  add column if not exists features text[] not null default '{}',
  add column if not exists estimate_amount numeric(10, 2) check (estimate_amount >= 0),
  add column if not exists payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid')),
  add column if not exists payment_method text,
  add column if not exists payment_ref text,
  add column if not exists paid_at timestamptz;

-- 示範付款：只限 demo_mode；模擬付款只限擁有人（或管理員）；Stripe 由伺服器核實 session 後先 call
create or replace function public.mark_custom_paid_demo(p_id uuid, p_method text, p_ref text)
returns table (request_id uuid, payment_status text)
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
  if p_method = 'simulated' and not exists (
    select 1 from public.custom_requests c where c.id = p_id and (c.profile_id = (select auth.uid()) or (select public.is_admin()))
  ) then
    raise exception using errcode = 'EB003', message = '搵唔到呢張訂製';
  end if;
  if p_method = 'stripe' and p_ref !~ '^cs_(test|live)_' then
    raise exception using errcode = 'EB003', message = '付款參考唔正確';
  end if;

  update public.custom_requests c
     set payment_status = 'paid', payment_method = p_method, payment_ref = left(p_ref, 120), paid_at = now()
   where c.id = p_id and c.status = 'accepted' and c.payment_status = 'unpaid';

  return query select c.id, c.payment_status from public.custom_requests c where c.id = p_id;
end;
$$;
revoke execute on function public.mark_custom_paid_demo(uuid, text, text) from public;
grant execute on function public.mark_custom_paid_demo(uuid, text, text) to anon, authenticated;
