-- =============================================================
-- 香港電話格式：normalize_hk_phone() 同各 table 嘅 trigger
-- 執行：npx supabase test db
-- =============================================================
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

select is(public.normalize_hk_phone('91234567'), '9123 4567', '8 位數字');
select is(public.normalize_hk_phone('9123 4567'), '9123 4567', '有空格');
select is(public.normalize_hk_phone('+852 9123-4567'), '9123 4567', '+852 前綴同連字號');
select is(public.normalize_hk_phone('852 2345 6789'), '2345 6789', '852 前綴、固網號碼');
select is(public.normalize_hk_phone('12345678'), null, '1 字頭唔接受');
select is(public.normalize_hk_phone('01234567'), null, '0 字頭唔接受');
select is(public.normalize_hk_phone('9123456'), null, '7 位唔夠');
select is(public.normalize_hk_phone('912345678'), null, '9 位太多');
select is(public.normalize_hk_phone('+86 138 0013 8000'), null, '內地號碼唔接受');

-- 經訪客報名 RPC：自動統一格式
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select is(
  (select status::text from public.enroll_guest(
    (select id from public.classes where end_date >= current_date order by start_date desc limit 1),
    '測試家長', '+852 6123-4567', '', '電話測試學員', extract(year from current_date)::int - 9)),
  'pending', '訪客用 +852 格式報名成功');
reset role;
select is(
  (select parent_phone from public.enrollments e join public.students s on s.id = e.student_id where s.name = '電話測試學員'),
  '6123 4567', '儲存時統一做 XXXX XXXX');

set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select throws_ok(
  $$ select * from public.enroll_guest(
       (select id from public.classes where end_date >= current_date order by start_date desc limit 1),
       '測試家長', '1234 5678', '', '另一個學員', extract(year from current_date)::int - 9) $$,
  'EB003', null, '非香港號碼報名會被拒');
select throws_ok(
  $$ insert into public.custom_requests (team_name, contact_name, contact_phone, item_type, qty) values ('隊', '人', '12345', 'jersey', 10) $$,
  'EB003', null, '訂製查詢電話都要香港格式');
reset role;

-- 註冊：profile 電話統一格式
insert into auth.users (id, email, raw_user_meta_data) values
  ('ffffffff-0000-0000-0000-000000000001', 'phone@test.local', '{"full_name": "電話測試", "phone": "+85298765432"}');
select is((select phone from public.profiles where id = 'ffffffff-0000-0000-0000-000000000001'), '9876 5432', '註冊時 profile 電話統一格式');

select * from finish();
rollback;
