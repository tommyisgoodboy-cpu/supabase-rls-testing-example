-- 示範資料：訂製查詢有面料 / 功能 / 估價，同唔同付款狀態（追加去 demo_admin.seed_sql，每晚 / 一鍵還原都保留）
do $do$
declare
  v_block text := $blk$
-- [demo-custom-v2]
update public.custom_requests set fabric = 'mesh', features = '{cooling,name_number,embroidery}', estimate_amount = 2300 where team_name = '晴朗街坊籃球會';
update public.custom_requests set fabric = 'standard', features = '{name_number}', estimate_amount = 3000, payment_status = 'unpaid' where team_name = '晨光小學籃球隊';
update public.custom_requests set fabric = 'stretch', features = '{reversible,name_number,uv}', estimate_amount = 2100, payment_status = 'paid', payment_method = 'simulated', payment_ref = 'DEMO-SIM-SEED', paid_at = now() - interval '5 days' where team_name = '街頭籃球聯賽 A 隊';
update public.custom_requests set fabric = 'standard', features = '{embroidery}', estimate_amount = 1400, payment_status = 'paid', payment_method = 'stripe', payment_ref = 'cs_test_seed', paid_at = now() - interval '40 days' where team_name = '明德中學老師隊';
update public.custom_requests set fabric = 'recycled', features = '{cooling,name_number}', estimate_amount = 1500 where team_name = '示範中學籃球隊';
$blk$;
begin
  update demo_admin.seed_sql
     set sql = sql || E'\n' || v_block
   where id = 1 and position('[demo-custom-v2]' in sql) = 0;
end;
$do$;
