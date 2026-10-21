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
-- 一直開到涵蓋未來約半年，等 demo 期間課程頁都有班可以報。
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
    while v_end < current_date + 190 loop
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

-- ---------- 擴充：更多會員家長同學員（10/15 加；全部虛構） ----------
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
  now() - make_interval(days => u.days_ago), now(),
  '', '', '', '', '', '', '', ''
from (values
  ('a0000000-0000-0000-0000-000000000011'::uuid, 'li.parent@educasketball.test',    '李太',   '5555 0111', 120),
  ('a0000000-0000-0000-0000-000000000012'::uuid, 'wong.parent@educasketball.test',  '黃先生', '5555 0112', 110),
  ('a0000000-0000-0000-0000-000000000013'::uuid, 'cheung.parent@educasketball.test','張太',   '5555 0113', 100),
  ('a0000000-0000-0000-0000-000000000014'::uuid, 'ho.parent@educasketball.test',    '何先生', '5555 0114', 90),
  ('a0000000-0000-0000-0000-000000000015'::uuid, 'leung.parent@educasketball.test', '梁太',   '5555 0115', 75),
  ('a0000000-0000-0000-0000-000000000016'::uuid, 'ng.parent@educasketball.test',    '吳先生', '5555 0116', 65),
  ('a0000000-0000-0000-0000-000000000017'::uuid, 'chow.parent@educasketball.test',  '周太',   '5555 0117', 50),
  ('a0000000-0000-0000-0000-000000000018'::uuid, 'law.member@educasketball.test',   '羅小姐', '5555 0118', 45)
) as u(id, email, full_name, phone, days_ago);

insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  'email', now(), now(), now()
from auth.users u
where u.email like '%.parent@educasketball.test' or u.email like '%.member@educasketball.test';

insert into public.students (id, parent_id, name, birth_year, years_playing, level, notes) values
  ('50000000-0000-0000-0000-000000000101', 'a0000000-0000-0000-0000-000000000011', '李靖朗', extract(year from current_date)::int - 9,  2, 'foundation',   null),
  ('50000000-0000-0000-0000-000000000102', 'a0000000-0000-0000-0000-000000000011', '李靖怡', extract(year from current_date)::int - 5,  0, 'starter',      '第一次學波，有啲怕羞'),
  ('50000000-0000-0000-0000-000000000103', 'a0000000-0000-0000-0000-000000000012', '黃梓軒', extract(year from current_date)::int - 15, 4, 'elite',        '校隊後衛'),
  ('50000000-0000-0000-0000-000000000104', 'a0000000-0000-0000-0000-000000000013', '張嘉言', extract(year from current_date)::int - 10, 1, 'intermediate', null),
  ('50000000-0000-0000-0000-000000000105', 'a0000000-0000-0000-0000-000000000014', '何柏謙', extract(year from current_date)::int - 11, 2, 'foundation',   '右手投籃較準'),
  ('50000000-0000-0000-0000-000000000106', 'a0000000-0000-0000-0000-000000000015', '梁芷晴', extract(year from current_date)::int - 6,  0, 'starter',      null),
  ('50000000-0000-0000-0000-000000000107', 'a0000000-0000-0000-0000-000000000015', '梁芷柔', extract(year from current_date)::int - 9,  1, 'foundation',   null),
  ('50000000-0000-0000-0000-000000000108', 'a0000000-0000-0000-0000-000000000016', '吳俊傑', extract(year from current_date)::int - 14, 3, 'elite',        '中鋒，體能好'),
  ('50000000-0000-0000-0000-000000000109', 'a0000000-0000-0000-0000-000000000017', '周樂軒', extract(year from current_date)::int - 12, 3, 'intermediate', null),
  ('50000000-0000-0000-0000-000000000110', 'a0000000-0000-0000-0000-000000000018', '羅詠欣', extract(year from current_date)::int - 28, 1, 'foundation',   '下班後上堂');

insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone, parent_email) values
  ('40000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000101', 'confirmed', 'member', '李太',   '5555 0111', 'li.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000102', 'confirmed', 'member', '李太',   '5555 0111', 'li.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000007', '50000000-0000-0000-0000-000000000103', 'confirmed', 'member', '黃先生', '5555 0112', 'wong.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000104', 'confirmed', 'member', '張太',   '5555 0113', 'cheung.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000105', 'confirmed', 'member', '何先生', '5555 0114', 'ho.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000106', 'confirmed', 'member', '梁太',   '5555 0115', 'leung.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000107', 'confirmed', 'member', '梁太',   '5555 0115', 'leung.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000008', '50000000-0000-0000-0000-000000000108', 'confirmed', 'member', '吳先生', '5555 0116', 'ng.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000109', 'pending',   'member', '周太',   '5555 0117', 'chow.parent@educasketball.test'),
  ('40000000-0000-0000-0000-000000000009', '50000000-0000-0000-0000-000000000110', 'confirmed', 'member', '羅小姐', '5555 0118', 'law.member@educasketball.test');

-- ---------- 擴充：更多學員同報名（過往兩期 + 未來幾期；10/15 加；全部虛構） ----------
do $$
declare
  surnames text[] := array['陳','李','張','黃','何','林','吳','劉','鄭','梁','周','羅','蔡','鍾','譚','葉','曾','蕭'];
  given    text[] := array['子軒','樂瑤','浩然','心悅','俊熙','曉晴','嘉朗','芷晴','卓謙','穎欣','天佑','凱琳','逸朗','詠恩','諾軒','思穎','宇軒','梓晴','浩賢','栩嵐','恩澄','朗曦'];
  base record;
  cls record;
  term int;
  v_start date;
  v_end date;
  v_id uuid;
  v_student uuid;
  n int := 1000;
  i int;
  want_confirmed int;
  want_pending int;
  v_surname text;
  v_birth int;
begin
  -- 1. 過往兩期（已完結）：同一個班，向前推 2 期
  for base in
    select c.*, co.sessions_count from public.classes c
    join public.courses co on co.id = c.course_id
    where c.id in (select id from public.classes where id::text like '40000000-0000-0000-0000-00000000000%' and id <> '40000000-0000-0000-0000-000000000010')
  loop
    v_start := base.start_date;
    for term in 1 .. 2 loop
      v_end := v_start - 7;
      v_start := v_end - (base.sessions_count - 1) * 7;
      insert into public.classes (course_id, coach_id, venue_id, weekday, start_time, end_time, start_date, end_date, capacity)
      values (base.course_id, base.coach_id, base.venue_id, base.weekday, base.start_time, base.end_time, v_start, v_end, base.capacity);
    end loop;
  end loop;

  -- 2. 幫「過往兩期」同「未來各期」嘅班補學員（原本 9 個現行班已有報名，唔郁）
  for cls in
    select c.id, c.capacity, c.start_date, c.end_date, co.age_group, co.level
    from public.classes c
    join public.courses co on co.id = c.course_id
    where c.id::text not like '40000000-0000-0000-0000-0000000000%'
      and not exists (select 1 from public.enrollments e where e.class_id = c.id)
  loop
    if cls.end_date < current_date then
      want_confirmed := greatest(3, cls.capacity - 3 - (n % 3)); want_pending := 0;
    elsif cls.start_date <= current_date + 35 then
      want_confirmed := 2 + (n % 4); want_pending := 1 + (n % 3);
    elsif cls.start_date <= current_date + 100 then
      want_confirmed := 0; want_pending := 1 + (n % 3);
    else
      want_confirmed := 0; want_pending := n % 2;
    end if;
    for i in 1 .. (want_confirmed + want_pending) loop
      n := n + 1;
      v_surname := surnames[1 + (n * 7) % array_length(surnames, 1)];
      v_birth := extract(year from current_date)::int - case cls.age_group
        when 'kids' then 4 + n % 3 when 'primary' then 7 + n % 6 when 'secondary' then 13 + n % 5 else 20 + n % 25 end;
      insert into public.students (parent_id, name, birth_year, years_playing, level)
      values (null, v_surname || given[1 + (n * 5) % array_length(given, 1)], v_birth, n % 5, cls.level)
      returning id into v_student;
      insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone, parent_email)
      values (cls.id, v_student, case when i <= want_confirmed then 'confirmed' else 'pending' end::public.enrollment_status, 'guest',
              case when cls.age_group = 'adult' then null else v_surname || '生' end,
              '5555 ' || lpad((1000 + (n % 9000))::text, 4, '0'), 'parent' || n || '@example.test');
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

