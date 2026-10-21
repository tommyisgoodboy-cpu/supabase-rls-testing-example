-- =============================================================
-- 技術徽章權限
-- 執行：npx supabase test db
-- =============================================================
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create function pg_temp.login_as(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- 預先（以 superuser）揀一個唔係陳志朗教嘅學員
create temp table other as
select s.id from public.students s
join public.enrollments e on e.student_id = s.id
join public.classes c on c.id = e.class_id
where c.coach_id <> '20000000-0000-0000-0000-000000000001'
  and s.id not in (
    select e2.student_id from public.enrollments e2 join public.classes c2 on c2.id = e2.class_id
    where c2.coach_id = '20000000-0000-0000-0000-000000000001')
limit 1;
grant select on other to authenticated;

set local role authenticated;

-- 家長睇到自己學員嘅 4 個徽章
select pg_temp.login_as('a0000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.student_badges), 4, '家長睇到自己學員嘅徽章');
select throws_ok(
  $$ insert into public.student_badges (student_id, badge_key, awarded_by) values ('50000000-0000-0000-0000-000000000001', 'shooting', 'a0000000-0000-0000-0000-000000000003') $$,
  '42501', null, '家長唔可以自己頒徽章');

-- 教練（陳志朗教陳小晴）可以頒發；唔可以頒畀唔係自己班嘅學員
select pg_temp.login_as('a0000000-0000-0000-0000-000000000002');
select lives_ok(
  $$ insert into public.student_badges (student_id, badge_key, awarded_by) values ('50000000-0000-0000-0000-000000000001', 'shooting', 'a0000000-0000-0000-0000-000000000002') $$,
  '教練可以頒徽章畀自己班學員');
select throws_ok(
  $$ insert into public.student_badges (student_id, badge_key, awarded_by)
     values ((select id from other), 'shooting', 'a0000000-0000-0000-0000-000000000002') $$,
  '42501', null, '教練唔可以頒畀其他班學員');
select throws_ok(
  $$ insert into public.student_badges (student_id, badge_key, awarded_by) values ('50000000-0000-0000-0000-000000000001', 'flying', 'a0000000-0000-0000-0000-000000000002') $$,
  '23514', null, '唔存在嘅徽章種類被拒');
select throws_ok(
  $$ insert into public.student_badges (student_id, badge_key, awarded_by) values ('50000000-0000-0000-0000-000000000001', 'shooting', 'a0000000-0000-0000-0000-000000000002') $$,
  '23505', null, '同一種徽章唔可以重複頒');

-- 訪客睇唔到
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select is((select count(*)::int from public.student_badges), 0, '訪客睇唔到徽章');

select * from finish();
rollback;
