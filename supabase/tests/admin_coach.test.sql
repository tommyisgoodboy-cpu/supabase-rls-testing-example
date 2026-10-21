-- =============================================================
-- 後台權限測試：教練點名、首次報名積分、管理員功能、場地權限
-- 用 seed 嘅測試帳戶：admin (…001)、coach 陳志朗 (…002，教小學基礎班星期六等)、member 陳太 (…003)
-- 執行：npx supabase test db
-- =============================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

-- 測試用 helper：切換身份
create function pg_temp.login_as(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- 陳小晴 (…501) 報咗陳志朗教嘅小學基礎班（班次 …003）；搵下一堂未上嘅
create temp table t as
select
  (select id from public.class_sessions
   where class_id = '40000000-0000-0000-0000-000000000003' and status = 'scheduled'
   order by session_date limit 1) as own_session,
  (select id from public.class_sessions
   where class_id = '40000000-0000-0000-0000-000000000001' and status = 'scheduled'
   order by session_date limit 1) as other_session,
  (select balance from public.member_points_balance where profile_id = 'a0000000-0000-0000-0000-000000000003') as balance_before;
grant select on t to authenticated;

-- ---------- 教練點名 ----------
set local role authenticated;
select pg_temp.login_as('a0000000-0000-0000-0000-000000000002');

select lives_ok(
  $$ insert into public.attendance (session_id, student_id, status, marked_by)
     values ((select own_session from t), '50000000-0000-0000-0000-000000000001', 'present', 'a0000000-0000-0000-0000-000000000002') $$,
  '教練可以為自己班點名');
select throws_ok(
  $$ insert into public.attendance (session_id, student_id, status)
     values ((select other_session from t), '50000000-0000-0000-0000-000000000001', 'present') $$,
  '42501', null, '教練唔可以點其他教練嘅班');
select is((select count(*)::int from public.points_ledger), 0, '教練睇唔到會員積分');
select throws_ok($$ select * from public.admin_list_members() $$, '42501', null, '教練唔可以睇會員列表');

update public.enrollments set status = 'cancelled'
where class_id = '40000000-0000-0000-0000-000000000003' and student_id = '50000000-0000-0000-0000-000000000001';

reset role;
select is(
  (select status::text from public.enrollments where class_id = '40000000-0000-0000-0000-000000000003' and student_id = '50000000-0000-0000-0000-000000000001'),
  'confirmed', '教練改唔到報名狀態');
select is(
  (select balance from public.member_points_balance where profile_id = 'a0000000-0000-0000-0000-000000000003'),
  (select balance_before + 10 from t), '點名出席後會員即時 +10 分');
select is((select status::text from public.class_sessions where id = (select own_session from t)), 'completed', '點名後該堂自動變已完成');

-- 會員睇到出席同積分（驗收標準）
set local role authenticated;
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select is(
  (select status::text from public.attendance where session_id = (select own_session from t) and student_id = '50000000-0000-0000-0000-000000000001'),
  'present', '會員區即時睇到出席');
select is(
  (select reason from public.points_ledger where ref_type = 'attendance' order by created_at desc limit 1) like '出席課堂：%',
  true, '會員區即時睇到出席積分紀錄');
select throws_ok($$ select * from public.admin_list_members() $$, '42501', null, '會員唔可以睇會員列表');

-- 教練改做缺席 → 扣返 10 分
select pg_temp.login_as('a0000000-0000-0000-0000-000000000002');
update public.attendance set status = 'absent'
where session_id = (select own_session from t) and student_id = '50000000-0000-0000-0000-000000000001';
reset role;
select is(
  (select balance from public.member_points_balance where profile_id = 'a0000000-0000-0000-0000-000000000003'),
  (select balance_before from t), '改做缺席後積分扣返');

-- ---------- 首次報名積分（只送一次） ----------
insert into auth.users (id, email, raw_user_meta_data) values
  ('dddddddd-0000-0000-0000-000000000001', 'new@test.local', '{"full_name": "新會員"}');
insert into public.students (id, parent_id, name, birth_year) values
  ('dddddddd-0000-0000-0000-0000000000a1', 'dddddddd-0000-0000-0000-000000000001', '新學員一', 2016),
  ('dddddddd-0000-0000-0000-0000000000a2', 'dddddddd-0000-0000-0000-000000000001', '新學員二', 2017);
insert into public.enrollments (class_id, student_id, status, source)
select c, s, 'pending', 'member'
from (values
  ('40000000-0000-0000-0000-000000000004'::uuid, 'dddddddd-0000-0000-0000-0000000000a1'::uuid),
  ('40000000-0000-0000-0000-000000000004'::uuid, 'dddddddd-0000-0000-0000-0000000000a2'::uuid)
) v(c, s);

select is((select count(*)::int from public.points_ledger where profile_id = 'dddddddd-0000-0000-0000-000000000001'), 0, '待確認報名未送積分');

set local role authenticated;
select pg_temp.login_as('a0000000-0000-0000-0000-000000000001');
update public.enrollments set status = 'confirmed' where student_id in ('dddddddd-0000-0000-0000-0000000000a1', 'dddddddd-0000-0000-0000-0000000000a2');
reset role;
select is(
  (select sum(delta)::int from public.points_ledger where profile_id = 'dddddddd-0000-0000-0000-000000000001' and ref_type = 'first_enrollment'),
  50, '兩個學員都確認，首次報名積分只送一次 50');

-- ---------- 管理員 ----------
set local role authenticated;
select pg_temp.login_as('a0000000-0000-0000-0000-000000000001');
select ok((select count(*) from public.admin_list_members() where email is not null) >= 4, '管理員睇到會員列表連電郵');
select lives_ok(
  $$ insert into public.points_ledger (profile_id, delta, reason, created_by)
     values ('a0000000-0000-0000-0000-000000000003', -20, '手動調整：測試', 'a0000000-0000-0000-0000-000000000001') $$,
  '管理員可以手動調整積分');

-- ---------- 場地權限 ----------
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select throws_ok(
  $$ insert into public.venues (name, district, address) values ('測試場', '測試區', '測試地址') $$,
  '42501', null, '冇權限嘅會員唔可以新增場地');
select throws_ok(
  $$ update public.profiles set can_manage_venues = true where id = 'a0000000-0000-0000-0000-000000000003' $$,
  'P0001', null, '會員唔可以自己開場地權限');

select pg_temp.login_as('a0000000-0000-0000-0000-000000000002');
update public.venues set name = '被教練改咗' where id = '10000000-0000-0000-0000-000000000001';
reset role;
select is((select name from public.venues where id = '10000000-0000-0000-0000-000000000001'), '天水圍訓練中心', '冇權限嘅教練改唔到場地');

-- 管理員幫教練開權限
set local role authenticated;
select pg_temp.login_as('a0000000-0000-0000-0000-000000000001');
update public.profiles set can_manage_venues = true where id = 'a0000000-0000-0000-0000-000000000002';

select pg_temp.login_as('a0000000-0000-0000-0000-000000000002');
select lives_ok(
  $$ insert into public.venues (id, name, district, address) values ('eeeeeeee-0000-0000-0000-000000000001', '新場地', '荃灣', '示範地址') $$,
  '有權限嘅教練可以新增場地');
update public.venues set name = '天水圍訓練中心（已更新）' where id = '10000000-0000-0000-0000-000000000001';
delete from public.venues where id = '10000000-0000-0000-0000-000000000002';  -- 有班次用緊
delete from public.venues where id = 'eeeeeeee-0000-0000-0000-000000000001';  -- 冇班次用
select throws_ok(
  $$ update public.profiles set role = 'admin' where id = 'a0000000-0000-0000-0000-000000000002' $$,
  'P0001', null, '有場地權限都唔可以將自己升做管理員');
reset role;

select is((select name from public.venues where id = '10000000-0000-0000-0000-000000000001'), '天水圍訓練中心（已更新）', '有權限嘅教練可以修改場地');
select is((select count(*)::int from public.venues where id = '10000000-0000-0000-0000-000000000002'), 1, '有班次用緊嘅場地唔可以刪');
select is((select count(*)::int from public.venues where id = 'eeeeeeee-0000-0000-0000-000000000001'), 0, '冇班次用嘅場地可以刪');
select is((select can_manage_venues from public.profiles where id = 'a0000000-0000-0000-0000-000000000003'), false, '會員權限冇被改');

select * from finish();
rollback;