-- ---------- 擴充：更多商品（10/15 加；全部虛構） ----------
insert into public.products (id, name, description, price, category) values
  ('60000000-0000-0000-0000-000000000009', '雙面訓練背心', '雙面可穿，一面深藍一面白，分組對抗最方便。', 180, 'jersey'),
  ('60000000-0000-0000-0000-000000000010', '保暖運動外套', '防風保暖，拉鏈口袋，熱身同落場後著。', 380, 'jersey'),
  ('60000000-0000-0000-0000-000000000011', '隊徽訓練 T 恤', '純棉混紡，上堂同日常都著得。', 150, 'jersey'),
  ('60000000-0000-0000-0000-000000000012', '長款運動褲', '冬天上堂用，束腳設計，彈性腰頭。', 220, 'shorts'),
  ('60000000-0000-0000-0000-000000000013', '成人比賽籃球褲', '寬身透氣，雙層網眼，成人比賽款。', 200, 'shorts'),
  ('60000000-0000-0000-0000-000000000014', '6 號女子比賽用籃球', '標準 6 號合成皮，適合女子及初中。', 210, 'ball'),
  ('60000000-0000-0000-0000-000000000015', '迷你紀念籃球', '迷你尺寸，作紀念品或幼兒玩樂。', 60, 'ball'),
  ('60000000-0000-0000-0000-000000000016', '護膝（單隻）', '加厚海綿，保護膝蓋，跳躍落地更安心。', 110, 'training'),
  ('60000000-0000-0000-0000-000000000017', '防滑運動襪（3 對裝）', '加厚底部，防滑點設計。', 78, 'training'),
  ('60000000-0000-0000-0000-000000000018', '隊徽運動毛巾', '速乾，印有隊徽。', 68, 'training'),
  ('60000000-0000-0000-0000-000000000019', '籃球背包', '可放籃球同球鞋，防水面料。', 320, 'training'),
  ('60000000-0000-0000-0000-000000000020', '投籃姿勢輔助環', '固定手型，幫助建立正確投籃姿勢。', 98, 'training'),
  ('60000000-0000-0000-0000-000000000021', '運動頭帶（2 條裝）', '吸汗，彈性好。', 45, 'training'),
  ('60000000-0000-0000-0000-000000000022', '手腕護帶（一對）', '減少手腕壓力，適合投籃練習。', 58, 'training');

insert into public.product_variants (product_id, size, color, stock)
select p.id, s.size, p.color, s.stock
from (values
  ('60000000-0000-0000-0000-000000000009'::uuid, '深藍 / 白'),
  ('60000000-0000-0000-0000-000000000011'::uuid, '白'),
  ('60000000-0000-0000-0000-000000000012'::uuid, '黑')
) as p(id, color)
cross join (values ('童裝 M', 10), ('童裝 L', 10), ('S', 8), ('M', 12), ('L', 10), ('XL', 5)) as s(size, stock);

