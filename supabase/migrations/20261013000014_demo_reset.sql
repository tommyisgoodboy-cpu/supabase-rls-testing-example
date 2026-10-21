-- 公開示範沙盒：每晚將示範資料還原成 seed（日期按「執行當日」重新計）。
-- seed 文本存喺 demo_admin.seed_sql，reset() 直接執行；唔經 API 暴露（demo_admin 唔喺 exposed schemas）。
create schema if not exists demo_admin;
revoke all on schema demo_admin from public, anon, authenticated;

create table if not exists demo_admin.seed_sql (
  id  int primary key,
  sql text not null
);
revoke all on demo_admin.seed_sql from public, anon, authenticated;

insert into demo_admin.seed_sql (id, sql) values (1, $seed$-- 還原前先清走所有示範資料（公開沙盒：訪客做咗乜都會喺每晚被清走）
truncate table
  public.student_badges, public.custom_requests, public.order_items, public.orders, public.points_ledger,
  public.attendance, public.enrollments, public.class_sessions, public.classes, public.students,
  public.product_variants, public.products, public.courses, public.coaches, public.venues, public.site_settings
  restart identity cascade;
delete from auth.users; -- profiles 跟住 cascade 清走（包括訪客自己註冊嘅帳戶）

-- =============================================================
-- Educasketball demo seed data
-- 全部資料均屬虛構：人名、場地、電話、地址都唔對應任何真實人物或地方。
-- 課程日期以「執行 seed 當日」計算，每次 db reset 都會有已上堂 + 未上堂。
--
-- 測試帳戶（密碼一律 Demo1234!）
--   admin@educasketball.test   管理員
--   coach@educasketball.test   教練（陳志朗）
--   member@educasketball.test  會員家長（陳太，有 2 個學員）
-- =============================================================

-- ---------- 測試帳戶 ----------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, email_change_token_current,
  recovery_token, phone_change, phone_change_token, reauthentication_token
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
  extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', u.full_name, 'phone', u.phone),
  now(), now(),
  '', '', '', '', '', '', '', ''
from (values
  ('a0000000-0000-0000-0000-000000000001'::uuid, 'admin@educasketball.test',  'Demo 管理員', '5555 0001'),
  ('a0000000-0000-0000-0000-000000000002'::uuid, 'coach@educasketball.test',  '陳志朗',      '5555 0002'),
  ('a0000000-0000-0000-0000-000000000003'::uuid, 'member@educasketball.test', '陳太',        '5555 0003')
) as u(id, email, full_name, phone);

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', now(), now(), now()
from auth.users u
where u.email like '%@educasketball.test';

-- profiles 已由 on_auth_user_created trigger 建立，呢度只改 role
update public.profiles set role = 'admin' where id = 'a0000000-0000-0000-0000-000000000001';
update public.profiles set role = 'coach' where id = 'a0000000-0000-0000-0000-000000000002';

-- ---------- 網站設定 ----------
insert into public.site_settings (key, value) values
  ('whatsapp', '{"number": "85255550000", "display": "+852 5555 0000", "default_message": "你好，我想查詢 Educasketball 課程"}'),
  ('fps', '{"fps_id": "1234567", "account_name": "Educasketball Demo", "instructions": "轉數後請喺訂單頁上載付款截圖，我哋會喺 1 個工作天內確認。"}'),
  ('points_rules', '{"attendance": 10, "spend_per_point": 10, "first_enrollment": 50, "referral": 100, "redeem_points": 100, "redeem_value": 10}'),
  ('site', '{"brand": "Educasketball", "phone": "+852 5555 0000", "email": "hello@educasketball.test", "demo_mode": true}');

-- ---------- 場地（虛構） ----------
insert into public.venues (id, name, district, address, map_url) values
  ('10000000-0000-0000-0000-000000000001', '天水圍訓練中心', '天水圍', '新界天水圍示範路 1 號體育館 2 樓（虛構地址）', null),
  ('10000000-0000-0000-0000-000000000002', '元朗訓練中心',   '元朗',   '新界元朗示範街 8 號體育館地下（虛構地址）', null),
  ('10000000-0000-0000-0000-000000000003', '屯門訓練中心',   '屯門',   '新界屯門示範道 28 號體育館 1 樓（虛構地址）', null);

-- ---------- 教練（虛構） ----------
insert into public.coaches (id, profile_id, name, bio, photo_url, certifications) values
  ('20000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000002', '陳志朗',
   '前大專籃球隊隊長，專注小學及中學梯隊訓練，擅長將技術拆細做循序漸進嘅練習。', null,
   array['籃球總會二級教練（示範）', '急救證書']),
  ('20000000-0000-0000-0000-000000000002', null, '黃靜雯',
   '幼兒體適能背景，用遊戲帶入運球同協調訓練，令小朋友由第一堂開始愛上籃球。', null,
   array['籃球總會一級教練（示範）', '幼兒體適能導師證書']),
  ('20000000-0000-0000-0000-000000000003', null, '李浩賢',
   '專攻戰術同體能，帶領中學校隊備戰校際比賽，重視數據化追蹤學員進度。', null,
   array['籃球總會二級教練（示範）', '體能訓練認證']),
  ('20000000-0000-0000-0000-000000000004', null, '馮嘉敏',
   '負責幼兒及成人課程，教學有耐性，擅長由零開始建立正確投籃姿勢。', null,
   array['籃球總會一級教練（示範）', '急救證書']);

-- ---------- 課程 ----------
insert into public.courses (id, title, age_group, level, description, price, sessions_count) values
  ('30000000-0000-0000-0000-000000000001', '幼兒啟蒙班', 'kids', 'starter',
   '4–6 歲。以遊戲形式訓練手眼協調、基本運球同傳接球，建立對籃球嘅興趣。', 1280, 8),
  ('30000000-0000-0000-0000-000000000002', '小學基礎班', 'primary', 'foundation',
   '7–12 歲初學者。系統學習運球、傳球、上籃同投籃姿勢，每期設技術評核。', 1680, 10),
  ('30000000-0000-0000-0000-000000000003', '小學進階班', 'primary', 'intermediate',
   '已完成基礎班或有一年以上球齡。加入攻防概念、二打一同比賽應用。', 1880, 10),
  ('30000000-0000-0000-0000-000000000004', '中學校隊訓練班', 'secondary', 'elite',
   '13–17 歲。針對校際比賽嘅戰術、體能同心理質素訓練。', 2280, 12),
  ('30000000-0000-0000-0000-000000000005', '成人班', 'adult', 'foundation',
   '18 歲以上。由基本功重新打好根基，下班後輕鬆練波。', 1480, 8),
  ('30000000-0000-0000-0000-000000000006', '暑期訓練營', 'primary', 'foundation',
   '7–12 歲。暑假密集訓練，一個暑假完成一個等級嘅技術評核。', 1500, 5);

-- ---------- 班次 ----------
-- start_date = 本週一 + week_offset 週 + (weekday - 1) 日；end_date 按課程堂數推算
insert into public.classes (id, course_id, coach_id, venue_id, weekday, start_time, end_time, start_date, end_date, capacity)
select
  v.id, v.course_id, v.coach_id, v.venue_id, v.weekday, v.start_time, v.end_time,
  date_trunc('week', current_date)::date + v.week_offset * 7 + (v.weekday - 1),
  date_trunc('week', current_date)::date + v.week_offset * 7 + (v.weekday - 1) + (c.sessions_count - 1) * 7,
  v.capacity
from (values
  -- id, course, coach, venue, weekday, start, end, week_offset, capacity
  ('40000000-0000-0000-0000-000000000001'::uuid, '30000000-0000-0000-0000-000000000001'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 6, '10:00'::time, '11:00'::time, -4, 12),
  ('40000000-0000-0000-0000-000000000002'::uuid, '30000000-0000-0000-0000-000000000001'::uuid, '20000000-0000-0000-0000-000000000004'::uuid, '10000000-0000-0000-0000-000000000002'::uuid, 7, '10:00'::time, '11:00'::time, -3,  8),
  ('40000000-0000-0000-0000-000000000003'::uuid, '30000000-0000-0000-0000-000000000002'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 6, '11:30'::time, '13:00'::time, -4, 16),
  ('40000000-0000-0000-0000-000000000004'::uuid, '30000000-0000-0000-0000-000000000002'::uuid, '20000000-0000-0000-0000-000000000003'::uuid, '10000000-0000-0000-0000-000000000003'::uuid, 3, '17:00'::time, '18:30'::time, -2, 16),
  ('40000000-0000-0000-0000-000000000005'::uuid, '30000000-0000-0000-0000-000000000003'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000002'::uuid, 7, '14:00'::time, '15:30'::time, -4, 14),
  ('40000000-0000-0000-0000-000000000006'::uuid, '30000000-0000-0000-0000-000000000003'::uuid, '20000000-0000-0000-0000-000000000003'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 5, '17:30'::time, '19:00'::time, -1,  6),
  ('40000000-0000-0000-0000-000000000007'::uuid, '30000000-0000-0000-0000-000000000004'::uuid, '20000000-0000-0000-0000-000000000003'::uuid, '10000000-0000-0000-0000-000000000003'::uuid, 2, '18:00'::time, '20:00'::time, -3, 20),
  ('40000000-0000-0000-0000-000000000008'::uuid, '30000000-0000-0000-0000-000000000004'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, '10000000-0000-0000-0000-000000000002'::uuid, 4, '18:00'::time, '20:00'::time, -2, 20),
  ('40000000-0000-0000-0000-000000000009'::uuid, '30000000-0000-0000-0000-000000000005'::uuid, '20000000-0000-0000-0000-000000000004'::uuid, '10000000-0000-0000-0000-000000000003'::uuid, 1, '20:00'::time, '21:30'::time,  0, 18)
) as v(id, course_id, coach_id, venue_id, weekday, start_time, end_time, week_offset, capacity)
join public.courses c on c.id = v.course_id;

-- 暑期訓練營：下一個暑假 7 月第二個星期一開始
insert into public.classes (id, course_id, coach_id, venue_id, weekday, start_time, end_time, start_date, end_date, capacity)
select
  '40000000-0000-0000-0000-000000000010', '30000000-0000-0000-0000-000000000006',
  '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
  1, '09:30', '12:30', d, d + 28, 24
from (
  select (date_trunc('week', make_date(
            extract(year from current_date)::int + case when extract(month from current_date) >= 7 then 1 else 0 end,
            7, 14))::date) as d
) s;
-- 下一期：每個常規班次喺上一期完結後一星期開新一期（同教練、場地、時間），
-- 一直開到涵蓋未來約三個月，等 demo 期間課程頁都有班可以報。
do $$
declare
  base record;
  v_start date;
  v_end date;
begin
  for base in
    select c.*, co.sessions_count
    from public.classes c
    join public.courses co on co.id = c.course_id
    where c.id <> '40000000-0000-0000-0000-000000000010'
  loop
    v_end := base.end_date;
    while v_end < current_date + 92 loop
      v_start := v_end + 7;
      v_end := v_start + (base.sessions_count - 1) * 7;
      insert into public.classes (course_id, coach_id, venue_id, weekday, start_time, end_time, start_date, end_date, capacity)
      values (base.course_id, base.coach_id, base.venue_id, base.weekday, base.start_time, base.end_time, v_start, v_end, base.capacity);
    end loop;
  end loop;
end;
$$;
-- class_sessions 已由 classes_sync_sessions trigger 自動生成

-- ---------- 會員嘅學員 ----------
insert into public.students (id, parent_id, name, birth_year, years_playing, level, notes) values
  ('50000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', '陳小晴', extract(year from current_date)::int - 9,  1, 'foundation',   '左手運球較弱'),
  ('50000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000003', '陳小朗', extract(year from current_date)::int - 12, 3, 'intermediate', null);

insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone, parent_email) values
  ('40000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000001', 'confirmed', 'member', '陳太', '5555 0003', 'member@educasketball.test'),
  ('40000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000002', 'confirmed', 'member', '陳太', '5555 0003', 'member@educasketball.test');

-- ---------- 其他學員 + 報名（訪客報名，冇連結帳戶） ----------
-- 每班先入 confirmed，再入 pending；超出名額嘅會由 trigger 自動變 waitlist。
-- 班次 2（8 位）同班次 6（6 位）刻意報爆，示範候補。
do $$
declare
  surnames text[] := array['陳','李','張','黃','何','林','吳','劉','鄭','梁','周','羅'];
  given    text[] := array['子軒','樂瑤','浩然','心悅','俊熙','曉晴','嘉朗','芷晴','卓謙','穎欣','天佑','凱琳','逸朗','詠恩'];
  t record;
  i integer;
  n integer := 0;
  v_student uuid;
  v_birth integer;
  v_surname text;
begin
  for t in
    select v.class_id, v.confirmed_n, v.pending_n, co.age_group, co.level
    from (values
      ('40000000-0000-0000-0000-000000000001'::uuid,  7, 2),
      ('40000000-0000-0000-0000-000000000002'::uuid,  9, 0),
      ('40000000-0000-0000-0000-000000000003'::uuid,  9, 1),
      ('40000000-0000-0000-0000-000000000004'::uuid,  5, 1),
      ('40000000-0000-0000-0000-000000000005'::uuid,  8, 0),
      ('40000000-0000-0000-0000-000000000006'::uuid,  8, 0),
      ('40000000-0000-0000-0000-000000000007'::uuid, 12, 0),
      ('40000000-0000-0000-0000-000000000008'::uuid, 10, 1),
      ('40000000-0000-0000-0000-000000000009'::uuid,  9, 1),
      ('40000000-0000-0000-0000-000000000010'::uuid,  0, 3)
    ) as v(class_id, confirmed_n, pending_n)
    join public.classes c on c.id = v.class_id
    join public.courses co on co.id = c.course_id
  loop
    for i in 1 .. (t.confirmed_n + t.pending_n) loop
      n := n + 1;
      v_surname := surnames[1 + (n * 7) % array_length(surnames, 1)];
      v_birth := extract(year from current_date)::int - case t.age_group
        when 'kids'      then 4 + n % 3
        when 'primary'   then 7 + n % 6
        when 'secondary' then 13 + n % 5
        else 20 + n % 25
      end;

      insert into public.students (parent_id, name, birth_year, years_playing, level)
      values (null, v_surname || given[1 + (n * 5) % array_length(given, 1)], v_birth, n % 4, t.level)
      returning id into v_student;

      insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone, parent_email)
      values (
        t.class_id, v_student,
        case when i <= t.confirmed_n then 'confirmed' else 'pending' end::public.enrollment_status,
        'guest',
        case when t.age_group = 'adult' then null else v_surname || '生' end,
        '5555 ' || lpad((1000 + n)::text, 4, '0'),
        'parent' || n || '@example.test'
      );
    end loop;
  end loop;
