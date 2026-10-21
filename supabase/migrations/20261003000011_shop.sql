-- =============================================================
-- 11 · 商店 + 團體訂製
--   1. orders 補欄位：小計、積分折扣、聯絡人、取貨方式、地址、備註
--   2. place_order()：會員下單，價錢由 DB 計，可用積分抵扣
--   3. 訂單狀態流程：只准向前行；取消時還原庫存同積分
--   4. accept_custom_quote()：會員接受訂製報價
-- =============================================================

-- ---------- 1. orders 補欄位 ----------
alter table public.orders
  add column subtotal numeric(10, 2) not null default 0 check (subtotal >= 0),
  add column discount numeric(10, 2) not null default 0 check (discount >= 0),
  add column contact_name text,
  add column contact_phone text,
  add column delivery_method text not null default 'pickup' check (delivery_method in ('pickup', 'delivery')),
  add column address text,
  add column notes text;

comment on column public.orders.total is '應付金額 = subtotal - discount';
comment on column public.orders.payment_proof_url is 'payment-proofs bucket 入面嘅檔案路徑（private，後台用 signed URL 睇）';

create trigger orders_normalize_phone
  before insert or update of contact_phone on public.orders
  for each row execute function public.trg_normalize_phone('contact_phone');

-- ---------- 2. 下單 ----------
-- p_items：[{"variant_id": "...", "qty": 2}, ...]
-- 自訂錯誤碼：EB003 資料錯誤、EB004 庫存不足 / 商品已下架
create or replace function public.place_order(
  p_items           jsonb,
  p_points          integer,
  p_contact_name    text,
  p_contact_phone   text,
  p_delivery_method text,
  p_address         text default null,
  p_notes           text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_item record;
  v_subtotal numeric(10, 2) := 0;
  v_points integer := coalesce(p_points, 0);
  v_redeem_points integer := public.points_rule('redeem_points', 100);
  v_redeem_value integer := public.points_rule('redeem_value', 10);
  v_balance integer;
  v_discount numeric(10, 2) := 0;
  v_order uuid;
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = '請先登入';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception using errcode = 'EB003', message = '購物車係空嘅';
  end if;
  if jsonb_array_length(p_items) > 30 then
    raise exception using errcode = 'EB003', message = '一張訂單最多 30 款商品';
  end if;

  if nullif(btrim(p_contact_name), '') is null or length(p_contact_name) > 100 then
    raise exception using errcode = 'EB003', message = '請填寫聯絡人姓名';
  end if;
  if p_delivery_method not in ('pickup', 'delivery') then
    raise exception using errcode = 'EB003', message = '請揀取貨方式';
  end if;
  if p_delivery_method = 'delivery' and (nullif(btrim(p_address), '') is null or length(p_address) > 300) then
    raise exception using errcode = 'EB003', message = '送貨請填寫地址';
  end if;
  if length(coalesce(p_notes, '')) > 500 then
    raise exception using errcode = 'EB003', message = '備註太長';
  end if;

  -- 同一款式合併數量；檢查上架同庫存（真正扣庫存喺付款後）
  -- 同一個 transaction 入面可能叫多次（例如測試），先清走上次嘅
  drop table if exists pg_temp._items;
  create temp table _items on commit drop as
  select (e ->> 'variant_id')::uuid as variant_id, sum((e ->> 'qty')::integer)::integer as qty
  from jsonb_array_elements(p_items) e
  group by 1;

  if exists (select 1 from _items where qty is null or qty < 1 or qty > 20) then
    raise exception using errcode = 'EB003', message = '每款數量要係 1–20';
  end if;

  for v_item in
    select i.variant_id, i.qty, v.stock, p.price, p.name, p.is_active, v.size, v.color
    from _items i
    left join public.product_variants v on v.id = i.variant_id
    left join public.products p on p.id = v.product_id
  loop
    if v_item.price is null or not v_item.is_active then
      raise exception using errcode = 'EB004', message = '有商品已經下架，請返回購物車更新';
    end if;
    if v_item.stock < v_item.qty then
      raise exception using errcode = 'EB004',
        message = format('「%s %s」庫存不足（尚餘 %s 件）', v_item.name, concat_ws(' / ', v_item.size, v_item.color), v_item.stock);
    end if;
    v_subtotal := v_subtotal + v_item.price * v_item.qty;
  end loop;

  -- 積分抵扣：redeem_points 分 = $redeem_value
  if v_points < 0 or v_points % v_redeem_points <> 0 then
    raise exception using errcode = 'EB003', message = format('積分要以 %s 分為單位使用', v_redeem_points);
  end if;
  if v_points > 0 then
    select coalesce(sum(delta), 0) into v_balance from public.points_ledger where profile_id = v_uid;
    if v_points > v_balance then
      raise exception using errcode = 'EB003', message = '積分餘額唔夠';
    end if;
    v_discount := (v_points / v_redeem_points) * v_redeem_value;
    if v_discount > v_subtotal then
      raise exception using errcode = 'EB003', message = '積分折扣唔可以多過貨款';
    end if;
  end if;

  insert into public.orders (
    profile_id, subtotal, discount, total, points_used, status,
    contact_name, contact_phone, delivery_method, address, notes
  ) values (
    v_uid, v_subtotal, v_discount, v_subtotal - v_discount, v_points, 'pending_payment',
    btrim(p_contact_name), p_contact_phone, p_delivery_method,
    case when p_delivery_method = 'delivery' then btrim(p_address) end,
    nullif(btrim(p_notes), '')
  )
  returning id into v_order;

  insert into public.order_items (order_id, variant_id, qty, unit_price)
  select v_order, i.variant_id, i.qty, p.price
  from _items i
  join public.product_variants v on v.id = i.variant_id
  join public.products p on p.id = v.product_id;

  if v_points > 0 then
    insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id, created_by)
    values (v_uid, -v_points, '積分抵扣：訂單 #' || upper(left(v_order::text, 8)), 'order_redeem', v_order, v_uid);
  end if;

  return v_order;
