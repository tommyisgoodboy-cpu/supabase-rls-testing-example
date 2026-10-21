-- 示範站：商店訂單網上付款（Stripe 測試模式 / 模擬付款成功）。
-- 只喺 site_settings.site.demo_mode = true 先生效；正式客戶版會改用 service role + webhook 驗簽。

alter table public.orders
  add column if not exists payment_method text,
  add column if not exists payment_ref text,
  add column if not exists paid_at timestamptz;

-- 守衛：會員一般唔可以改訂單狀態；示範付款 RPC 會喺同一個交易內設定 app.demo_payment = '1' 先放行
create or replace function public.trg_orders_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and not public.is_admin() and coalesce(current_setting('app.demo_payment', true), '') <> '1' then
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

create or replace function public.mark_order_paid_demo(p_order_id uuid, p_method text, p_ref text)
returns table (order_id uuid, status public.order_status, payment_method text)
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
  -- 模擬付款：只限訂單擁有人（或管理員）；Stripe：伺服器已向 Stripe 核實 session 先會 call
  if p_method = 'simulated' and not exists (
    select 1 from public.orders o where o.id = p_order_id and (o.profile_id = (select auth.uid()) or (select public.is_admin()))
  ) then
    raise exception using errcode = 'EB003', message = '搵唔到呢張訂單';
  end if;
  if p_method = 'stripe' and p_ref !~ '^cs_(test|live)_' then
    raise exception using errcode = 'EB003', message = '付款參考唔正確';
  end if;

  perform set_config('app.demo_payment', '1', true);
  update public.orders o
     set status = 'paid', payment_method = p_method, payment_ref = left(p_ref, 120), paid_at = now()
   where o.id = p_order_id and o.status = 'pending_payment';

  return query select o.id, o.status, o.payment_method from public.orders o where o.id = p_order_id;
end;
$$;

revoke execute on function public.mark_order_paid_demo(uuid, text, text) from public;
grant execute on function public.mark_order_paid_demo(uuid, text, text) to anon, authenticated;