end;
$$;

-- ---------- 出席紀錄（已過去嘅堂） ----------
update public.class_sessions set status = 'completed' where session_date < current_date;

-- 大部分出席；按次序間中缺席 / 請假。會員學員 present 會由 trigger 自動 +10 分
insert into public.attendance (session_id, student_id, status, marked_by)
select
  s.id, e.student_id,
  case
    when e.student_id = '50000000-0000-0000-0000-000000000002'
         and s.session_date = (select min(session_date) from public.class_sessions where class_id = s.class_id) + 7
      then 'leave'
    when e.student_id in ('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002')
      then 'present'
    when (row_number() over (order by s.session_date, e.student_id)) % 11 = 0 then 'absent'
    when (row_number() over (order by s.session_date, e.student_id)) % 17 = 0 then 'leave'
    else 'present'
  end::public.attendance_status,
  coalesce(co.profile_id, 'a0000000-0000-0000-0000-000000000001')
from public.class_sessions s
join public.classes c on c.id = s.class_id
left join public.coaches co on co.id = c.coach_id
join public.enrollments e on e.class_id = s.class_id and e.status = 'confirmed'
where s.status = 'completed';

-- trigger 寫入積分時用 now()；改返做上堂當日，積分紀錄先睇落合理
update public.points_ledger pl
set created_at = (s.session_date + time '19:00') at time zone 'Asia/Hong_Kong'
from public.attendance a
join public.class_sessions s on s.id = a.session_id
where pl.ref_type = 'attendance' and pl.ref_id = a.id;