end;
$$;

revoke execute on function public.place_order(jsonb, integer, text, text, text, text, text) from public, anon;
grant execute on function public.place_order(jsonb, integer, text, text, text, text, text) to authenticated;

-- ---------- 3. 訂單狀態流程 ----------
-- 待付款 → 已付款 / 已取消；已付款 → 已出貨 / 已取消；已出貨 → 已取消；已取消唔可以再改
create or replace function public.trg_orders_status_flow()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = old.status then
    return new;
  end if;
  if not (
    (old.status = 'pending_payment' and new.status in ('paid', 'cancelled'))
    or (old.status = 'paid' and new.status in ('shipped', 'cancelled'))
    or (old.status = 'shipped' and new.status = 'cancelled')
  ) then
    raise exception using errcode = 'EB003', message = '訂單狀態唔可以咁改';
  end if;
  return new;
end;
$$;

revoke execute on function public.trg_orders_status_flow() from public, anon, authenticated;

create trigger orders_status_flow
  before update of status on public.orders
  for each row execute function public.trg_orders_status_flow();

-- 取消：已付款 / 已出貨嘅退返庫存、扣返消費積分；用咗嘅積分退返
create or replace function public.trg_orders_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_earned integer;
  v_ref text := upper(left(new.id::text, 8));
begin
  if new.status <> 'cancelled' or old.status = 'cancelled' then
    return new;
  end if;

  if old.status in ('paid', 'shipped') then
    update public.product_variants v
    set stock = v.stock + i.qty
    from public.order_items i
    where i.order_id = new.id and v.id = i.variant_id;

    select coalesce(sum(delta), 0) into v_earned
    from public.points_ledger
    where ref_type = 'order' and ref_id = new.id;
    if v_earned > 0 then
      insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id, created_by)
      values (new.profile_id, -v_earned, '取消訂單 #' || v_ref || '：扣回消費積分', 'order_cancel', new.id, auth.uid());
    end if;
  end if;

  if new.points_used > 0 then
    insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id, created_by)
    values (new.profile_id, new.points_used, '取消訂單 #' || v_ref || '：退回已用積分', 'order_refund', new.id, auth.uid());
  end if;

  return new;
end;
$$;

revoke execute on function public.trg_orders_on_cancel() from public, anon, authenticated;

create trigger orders_on_cancel
  after update of status on public.orders
  for each row execute function public.trg_orders_on_cancel();

-- ---------- 4. 接受訂製報價 ----------
create or replace function public.accept_custom_quote(p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = '請先登入';
  end if;

  update public.custom_requests
  set status = 'accepted'
  where id = p_id and profile_id = auth.uid() and status = 'quoted';

  if not found then
    raise exception using errcode = 'EB003', message = '呢張查詢未報價或者唔屬於你';
  end if;
end;
$$;

revoke execute on function public.accept_custom_quote(uuid) from public, anon;
grant execute on function public.accept_custom_quote(uuid) to authenticated;
