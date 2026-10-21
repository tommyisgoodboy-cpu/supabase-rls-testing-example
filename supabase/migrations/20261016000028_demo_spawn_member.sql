-- 每位訪客獨立試玩家長帳戶（10/16）：撳「試玩家長會員區」就建一個臨時帳戶 + 一套私人示範資料
-- （2 個學員、1 個待確認報名、1 張已報價訂製），多人同時試玩互不干擾。夜間還原會連同清走。
-- 只限示範資料庫；anon 可 call，所以有上限同自動清理。
create or replace function public.demo_spawn_member()
returns text
language plpgsql volatile security definer
set search_path = public, auth, extensions
as $$
declare
  v_demo boolean := coalesce((select (value ->> 'demo_mode')::boolean from public.site_settings where key = 'site'), false);
  v_id uuid := gen_random_uuid();
  v_tag text := substr(replace(v_id::text, '-', ''), 1, 8);
  v_email text := 'demo-' || v_tag || '@educasketball.test';
  v_class uuid;
  v_s1 uuid := gen_random_uuid();
  v_s2 uuid := gen_random_uuid();
begin
  if not v_demo then raise exception using errcode = 'EB004', message = '呢個動作只限示範站'; end if;

  -- 清走超過 1 日嘅臨時帳戶；仲多過 400 個就拒絕（防濫用）
  delete from auth.users where email like 'demo-%@educasketball.test' and created_at < now() - interval '1 day';
  if (select count(*) from auth.users where email like 'demo-%@educasketball.test') > 400 then
    raise exception using errcode = 'EB003', message = '試玩人數太多，請稍後再試';
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, email_change_token_current, recovery_token, phone_change, phone_change_token, reauthentication_token)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt('Demo1234!', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', '試玩家長 ' || upper(substr(v_tag, 1, 4)), 'phone', '5558 ' || lpad((floor(random() * 10000))::int::text, 4, '0')),
    now(), now(), '', '', '', '', '', '', '', '');

  select c.id into v_class from public.classes c where c.end_date >= current_date order by c.start_date limit 1;
  insert into public.students (id, parent_id, name, birth_year, years_playing, level) values
    (v_s1, v_id, '小明', extract(year from now())::int - 9, 1, 'foundation'),
    (v_s2, v_id, '小欣', extract(year from now())::int - 7, 0, 'starter');
  if v_class is not null then
    insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone)
    values (v_class, v_s1, 'pending', 'member', '試玩家長', '5558 0000');
  end if;
  insert into public.custom_requests (profile_id, team_name, contact_name, contact_phone, item_type, qty, size_breakdown, colors, due_date, notes, quote_amount, quote_note, status, fabric, features, estimate_amount)
  values (v_id, '我哋嘅球隊（試玩）', '試玩家長', '5558 0000', 'jersey', 12, '{"M": 6, "L": 6}'::jsonb, '主色藍、號碼白', current_date + 30, '示範訂製：可以試接受報價同付款',
    1620, '包印刷號碼及隊名，交貨期約 3 星期。', 'quoted', 'mesh', '{cooling,name_number}', 1700);

  return v_email;
end;
$$;
revoke execute on function public.demo_spawn_member() from public;
grant execute on function public.demo_spawn_member() to anon, authenticated;
