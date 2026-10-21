-- =============================================================
-- 06 · 前台報名 RPC
-- 訪客（同已登入會員）經呢個 function 報名，唔使開放 anon 直接寫 table。
-- 一次過：檢查班次 → 建立學員 → 寫入報名（額滿由 trigger 轉 waitlist）。
--
-- 自訂錯誤碼（前台按 code 顯示訊息）：
--   EB001  班次唔存在 / 已停止報名
--   EB002  同一學員已經報咗呢班
--   EB003  資料唔齊或格式錯誤
-- =============================================================

create or replace function public.enroll_guest(
  p_class_id      uuid,
  p_parent_name   text,
  p_parent_phone  text,
  p_parent_email  text,
  p_student_name  text,
  p_birth_year    integer,
  p_years_playing integer default 0,
  p_notes         text default null
)
returns table (enrollment_id uuid, status public.enrollment_status)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_parent_name text := nullif(btrim(p_parent_name), '');
  v_parent_phone text := nullif(btrim(p_parent_phone), '');
  v_parent_email text := nullif(lower(btrim(p_parent_email)), '');
  v_student_name text := nullif(btrim(p_student_name), '');
  v_level public.skill_level;
  v_student uuid;
  v_enrollment uuid;
  v_status public.enrollment_status;
begin
  -- ---------- 驗證輸入 ----------
  if v_parent_name is null or v_student_name is null or v_parent_phone is null then
    raise exception using errcode = 'EB003', message = '請填寫家長姓名、聯絡電話同學員姓名';
  end if;

  if length(regexp_replace(v_parent_phone, '\D', '', 'g')) < 8 then
    raise exception using errcode = 'EB003', message = '聯絡電話格式唔正確';
  end if;

  if v_parent_email is not null and v_parent_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception using errcode = 'EB003', message = '電郵格式唔正確';
  end if;

  if p_birth_year is null
     or p_birth_year < extract(year from current_date)::int - 80
     or p_birth_year > extract(year from current_date)::int - 3 then
    raise exception using errcode = 'EB003', message = '出生年份唔正確';
  end if;

  if coalesce(p_years_playing, 0) < 0 or coalesce(p_years_playing, 0) > 60 then
    raise exception using errcode = 'EB003', message = '球齡唔正確';
  end if;

  if length(v_parent_name) > 100 or length(v_student_name) > 100 or length(coalesce(p_notes, '')) > 1000 then
    raise exception using errcode = 'EB003', message = '輸入內容太長';
  end if;

  -- ---------- 班次仲接唔接受報名 ----------
  select co.level into v_level
  from public.classes c
  join public.courses co on co.id = c.course_id
  where c.id = p_class_id
    and co.is_active
    and c.end_date >= current_date;

  if not found then
    raise exception using errcode = 'EB001', message = '呢個班已經停止報名';
  end if;

  -- ---------- 防止重複報名 ----------
  -- 會員：同一個學員名；訪客：同一個電話 + 學員名
  if exists (
    select 1
    from public.enrollments e
    join public.students s on s.id = e.student_id
    where e.class_id = p_class_id
      and e.status <> 'cancelled'
      and lower(s.name) = lower(v_student_name)
      and (
        (v_uid is not null and s.parent_id = v_uid)
        or regexp_replace(coalesce(e.parent_phone, ''), '\D', '', 'g') = regexp_replace(v_parent_phone, '\D', '', 'g')
      )
  ) then
    raise exception using errcode = 'EB002', message = '呢位學員已經報咗呢個班';
  end if;

  -- ---------- 建立學員 + 報名 ----------
  insert into public.students (parent_id, name, birth_year, years_playing, level, notes)
  values (v_uid, v_student_name, p_birth_year, coalesce(p_years_playing, 0), v_level, nullif(btrim(p_notes), ''))
  returning id into v_student;

  insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone, parent_email, notes)
  values (
    p_class_id, v_student, 'pending',
    case when v_uid is null then 'guest' else 'member' end::public.enrollment_source,
    v_parent_name, v_parent_phone, v_parent_email, nullif(btrim(p_notes), '')
  )
  returning id, enrollments.status into v_enrollment, v_status;

  return query select v_enrollment, v_status;
end;
$$;

revoke execute on function public.enroll_guest(uuid, text, text, text, text, integer, integer, text) from public;
grant execute on function public.enroll_guest(uuid, text, text, text, text, integer, integer, text) to anon, authenticated;