-- ---------- 積分：首次報名獎勵 ----------
-- 會員報名 confirmed 時 trigger 已經自動送咗 +50；日期改返報名嗰陣（開班前一星期）
update public.points_ledger pl
set created_at = (c.start_date - 7 + time '12:00') at time zone 'Asia/Hong_Kong'
from public.enrollments e
join public.classes c on c.id = e.class_id
where pl.ref_type = 'first_enrollment' and pl.ref_id = e.id;

-- ---------- 商品 ----------
insert into public.products (id, name, description, price, category) values
  ('60000000-0000-0000-0000-000000000001', '主場訓練球衣', '透氣速乾物料，背面可印號碼。深藍色主場版。', 280, 'jersey'),
  ('60000000-0000-0000-0000-000000000002', '作客訓練球衣', '透氣速乾物料，背面可印號碼。白色作客版。', 280, 'jersey'),
  ('60000000-0000-0000-0000-000000000003', '訓練球褲', '彈性腰頭，兩側口袋，配合訓練球衣。', 180, 'shorts'),
  ('60000000-0000-0000-0000-000000000004', '7 號比賽用籃球', '室內外通用合成皮，適合中學及成人。', 220, 'ball'),
  ('60000000-0000-0000-0000-000000000005', '5 號兒童籃球', '細碼輕身，適合 4–9 歲小朋友練習運球。', 160, 'ball'),
  ('60000000-0000-0000-0000-000000000006', '運球訓練眼鏡', '遮擋下方視線，訓練抬頭運球。', 120, 'training'),
  ('60000000-0000-0000-0000-000000000007', '敏捷訓練梯套裝', '4 米訓練梯連 6 個標誌碟，屋企都可以練步法。', 260, 'training'),
  ('60000000-0000-0000-0000-000000000008', '隊徽運動水樽', '750ml，不含 BPA。', 90, 'training');

