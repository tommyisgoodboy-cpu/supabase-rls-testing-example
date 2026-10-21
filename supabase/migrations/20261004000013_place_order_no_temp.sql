-- =============================================================
-- 13 · place_order() 改用 jsonb，唔再用臨時表
-- 行為完全一樣；臨時表會令 supabase db lint 報錯，亦唔適合連續叫多次。
-- =============================================================

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
  v_items jsonb;
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
  select jsonb_agg(jsonb_build_object('variant_id', variant_id, 'qty', qty))
  into v_items
  from (
    select (e ->> 'variant_id')::uuid as variant_id, sum((e ->> 'qty')::integer)::integer as qty
    from jsonb_array_elements(p_items) e
    group by 1
  ) merged;

  if exists (select 1 from jsonb_to_recordset(v_items) as i(variant_id uuid, qty integer) where qty is null or qty < 1 or qty > 20) then
    raise exception using errcode = 'EB003', message = '每款數量要係 1–20';
  end if;

  for v_item in
    select i.variant_id, i.qty, v.stock, p.price, p.name, p.is_active, v.size, v.color
    from jsonb_to_recordset(v_items) as i(variant_id uuid, qty integer)
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
  from jsonb_to_recordset(v_items) as i(variant_id uuid, qty integer)
  join public.product_variants v on v.id = i.variant_id
  join public.products p on p.id = v.product_id;

  if v_points > 0 then
    insert into public.points_ledger (profile_id, delta, reason, ref_type, ref_id, created_by)
    values (v_uid, -v_points, '積分抵扣：訂單 #' || upper(left(v_order::text, 8)), 'order_redeem', v_order, v_uid);
  end if;

  return v_order;
end;
$$;

