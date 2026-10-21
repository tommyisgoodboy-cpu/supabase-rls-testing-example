-- 日曆訂閱（10/15）：每個用戶一條私人訂閱連結（token），Apple / Google / Outlook 日曆都可以長期訂閱、自動更新。
-- 日曆 app 唔會帶登入 cookie，所以用 token 對應用戶；token 唔係密碼，但知道連結嘅人睇得到時間表，可隨時重置。
alter table public.profiles add column if not exists calendar_token uuid not null default gen_random_uuid();
create unique index if not exists profiles_calendar_token_key on public.profiles (calendar_token);

create or replace function public.calendar_feed(p_token uuid)
returns table (
  uid text, session_date date, start_time time, end_time time,
  summary text, location text, description text, cancelled boolean
)
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
  v_coach uuid;
  v_from date := (now() at time zone 'Asia/Hong_Kong')::date - 30;
  v_to date := (now() at time zone 'Asia/Hong_Kong')::date + 190;
begin
  select * into v_profile from public.profiles where calendar_token = p_token;
  if not found then return; end if;

  if v_profile.role = 'admin' or v_profile.role = 'coach' then
    select id into v_coach from public.coaches where profile_id = v_profile.id;
    return query
      select (s.id::text || '@educasketball.demo'), s.session_date, c.start_time, c.end_time,
             co.title,
             case when v.id is null then null else v.name || '（' || coalesce(v.district, '') || '）' end,
             concat_ws(E'\n', case when ch.name is not null then '教練：' || ch.name end,
                       (select count(*)::text || ' 位學員' from public.enrollments e where e.class_id = c.id and e.status = 'confirmed')),
             (s.status = 'cancelled')
      from public.class_sessions s
      join public.classes c on c.id = s.class_id
      join public.courses co on co.id = c.course_id
      left join public.venues v on v.id = c.venue_id
      left join public.coaches ch on ch.id = c.coach_id
      where s.session_date between v_from and v_to
        and (v_profile.role = 'admin' or c.coach_id = v_coach);
  else
    return query
      select (s.id::text || '-' || st.id::text || '@educasketball.demo'), s.session_date, c.start_time, c.end_time,
             co.title || '・' || st.name,
             case when v.id is null then null else v.name || '（' || coalesce(v.district, '') || '）' end,
             concat_ws(E'\n', case when ch.name is not null then '教練：' || ch.name end,
                       case when e.status = 'pending' then '報名待確認' end),
             (s.status = 'cancelled')
      from public.enrollments e
      join public.students st on st.id = e.student_id and st.parent_id = v_profile.id
      join public.classes c on c.id = e.class_id
      join public.courses co on co.id = c.course_id
      join public.class_sessions s on s.class_id = c.id
      left join public.venues v on v.id = c.venue_id
      left join public.coaches ch on ch.id = c.coach_id
      where e.status in ('confirmed', 'pending')
        and s.session_date between v_from and v_to;
  end if;
end;
$$;
revoke execute on function public.calendar_feed(uuid) from public;
grant execute on function public.calendar_feed(uuid) to anon, authenticated;