insert into public.product_variants (product_id, size, color, stock)
select p.id, s.size, p.color, s.stock
from (values
  ('60000000-0000-0000-0000-000000000001'::uuid, '深藍'),
  ('60000000-0000-0000-0000-000000000002'::uuid, '白'),
  ('60000000-0000-0000-0000-000000000003'::uuid, '深藍')
) as p(id, color)
cross join (values ('童裝 S', 8), ('童裝 M', 12), ('童裝 L', 10), ('S', 6), ('M', 10), ('L', 8), ('XL', 4)) as s(size, stock);

insert into public.product_variants (product_id, size, color, stock) values
  ('60000000-0000-0000-0000-000000000004', '7 號', '橙', 25),
  ('60000000-0000-0000-0000-000000000005', '5 號', '橙', 18),
  ('60000000-0000-0000-0000-000000000005', '5 號', '藍', 12),
  ('60000000-0000-0000-0000-000000000006', '均碼', '黑', 30),
  ('60000000-0000-0000-0000-000000000007', '均碼', '黃', 10),
  ('60000000-0000-0000-0000-000000000008', '均碼', '深藍', 20),
  ('60000000-0000-0000-0000-000000000008', '均碼', '淺藍', 20),
  ('60000000-0000-0000-0000-000000000008', '均碼', '白', 15);