insert into public.product_variants (product_id, size, color, stock) values
  ('60000000-0000-0000-0000-000000000010', 'S',  '黑', 6),
  ('60000000-0000-0000-0000-000000000010', 'M',  '黑', 10),
  ('60000000-0000-0000-0000-000000000010', 'L',  '黑', 8),
  ('60000000-0000-0000-0000-000000000010', 'XL', '黑', 4),
  ('60000000-0000-0000-0000-000000000013', 'S',  '深藍', 6),
  ('60000000-0000-0000-0000-000000000013', 'M',  '深藍', 12),
  ('60000000-0000-0000-0000-000000000013', 'L',  '深藍', 10),
  ('60000000-0000-0000-0000-000000000013', 'XL', '深藍', 5),
  ('60000000-0000-0000-0000-000000000014', '6 號', '橙', 16),
  ('60000000-0000-0000-0000-000000000015', '迷你', '橙', 40),
  ('60000000-0000-0000-0000-000000000016', 'S', '黑', 14),
  ('60000000-0000-0000-0000-000000000016', 'M', '黑', 14),
  ('60000000-0000-0000-0000-000000000016', 'L', '黑', 14),
  ('60000000-0000-0000-0000-000000000017', '均碼', '白', 30),
  ('60000000-0000-0000-0000-000000000017', '均碼', '黑', 30),
  ('60000000-0000-0000-0000-000000000018', '均碼', '灰', 25),
  ('60000000-0000-0000-0000-000000000019', '均碼', '黑', 9),
  ('60000000-0000-0000-0000-000000000019', '均碼', '深藍', 7),
  ('60000000-0000-0000-0000-000000000020', '均碼', '橙', 18),
  ('60000000-0000-0000-0000-000000000021', '均碼', '黑', 30),
  ('60000000-0000-0000-0000-000000000021', '均碼', '白', 30),
  ('60000000-0000-0000-0000-000000000022', '均碼', '黑', 24);

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

-- ---------- 擴充：更多會員訂單（過去約 4 個月，各種狀態；10/15 加） ----------
-- 一律先建 pending_payment + 明細，再按最終狀態逐步轉（trigger 會扣庫存、加積分）
do $$
declare
  o record;
  it record;
  v_variant uuid;
  v_sub numeric;
