-- =============================================================
-- RLS 測試：會員 A 睇唔到、改唔到會員 B 嘅任何資料
-- 執行：npx supabase test db
-- 全部喺 transaction 入面做，完咗 rollback，唔會留低資料。
-- =============================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(38);

-- ---------- 準備兩個會員，各自有學員、報名、出席、積分、訂單、訂製查詢 ----------
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test.local', '{"full_name": "會員A"}'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'b@test.local', '{"full_name": "會員B"}');

insert into public.students (id, parent_id, name, birth_year) values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'aaaaaaaa-0000-0000-0000-000000000001', 'A 嘅小朋友', 2016),
  ('bbbbbbbb-0000-0000-0000-0000000000b1', 'bbbbbbbb-0000-0000-0000-000000000001', 'B 嘅小朋友', 2016);

insert into public.enrollments (id, class_id, student_id, status, source)
select v.id, (select id from public.classes order by start_date desc limit 1), v.student_id, 'confirmed', 'member'
from (values
  ('aaaaaaaa-0000-0000-0000-0000000000e1'::uuid, 'aaaaaaaa-0000-0000-0000-0000000000a1'::uuid),
  ('bbbbbbbb-0000-0000-0000-0000000000e1'::uuid, 'bbbbbbbb-0000-0000-0000-0000000000b1'::uuid)
) v(id, student_id);

insert into public.attendance (session_id, student_id, status)
select (select id from public.class_sessions order by session_date limit 1), s, 'present'
from unnest(array['aaaaaaaa-0000-0000-0000-0000000000a1', 'bbbbbbbb-0000-0000-0000-0000000000b1']::uuid[]) s;

insert into public.points_ledger (profile_id, delta, reason) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 5, '測試'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 5, '測試');

insert into public.orders (id, profile_id, total) values
  ('aaaaaaaa-0000-0000-0000-0000000000f1', 'aaaaaaaa-0000-0000-0000-000000000001', 100),
  ('bbbbbbbb-0000-0000-0000-0000000000f1', 'bbbbbbbb-0000-0000-0000-000000000001', 100);

insert into public.order_items (order_id, variant_id, qty, unit_price)
select o, (select id from public.product_variants limit 1), 1, 100
from unnest(array['aaaaaaaa-0000-0000-0000-0000000000f1', 'bbbbbbbb-0000-0000-0000-0000000000f1']::uuid[]) o;

insert into public.custom_requests (profile_id, team_name, contact_name, contact_phone, item_type, qty) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'A 隊', 'A', '55550000', 'jersey', 10),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'B 隊', 'B', '55550000', 'jersey', 10);

-- ---------- 切換做會員 A ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "aaaaaaaa-0000-0000-0000-000000000001", "role": "authenticated"}', true);