-- ---------- 會員訂單 ----------
-- 訂單 1：先建 pending_payment，再轉 paid（trigger 扣庫存 + 加積分），再轉 shipped
insert into public.orders (id, profile_id, subtotal, total, status, contact_name, contact_phone, delivery_method, address, created_at) values
  ('7a3f9c21-5b8e-4d2a-9c11-2e6f8b0d4a01', 'a0000000-0000-0000-0000-000000000003', 500, 500, 'pending_payment', '陳太', '5555 0003', 'pickup', null, now() - interval '10 days'),
  ('7c81d4e0-2f6a-4b93-8e57-1d9a3c6b5e02', 'a0000000-0000-0000-0000-000000000003', 120, 120, 'pending_payment', '陳太', '5555 0003', 'delivery', '新界天水圍示範路 18 號 3 樓 A 室（虛構地址）', now() - interval '1 day');

insert into public.order_items (order_id, variant_id, qty, unit_price)
select '7a3f9c21-5b8e-4d2a-9c11-2e6f8b0d4a01', id, 1, 280
from public.product_variants
where product_id = '60000000-0000-0000-0000-000000000001' and size = '童裝 M';

insert into public.order_items (order_id, variant_id, qty, unit_price)
select '7a3f9c21-5b8e-4d2a-9c11-2e6f8b0d4a01', id, 1, 220
from public.product_variants
where product_id = '60000000-0000-0000-0000-000000000004';

