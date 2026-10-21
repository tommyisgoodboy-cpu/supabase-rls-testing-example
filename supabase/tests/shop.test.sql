-- =============================================================
-- 商店：下單、積分抵扣、付款 / 出貨 / 取消嘅庫存同積分變化、訂製報價
-- 用 seed 會員陳太 (…003，積分 170)
-- 執行：npx supabase test db
-- =============================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

create function pg_temp.login_as(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- 7 號籃球 $220（庫存 24，seed 已賣出 1）、運球眼鏡 $120（庫存 30）
create temp table v as select
  (select id from public.product_variants where product_id = '60000000-0000-0000-0000-000000000004') as ball,
  (select id from public.product_variants where product_id = '60000000-0000-0000-0000-000000000006') as goggles,
  (select stock from public.product_variants where product_id = '60000000-0000-0000-0000-000000000004') as ball_stock,
  (select id from public.custom_requests where profile_id is null limit 1) as guest_request;
create temp table o (id uuid);
grant select on v to authenticated;
grant all on o to authenticated;

set local role authenticated;
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');

select is((select balance from public.member_points_balance), 170, '開始時積分 170');

-- ---------- 下單驗證 ----------
select throws_ok(
  format($$ select public.place_order('[{"variant_id": "%s", "qty": 999}]', 0, '陳太', '5555 0003', 'pickup') $$, (select ball from v)),
  'EB003', null, '數量超過 20 被拒');
select throws_ok(
  format($$ select public.place_order('[{"variant_id": "%s", "qty": 1}]', 50, '陳太', '5555 0003', 'pickup') $$, (select ball from v)),
  'EB003', null, '積分唔係 100 嘅倍數被拒');
select throws_ok(
  format($$ select public.place_order('[{"variant_id": "%s", "qty": 1}]', 200, '陳太', '5555 0003', 'pickup') $$, (select ball from v)),
  'EB003', null, '積分多過餘額被拒');
select throws_ok(
  format($$ select public.place_order('[{"variant_id": "%s", "qty": 1}]', 0, '陳太', '5555 0003', 'delivery') $$, (select ball from v)),
  'EB003', null, '送貨冇地址被拒');
select throws_ok(
  format($$ select public.place_order('[{"variant_id": "%s", "qty": 1}]', 0, '陳太', '1234', 'pickup') $$, (select ball from v)),
  'EB003', null, '非香港電話被拒');
select throws_ok(
  $$ insert into public.orders (profile_id, total) values ('a0000000-0000-0000-0000-000000000003', 1) $$,
  '42501', null, '會員唔可以直接 insert 訂單');

-- ---------- 正常下單：籃球 x2 + 眼鏡 x1 = $560，用 100 分抵 $10 ----------
insert into o select public.place_order(
  format('[{"variant_id": "%s", "qty": 1}, {"variant_id": "%s", "qty": 1}, {"variant_id": "%s", "qty": 1}]',
         (select ball from v), (select ball from v), (select goggles from v))::jsonb,
  100, '陳太', '+852 5555-0003', 'delivery', '示範地址');

select results_eq(
  $$ select subtotal, discount, total, points_used, status::text, contact_phone from public.orders where id = (select id from o) $$,
  $$ values (560.00::numeric(10,2), 10.00::numeric(10,2), 550.00::numeric(10,2), 100, 'pending_payment', '5555 0003') $$,
  '金額由 DB 計：小計 560、折扣 10、應付 550；同款合併；電話統一格式');
select is((select sum(qty)::int from public.order_items where order_id = (select id from o)), 3, '訂單明細 3 件');
select is((select balance from public.member_points_balance), 70, '下單即扣 100 分');
select is((select stock from public.product_variants where id = (select ball from v)), (select ball_stock from v), '未付款唔扣庫存');

-- 會員只可以上載付款截圖，唔可以改狀態 / 金額
select throws_ok(
  $$ update public.orders set status = 'paid' where id = (select id from o) $$,
  'P0001', null, '會員唔可以自己改做已付款');
select lives_ok(
  $$ update public.orders set payment_proof_url = 'a0000000-0000-0000-0000-000000000003/proof.png' where id = (select id from o) $$,
  '會員可以上載付款截圖');

-- ---------- 管理員：已付款 → 已出貨 ----------
select pg_temp.login_as('a0000000-0000-0000-0000-000000000001');
update public.orders set status = 'paid' where id = (select id from o);
select is((select stock from public.product_variants where id = (select ball from v)), (select ball_stock - 2 from v), '付款後扣庫存（籃球 -2）');
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select is((select balance from public.member_points_balance), 125, '付款後加消費積分 floor(550/10) = 55');
select pg_temp.login_as('a0000000-0000-0000-0000-000000000001');
update public.orders set status = 'shipped' where id = (select id from o);
select is((select status::text from public.orders where id = (select id from o)), 'shipped', '可以改做已出貨');
select throws_ok(
  $$ update public.orders set status = 'paid' where id = (select id from o) $$,
  'EB003', null, '已出貨唔可以倒退做已付款');

-- ---------- 取消已出貨訂單：還原 ----------
update public.orders set status = 'cancelled' where id = (select id from o);
select is((select stock from public.product_variants where id = (select ball from v)), (select ball_stock from v), '取消後庫存加返');
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select is((select balance from public.member_points_balance), 170, '取消後消費積分扣返、已用積分退返，回到 170');
select pg_temp.login_as('a0000000-0000-0000-0000-000000000001');
select throws_ok(
  $$ update public.orders set status = 'pending_payment' where id = (select id from o) $$,
  'EB003', null, '已取消唔可以再改');

-- ---------- 未付款取消：退積分 ----------
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
delete from o;
insert into o select public.place_order(
  format('[{"variant_id": "%s", "qty": 1}]', (select goggles from v))::jsonb, 100, '陳太', '55550003', 'pickup');
select is((select balance from public.member_points_balance), 70, '第二張單扣 100 分');
select pg_temp.login_as('a0000000-0000-0000-0000-000000000001');
update public.orders set status = 'cancelled' where id = (select id from o);
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select is((select balance from public.member_points_balance), 170, '未付款取消退返 100 分');

-- ---------- 訂製報價 ----------
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select lives_ok(
  $$ select public.accept_custom_quote((select id from public.custom_requests where status = 'quoted' and profile_id = 'a0000000-0000-0000-0000-000000000003')) $$,
  '會員可以接受自己嘅報價');
select is((select count(*)::int from public.custom_requests where status = 'accepted'), 1, '接受後狀態變已接受');
select throws_ok(
  $$ select public.accept_custom_quote((select id from public.custom_requests where status = 'accepted' limit 1)) $$,
  'EB003', null, '唔可以重複接受');
reset role;
-- 訪客嘅查詢（profile_id null）會員攞唔到
set local role authenticated;
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select throws_ok(
  format($$ select public.accept_custom_quote('%s') $$, (select guest_request from v)),
  'EB003', null, '唔可以接受其他人嘅查詢');
select is((select count(*)::int from public.custom_requests), 1, '會員只睇到自己嘅訂製查詢');

select * from finish();
rollback;
