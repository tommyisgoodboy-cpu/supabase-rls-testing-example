-- =============================================================
-- 08 · 會員系統
--   1. 訪客報名認領碼：報完名喺同一部機開帳戶 / 登入，自動連結學員
--   2. 會員用已有學員報名（enroll_member），取代直接 insert enrollments
--   3. 技術等級只可以由管理員改
-- =============================================================

-- ---------- 1. 認領碼 ----------
-- 只喺訪客報名時產生，認領後清空。唔用電話 / 電郵配對，因為兩者都可以亂填。
alter table public.enrollments add column claim_token uuid;
create unique index enrollments_claim_token_idx on public.enrollments (claim_token) where claim_token is not null;

-- enroll_guest 要多回傳 claim_token，回傳型別變咗所以要 drop 再建
drop function public.enroll_guest(uuid, text, text, text, text, integer, integer, text);

create function public.enroll_guest(
  p_class_id      uuid,
  p_parent_name   text,
  p_parent_phone  text,
  p_parent_email  text,
  p_student_name  text,
  p_birth_year    integer,
  p_years_playing integer default 0,
  p_notes         text default null
)
returns table (enrollment_id uuid, status public.enrollment_status, claim_token uuid)
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
  v_token uuid := case when auth.uid() is null then gen_random_uuid() end;
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

  insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone, parent_email, notes, claim_token)
  values (
    p_class_id, v_student, 'pending',
    case when v_uid is null then 'guest' else 'member' end::public.enrollment_source,
    v_parent_name, v_parent_phone, v_parent_email, nullif(btrim(p_notes), ''), v_token
  )
  returning id, enrollments.status into v_enrollment, v_status;

  return query select v_enrollment, v_status, v_token;
end;
$$;

revoke execute on function public.enroll_guest(uuid, text, text, text, text, integer, integer, text) from public;
grant execute on function public.enroll_guest(uuid, text, text, text, text, integer, integer, text) to anon, authenticated;

-- 登入 / 註冊後認領：將認領碼對應嘅訪客學員歸入目前帳戶。回傳認領咗幾多個報名。
create function public.claim_enrollments(p_tokens uuid[])
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = '請先登入';
  end if;
  if p_tokens is null or cardinality(p_tokens) = 0 then
    return 0;
  end if;
  if cardinality(p_tokens) > 20 then
    raise exception using errcode = 'EB003', message = '認領碼太多';
  end if;

  update public.students s
  set parent_id = v_uid
  from public.enrollments e
  where e.student_id = s.id
    and e.claim_token = any(p_tokens)
    and s.parent_id is null;

  update public.enrollments
  set claim_token = null
  where claim_token = any(p_tokens);
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

revoke execute on function public.claim_enrollments(uuid[]) from public, anon;
grant execute on function public.claim_enrollments(uuid[]) to authenticated;

-- ---------- 2. 會員用已有學員報名 ----------
-- 唔再畀會員直接 insert enrollments（policy 檢查唔到班次有冇完結），一律經 RPC。
drop policy "enrollments: 會員可為自己學員報名" on public.enrollments;

create function public.enroll_member(p_class_id uuid, p_student_id uuid, p_notes text default null)
returns table (enrollment_id uuid, status public.enrollment_status)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_enrollment uuid;
  v_status public.enrollment_status;
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = '請先登入';
  end if;

  if not exists (select 1 from public.students where id = p_student_id and parent_id = v_uid) then
    raise exception using errcode = 'EB003', message = '搵唔到呢位學員';
  end if;

  if not exists (
    select 1
    from public.classes c
    join public.courses co on co.id = c.course_id
    where c.id = p_class_id and co.is_active and c.end_date >= current_date
  ) then
    raise exception using errcode = 'EB001', message = '呢個班已經停止報名';
  end if;

  if exists (
    select 1 from public.enrollments
    where class_id = p_class_id and student_id = p_student_id and enrollments.status <> 'cancelled'
  ) then
    raise exception using errcode = 'EB002', message = '呢位學員已經報咗呢個班';
  end if;

  if length(coalesce(p_notes, '')) > 1000 then
    raise exception using errcode = 'EB003', message = '輸入內容太長';
  end if;

  select * into v_profile from public.profiles where id = v_uid;

  insert into public.enrollments (class_id, student_id, status, source, parent_name, parent_phone, parent_email, notes)
  values (
    p_class_id, p_student_id, 'pending', 'member',
    v_profile.full_name, v_profile.phone,
    (select email from auth.users where id = v_uid),
    nullif(btrim(p_notes), '')
  )
  returning id, enrollments.status into v_enrollment, v_status;

  return query select v_enrollment, v_status;
end;
$$;

revoke execute on function public.enroll_member(uuid, uuid, text) from public, anon;
grant execute on function public.enroll_member(uuid, uuid, text) to authenticated;

-- ---------- 3. 技術等級只可以由管理員改 ----------
-- security invoker：current_user 係 'authenticated' 即係經 API 直接改；
-- 經 enroll_guest 等 security definer function 寫入時 current_user 係 owner，唔受限。
create function public.trg_students_guard_level()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'authenticated' and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.level := 'starter';
    elsif new.level is distinct from old.level then
      new.level := old.level;
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.trg_students_guard_level() from public, anon, authenticated;

create trigger students_guard_level
  before insert or update on public.students
  for each row execute function public.trg_students_guard_level();