insert into public.order_items (order_id, variant_id, qty, unit_price)
select '7c81d4e0-2f6a-4b93-8e57-1d9a3c6b5e02', id, 1, 120
from public.product_variants
where product_id = '60000000-0000-0000-0000-000000000006';

update public.orders set status = 'paid'    where id = '7a3f9c21-5b8e-4d2a-9c11-2e6f8b0d4a01';
update public.orders set status = 'shipped' where id = '7a3f9c21-5b8e-4d2a-9c11-2e6f8b0d4a01';
update public.points_ledger set created_at = now() - interval '9 days'
where ref_type = 'order' and ref_id = '7a3f9c21-5b8e-4d2a-9c11-2e6f8b0d4a01';

-- ---------- 團體訂製查詢 ----------
insert into public.custom_requests (
  profile_id, team_name, contact_name, contact_phone, contact_email, item_type, qty,
  size_breakdown, colors, roster, due_date, notes, quote_amount, quote_note, status
) values
  (null, '示範中學籃球隊', '何老師', '5555 2001', 'coach@example.test', 'jersey', 15,
   '{"S": 3, "M": 6, "L": 4, "XL": 2}', '深藍主色、白色號碼',
   '[{"number": 4, "name": "HO"}, {"number": 7, "name": "LAM"}, {"number": 10, "name": "CHEUNG"}]',
   current_date + 45, '想要雙面款，校徽印左胸。', null, null, 'submitted'),
  ('a0000000-0000-0000-0000-000000000003', '晴朗街坊籃球會', '陳太', '5555 0003', 'member@educasketball.test', 'warmup', 12,
   '{"童裝 M": 4, "童裝 L": 4, "S": 2, "M": 2}', '淺藍 + 深藍拼色',
   '[]', current_date + 30, '小朋友同家長一齊著。', 2160, '包雙面印刷、號碼及隊名，交貨期約 3 星期。', 'quoted');

-- ---------- 技術徽章 ----------
insert into public.student_badges (student_id, badge_key, note, awarded_by, created_at) values
  ('50000000-0000-0000-0000-000000000001', 'dribble',    '雙手交替運球穩定', 'a0000000-0000-0000-0000-000000000002', now() - interval '14 days'),
  ('50000000-0000-0000-0000-000000000001', 'attendance', '頭四堂全勤', 'a0000000-0000-0000-0000-000000000002', now() - interval '7 days'),
  ('50000000-0000-0000-0000-000000000002', 'layup',      '左右手上籃都入', 'a0000000-0000-0000-0000-000000000002', now() - interval '10 days'),
  ('50000000-0000-0000-0000-000000000002', 'teamwork',   null, 'a0000000-0000-0000-0000-000000000002', now() - interval '3 days');
$seed$)
on conflict (id) do update set sql = excluded.sql;

create or replace function demo_admin.reset() returns void
language plpgsql security definer
set search_path = public, auth, extensions
as $fn$
begin
  execute (select sql from demo_admin.seed_sql where id = 1);
end;
$fn$;
revoke all on function demo_admin.reset() from public, anon, authenticated;
