-- 示範資料補強（10/15）：商品相片 + 每種項目都有唔同狀態可以試。追加去 demo_admin.seed_sql，每晚 / 一鍵還原都會保留。
-- 冇 marker 先追加，可重複執行。
do $do$
declare
  v_block text := $blk$
-- [demo-states-v1] 商品相片（public/demo-shop）同唔同狀態
update public.products p set images = array['/demo-shop/' || m.f || '.webp']
from (values
  ('主場訓練球衣','p01'),('作客訓練球衣','p02'),('訓練球褲','p03'),('7 號比賽用籃球','p04'),('5 號兒童籃球','p05'),
  ('運球訓練眼鏡','p06'),('敏捷訓練梯套裝','p07'),('隊徽運動水樽','p08'),('雙面訓練背心','p09'),('保暖運動外套','p10'),
  ('隊徽訓練 T 恤','p11'),('長款運動褲','p12'),('成人比賽籃球褲','p13'),('6 號女子比賽用籃球','p14'),('迷你紀念籃球','p15'),
  ('護膝（單隻）','p16'),('防滑運動襪（3 對裝）','p17'),('隊徽運動毛巾','p18'),('籃球背包','p19'),('投籃姿勢輔助環','p20'),
  ('運動頭帶（2 條裝）','p21')
) as m(n, f) where p.name = m.n;
-- 狀態：低庫存 / 售罄 / 下架 / 未有相
update public.product_variants set stock = 2 where product_id = (select id from public.products where name = '敏捷訓練梯套裝');
update public.product_variants set stock = 0 where product_id = (select id from public.products where name = '迷你紀念籃球');
update public.products set is_active = false where name = '隊徽訓練 T 恤';
update public.products set images = '{}' where name = '手腕護帶（一對）';
-- 訂製：留一個「已報價」畀會員試「接受報價」；報課：一個已取消
update public.custom_requests set status = 'quoted' where team_name = '晴朗街坊籃球會';
update public.enrollments set status = 'cancelled' where id = (select e.id from public.enrollments e where e.status = 'pending' order by e.created_at desc limit 1);
$blk$;
begin
  -- 經 PostgREST 呼叫時有 pg_safeupdate（DELETE 一定要 WHERE），所以清用戶要寫 where true
  update demo_admin.seed_sql
     set sql = replace(sql, 'delete from auth.users;', 'delete from auth.users where true;')
   where id = 1;
  update demo_admin.seed_sql
     set sql = sql || E'\n' || v_block
   where id = 1 and position('[demo-states-v1]' in sql) = 0;
end;
$do$;