begin
  for o in
    select * from (values
      ('3e91a7c2-5c7e-4e1b-8d22-3f7a9c1e5b01'::uuid, 'a0000000-0000-0000-0000-000000000011'::uuid, '李太',   '5555 0111', 118, 'pickup',   null::text, 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000001","size":"童裝 M","q":1},{"p":"60000000-0000-0000-0000-000000000005","q":1}]'::jsonb),
      ('8b2f04d6-5c7e-4e1b-8d22-3f7a9c1e5b02'::uuid, 'a0000000-0000-0000-0000-000000000012'::uuid, '黃先生', '5555 0112', 104, 'delivery', '新界元朗示範街 8 號（虛構地址）', 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000010","size":"L","q":1}]'::jsonb),
      ('c47d19e8-5c7e-4e1b-8d22-3f7a9c1e5b03'::uuid, 'a0000000-0000-0000-0000-000000000013'::uuid, '張太',   '5555 0113', 96,  'pickup',   null, 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000017","q":2},{"p":"60000000-0000-0000-0000-000000000018","q":1}]'::jsonb),
      ('1fa6b3d5-5c7e-4e1b-8d22-3f7a9c1e5b04'::uuid, 'a0000000-0000-0000-0000-000000000014'::uuid, '何先生', '5555 0114', 85,  'delivery', '新界屯門示範徑 15 號（虛構地址）', 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000012","size":"童裝 L","q":1},{"p":"60000000-0000-0000-0000-000000000016","size":"M","q":1}]'::jsonb),
      ('e03c8a71-5c7e-4e1b-8d22-3f7a9c1e5b05'::uuid, 'a0000000-0000-0000-0000-000000000015'::uuid, '梁太',   '5555 0115', 71,  'pickup',   null, 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000009","size":"童裝 M","q":1},{"p":"60000000-0000-0000-0000-000000000009","size":"童裝 L","q":1}]'::jsonb),
      ('5d2b9f04-5c7e-4e1b-8d22-3f7a9c1e5b06'::uuid, 'a0000000-0000-0000-0000-000000000016'::uuid, '吳先生', '5555 0116', 60,  'delivery', '新界天水圍示範里 6 號（虛構地址）', 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000019","size":"均碼","q":1},{"p":"60000000-0000-0000-0000-000000000004","q":1}]'::jsonb),
      ('a68e1c37-5c7e-4e1b-8d22-3f7a9c1e5b07'::uuid, 'a0000000-0000-0000-0000-000000000017'::uuid, '周太',   '5555 0117', 48,  'pickup',   null, 'cancelled',
        '[{"p":"60000000-0000-0000-0000-000000000002","size":"童裝 M","q":1}]'::jsonb),
      ('92f4d0b8-5c7e-4e1b-8d22-3f7a9c1e5b08'::uuid, 'a0000000-0000-0000-0000-000000000018'::uuid, '羅小姐', '5555 0118', 40,  'delivery', '九龍示範道 22 號（虛構地址）', 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000013","size":"M","q":1},{"p":"60000000-0000-0000-0000-000000000021","q":1},{"p":"60000000-0000-0000-0000-000000000022","q":1}]'::jsonb),
      ('0c7a5e69-5c7e-4e1b-8d22-3f7a9c1e5b09'::uuid, 'a0000000-0000-0000-0000-000000000011'::uuid, '李太',   '5555 0111', 33,  'delivery', '新界荃灣示範街 3 號（虛構地址）', 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000011","size":"童裝 M","q":2}]'::jsonb),
      ('d5b13f82-5c7e-4e1b-8d22-3f7a9c1e5b10'::uuid, 'a0000000-0000-0000-0000-000000000012'::uuid, '黃先生', '5555 0112', 25,  'pickup',   null, 'shipped',
        '[{"p":"60000000-0000-0000-0000-000000000004","q":1},{"p":"60000000-0000-0000-0000-000000000016","size":"L","q":2}]'::jsonb),
      ('4e8c7a10-5c7e-4e1b-8d22-3f7a9c1e5b11'::uuid, 'a0000000-0000-0000-0000-000000000013'::uuid, '張太',   '5555 0113', 19,  'pickup',   null, 'paid',
        '[{"p":"60000000-0000-0000-0000-000000000007","q":1},{"p":"60000000-0000-0000-0000-000000000008","size":"均碼","q":1}]'::jsonb),
      ('b9306d4f-5c7e-4e1b-8d22-3f7a9c1e5b12'::uuid, 'a0000000-0000-0000-0000-000000000015'::uuid, '梁太',   '5555 0115', 12,  'delivery', '新界沙田示範路 9 號（虛構地址）', 'paid',
        '[{"p":"60000000-0000-0000-0000-000000000005","q":1},{"p":"60000000-0000-0000-0000-000000000015","q":2}]'::jsonb),
      ('27d1f5c3-5c7e-4e1b-8d22-3f7a9c1e5b13'::uuid, 'a0000000-0000-0000-0000-000000000014'::uuid, '何先生', '5555 0114', 6,   'pickup',   null, 'pending_payment',
        '[{"p":"60000000-0000-0000-0000-000000000010","size":"M","q":1}]'::jsonb),
      ('f1a84b96-5c7e-4e1b-8d22-3f7a9c1e5b14'::uuid, 'a0000000-0000-0000-0000-000000000018'::uuid, '羅小姐', '5555 0118', 4,   'delivery', '九龍示範道 22 號（虛構地址）', 'pending_payment',
        '[{"p":"60000000-0000-0000-0000-000000000020","q":1},{"p":"60000000-0000-0000-0000-000000000018","q":1}]'::jsonb),
      ('6a0e2d7b-5c7e-4e1b-8d22-3f7a9c1e5b15'::uuid, 'a0000000-0000-0000-0000-000000000017'::uuid, '周太',   '5555 0117', 2,   'pickup',   null, 'pending_payment',
        '[{"p":"60000000-0000-0000-0000-000000000009","size":"童裝 L","q":1},{"p":"60000000-0000-0000-0000-000000000021","q":1}]'::jsonb)
    ) as t(id, profile, name, phone, days_ago, method, addr, final_status, items)
  loop
    select sum(p.price * (i ->> 'q')::int) into v_sub
    from jsonb_array_elements(o.items) i join public.products p on p.id = (i ->> 'p')::uuid;

    insert into public.orders (id, profile_id, subtotal, total, status, contact_name, contact_phone, delivery_method, address, created_at)
    values (o.id, o.profile, v_sub, v_sub, 'pending_payment', o.name, o.phone, o.method, o.addr, now() - make_interval(days => o.days_ago));

    for it in select value from jsonb_array_elements(o.items) loop
      select v.id into v_variant
      from public.product_variants v
      where v.product_id = (it.value ->> 'p')::uuid and (it.value ->> 'size' is null or v.size = it.value ->> 'size')
      order by v.color, v.size limit 1;
      insert into public.order_items (order_id, variant_id, qty, unit_price)
      select o.id, v_variant, (it.value ->> 'q')::int, p.price from public.products p where p.id = (it.value ->> 'p')::uuid;
    end loop;

    if o.final_status in ('paid', 'shipped') then update public.orders set status = 'paid' where id = o.id; end if;
    if o.final_status = 'shipped' then update public.orders set status = 'shipped' where id = o.id; end if;
    if o.final_status = 'cancelled' then update public.orders set status = 'cancelled' where id = o.id; end if;
  end loop;
end;
$$;

-- 積分紀錄日期跟返訂單日期（trigger 用 now()）
update public.points_ledger pl
set created_at = o.created_at + interval '1 day'
from public.orders o
where pl.ref_type = 'order' and pl.ref_id = o.id and o.id::text like '%-5c7e-4e1b-8d22-3f7a9c1e5b%';

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

-- ---------- 擴充：更多團體訂製查詢（涵蓋未來半年；10/15 加） ----------
insert into public.custom_requests (
  profile_id, team_name, contact_name, contact_phone, contact_email, item_type, qty,
  size_breakdown, colors, roster, due_date, notes, quote_amount, quote_note, status, created_at
) values
  (null, '晨光小學籃球隊', '林老師', '5555 2002', 'lam@example.test', 'jersey', 20,
   '{"童裝 M": 8, "童裝 L": 8, "S": 4}', '紅色主色、白色號碼',
   '[{"number": 5, "name": "CHAN"}, {"number": 9, "name": "WONG"}]',
   current_date + 120, '開學後第一個月交貨，校徽印胸前。', 3200, '包印刷號碼及校名，交貨期約 4 星期。', 'accepted', now() - interval '6 days'),
  ('a0000000-0000-0000-0000-000000000012', '街頭籃球聯賽 A 隊', '黃先生', '5555 0112', 'wong.parent@educasketball.test', 'jersey', 12,
   '{"M": 4, "L": 5, "XL": 3}', '黑金配色',
   '[{"number": 23, "name": "WONG"}, {"number": 8, "name": "KO"}]',
   current_date + 75, '聯賽開季前要齊，字體想要粗體。', 1980, '雙面可穿款，包隊名同號碼。', 'in_production', now() - interval '25 days'),
  (null, '明德中學老師隊', '張老師', '5555 2003', 'cheung@example.test', 'warmup', 10,
   '{"M": 4, "L": 4, "XL": 2}', '灰色 + 深藍',
   '[]', current_date - 10, '運動會當日要用。', 1500, '已完成交貨。', 'completed', now() - interval '55 days'),
  (null, '何生私人訂製', '何先生', '5555 2004', null, 'other', 3,
   '{"均碼": 3}', '白色',
   '[]', current_date + 30, '想要印公司 logo 嘅毛巾。', null, null, 'cancelled', now() - interval '18 days');

-- ---------- 擴充：更多技術徽章 ----------
insert into public.student_badges (student_id, badge_key, note, awarded_by, created_at) values
  ('50000000-0000-0000-0000-000000000101', 'dribble',    '運球時開始抬頭', 'a0000000-0000-0000-0000-000000000002', now() - interval '20 days'),
  ('50000000-0000-0000-0000-000000000101', 'attendance', null, 'a0000000-0000-0000-0000-000000000002', now() - interval '12 days'),
  ('50000000-0000-0000-0000-000000000103', 'defense',    '防守腳步好穩', 'a0000000-0000-0000-0000-000000000002', now() - interval '30 days'),
  ('50000000-0000-0000-0000-000000000103', 'shooting',   '中距離命中率高', 'a0000000-0000-0000-0000-000000000002', now() - interval '16 days'),
  ('50000000-0000-0000-0000-000000000103', 'level_up',   '通過精英組評核', 'a0000000-0000-0000-0000-000000000002', now() - interval '9 days'),
  ('50000000-0000-0000-0000-000000000104', 'passing',    '擊地傳球準確', 'a0000000-0000-0000-0000-000000000002', now() - interval '11 days'),
  ('50000000-0000-0000-0000-000000000108', 'teamwork',   '主動指揮隊友補位', 'a0000000-0000-0000-0000-000000000002', now() - interval '14 days'),
  ('50000000-0000-0000-0000-000000000108', 'level_up',   null, 'a0000000-0000-0000-0000-000000000002', now() - interval '5 days'),
  ('50000000-0000-0000-0000-000000000110', 'dribble',    '下班後都堅持上堂', 'a0000000-0000-0000-0000-000000000002', now() - interval '8 days');

-- ---------- 擴充：學員備注（10/15 加；虛構） ----------
insert into public.student_notes (student_id, kind, body, created_by, created_at) values
  ('50000000-0000-0000-0000-000000000001', 'health',   '左手手腕輕微拉傷，兩星期內避免大力運球。', 'a0000000-0000-0000-0000-000000000002', now() - interval '3 days'),
  ('50000000-0000-0000-0000-000000000002', 'schedule', '逢星期五 19:00 要補習，請準時完堂。', 'a0000000-0000-0000-0000-000000000001', now() - interval '12 days'),
  ('50000000-0000-0000-0000-000000000102', 'general',  '比較怕羞，分組時可以安排同熟人一組。', 'a0000000-0000-0000-0000-000000000002', now() - interval '9 days'),
  ('50000000-0000-0000-0000-000000000103', 'health',   '膝蓋有舊患，跳躍動作量力而為。', 'a0000000-0000-0000-0000-000000000001', now() - interval '20 days'),
  ('50000000-0000-0000-0000-000000000103', 'schedule', '逢星期二要 20:30 前離開（補習）。', 'a0000000-0000-0000-0000-000000000001', now() - interval '6 days'),
  ('50000000-0000-0000-0000-000000000105', 'general',  '正準備校隊選拔，想多練罰球。', 'a0000000-0000-0000-0000-000000000002', now() - interval '15 days'),
  ('50000000-0000-0000-0000-000000000108', 'health',   '對花生敏感，小食時間要留意。', 'a0000000-0000-0000-0000-000000000001', now() - interval '30 days'),
  ('50000000-0000-0000-0000-000000000110', 'schedule', '下班後上堂，18:45 前可能遲少少到。', 'a0000000-0000-0000-0000-000000000001', now() - interval '4 days');

-- ---------- 擴充：付款狀態（示範；10/15 加） ----------
update public.enrollments e
   set payment_status = 'paid',
       payment_method = case when mod(abs(hashtext(e.id::text)), 3) = 0 then 'stripe' else 'simulated' end,
       payment_ref = 'DEMO-SEED-' || left(e.id::text, 8),
       paid_at = e.created_at + interval '1 day'
 where e.status = 'confirmed'
   and (mod(abs(hashtext(e.id::text)), 10) < 8 or e.student_id in ('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002'));

update public.orders o
   set payment_method = case when mod(abs(hashtext(o.id::text)), 2) = 0 then 'stripe' else 'simulated' end,
       payment_ref = 'DEMO-SEED-' || left(o.id::text, 8),
       paid_at = o.created_at + interval '1 day'
 where o.status in ('paid', 'shipped');