-- 讀：B 嘅資料一筆都睇唔到
select is((select count(*)::int from public.profiles where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'A 睇唔到 B 嘅 profile');
select is((select count(*)::int from public.students where parent_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'A 睇唔到 B 嘅學員');
select is((select count(*)::int from public.enrollments where student_id = 'bbbbbbbb-0000-0000-0000-0000000000b1'), 0, 'A 睇唔到 B 嘅報名');
select is((select count(*)::int from public.attendance where student_id = 'bbbbbbbb-0000-0000-0000-0000000000b1'), 0, 'A 睇唔到 B 嘅出席');
select is((select count(*)::int from public.points_ledger where profile_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'A 睇唔到 B 嘅積分紀錄');
select is((select count(*)::int from public.member_points_balance where profile_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'A 睇唔到 B 嘅積分餘額');
select is((select count(*)::int from public.orders where profile_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'A 睇唔到 B 嘅訂單');
select is((select count(*)::int from public.order_items where order_id = 'bbbbbbbb-0000-0000-0000-0000000000f1'), 0, 'A 睇唔到 B 嘅訂單明細');
select is((select count(*)::int from public.custom_requests where profile_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'A 睇唔到 B 嘅訂製查詢');

-- 讀：自己嘅資料睇得到
select is((select count(*)::int from public.students), 1, 'A 只睇到自己 1 個學員');
select is((select count(*)::int from public.enrollments), 1, 'A 只睇到自己 1 個報名');
select is((select count(*)::int from public.attendance), 1, 'A 只睇到自己 1 筆出席');
select is((select count(*)::int from public.orders), 1, 'A 只睇到自己 1 張訂單');
select is((select count(*)::int from public.custom_requests), 1, 'A 只睇到自己 1 張訂製查詢');
select is((select balance from public.member_points_balance), 65, 'A 積分 = 5 + 出席 10 + 首次報名 50');

-- 寫：改唔到 / 刪唔到 B 嘅資料（RLS 令 update / delete 影響 0 行）
update public.students set name = '被改咗' where id = 'bbbbbbbb-0000-0000-0000-0000000000b1';
update public.profiles set full_name = '被改咗' where id = 'bbbbbbbb-0000-0000-0000-000000000001';
update public.orders set payment_proof_url = 'x' where id = 'bbbbbbbb-0000-0000-0000-0000000000f1';
delete from public.students where id = 'bbbbbbbb-0000-0000-0000-0000000000b1';
delete from public.points_ledger where profile_id = 'bbbbbbbb-0000-0000-0000-000000000001';

select throws_ok(
  $$ insert into public.students (parent_id, name, birth_year) values ('bbbbbbbb-0000-0000-0000-000000000001', '偷加', 2016) $$,
  '42501', null, 'A 唔可以幫 B 新增學員');
select throws_ok(
  $$ insert into public.points_ledger (profile_id, delta, reason) values ('aaaaaaaa-0000-0000-0000-000000000001', 999, '自己加分') $$,
  '42501', null, 'A 唔可以自己加積分');
select throws_ok(
  $$ insert into public.enrollments (class_id, student_id, source) select id, 'aaaaaaaa-0000-0000-0000-0000000000a1', 'member' from public.classes limit 1 $$,
  '42501', null, 'A 唔可以直接 insert 報名（要經 RPC）');
select throws_ok(
  $$ select * from public.enroll_member((select id from public.classes order by start_date desc limit 1 offset 1), 'bbbbbbbb-0000-0000-0000-0000000000b1') $$,
  'EB003', null, 'A 唔可以用 B 嘅學員報名');
select throws_ok(
  $$ update public.profiles set role = 'admin' where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'P0001', null, 'A 唔可以將自己升做 admin');

-- 技術等級：家長改唔到（靜靜地保留原值）
update public.students set level = 'elite' where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';
select is((select level::text from public.students where id = 'aaaaaaaa-0000-0000-0000-0000000000a1'), 'starter', 'A 改唔到學員技術等級');

-- ---------- 返做 superuser 確認 B 嘅資料原封不動 ----------
reset role;
select is((select name from public.students where id = 'bbbbbbbb-0000-0000-0000-0000000000b1'), 'B 嘅小朋友', 'B 嘅學員冇被改');
select is((select full_name from public.profiles where id = 'bbbbbbbb-0000-0000-0000-000000000001'), '會員B', 'B 嘅 profile 冇被改');
select is((select payment_proof_url from public.orders where id = 'bbbbbbbb-0000-0000-0000-0000000000f1'), null, 'B 嘅訂單冇被改');
select is((select count(*)::int from public.points_ledger where profile_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 3, 'B 嘅積分紀錄冇被刪（5 + 出席 + 首次報名）');

-- ---------- 認領碼：B 攞唔到 A 嘅訪客報名，除非有認領碼 ----------
insert into public.students (id, parent_id, name, birth_year) values
  ('cccccccc-0000-0000-0000-0000000000c1', null, '訪客小朋友', 2016);
insert into public.enrollments (class_id, student_id, status, source, claim_token)
select id, 'cccccccc-0000-0000-0000-0000000000c1', 'pending', 'guest', 'cccccccc-0000-0000-0000-00000000c1a1'
from public.classes order by start_date desc limit 1;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "bbbbbbbb-0000-0000-0000-000000000001", "role": "authenticated"}', true);
select is(public.claim_enrollments(array[gen_random_uuid()]), 0, '亂估認領碼認領唔到任何嘢');
select is((select count(*)::int from public.students where id = 'cccccccc-0000-0000-0000-0000000000c1'), 0, '未認領前 B 睇唔到訪客學員');
select is(public.claim_enrollments(array['cccccccc-0000-0000-0000-00000000c1a1'::uuid]), 1, '有正確認領碼可以認領');
select is((select count(*)::int from public.students where id = 'cccccccc-0000-0000-0000-0000000000c1'), 1, '認領後 B 睇到訪客學員');
select is(public.claim_enrollments(array['cccccccc-0000-0000-0000-00000000c1a1'::uuid]), 0, '認領碼用完即失效');

-- B 而家用 A 睇唔到嘅學員報名，A 睇唔到
select set_config('request.jwt.claims', '{"sub": "aaaaaaaa-0000-0000-0000-000000000001", "role": "authenticated"}', true);
select is((select count(*)::int from public.students where id = 'cccccccc-0000-0000-0000-0000000000c1'), 0, 'A 睇唔到 B 認領咗嘅學員');

-- ---------- 訪客 ----------
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select is((select count(*)::int from public.students), 0, '訪客睇唔到學員');
select is((select count(*)::int from public.enrollments), 0, '訪客睇唔到報名');
select is((select count(*)::int from public.attendance), 0, '訪客睇唔到出席');
select is((select count(*)::int from public.points_ledger), 0, '訪客睇唔到積分');
select is((select count(*)::int from public.orders), 0, '訪客睇唔到訂單');
select is((select count(*)::int from public.profiles), 0, '訪客睇唔到 profile');
select throws_ok($$ select public.claim_enrollments(array[gen_random_uuid()]) $$, '42501', null, '訪客唔可以認領');

select * from finish();
rollback;
