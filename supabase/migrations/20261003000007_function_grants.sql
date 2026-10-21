-- =============================================================
-- 07 · 收緊 function 執行權限
-- Supabase 預設畀 anon / authenticated 執行 public schema 所有 function，
-- 即係全部都可以經 /rest/v1/rpc/<name> 呼叫。呢度只保留需要嘅：
--   - anon + authenticated：class_availability()、enroll_guest()（前台公開用）
--   - authenticated：RLS policy 用到嘅 helper（policy 以查詢者身份執行，所以要有權）
--   - 其餘（trigger function、points_rule）只喺 security definer 內部用，唔使畀任何人
-- =============================================================

-- trigger functions + 內部 helper：全部收返
revoke execute on function public.handle_new_user()                from public, anon, authenticated;
revoke execute on function public.trg_classes_sync_sessions()      from public, anon, authenticated;
revoke execute on function public.trg_enrollments_check_capacity() from public, anon, authenticated;
revoke execute on function public.trg_attendance_points()          from public, anon, authenticated;
revoke execute on function public.trg_orders_on_paid()             from public, anon, authenticated;
revoke execute on function public.trg_profiles_guard_role()        from public, anon, authenticated;
revoke execute on function public.trg_orders_guard()               from public, anon, authenticated;
revoke execute on function public.points_rule(text, integer)       from public, anon, authenticated;

-- RLS helper：只有登入用戶需要（所有用到佢哋嘅 policy 都係 to authenticated）
revoke execute on function public.current_user_role()              from public, anon;
revoke execute on function public.is_admin()                       from public, anon;
revoke execute on function public.is_coach_of_class(uuid)          from public, anon;
revoke execute on function public.is_coach_of_session(uuid)        from public, anon;
revoke execute on function public.is_coach_of_student(uuid)        from public, anon;
revoke execute on function public.owns_student(uuid)               from public, anon;
grant execute on function public.current_user_role()               to authenticated;
grant execute on function public.is_admin()                        to authenticated;
grant execute on function public.is_coach_of_class(uuid)           to authenticated;
grant execute on function public.is_coach_of_session(uuid)         to authenticated;
grant execute on function public.is_coach_of_student(uuid)         to authenticated;
grant execute on function public.owns_student(uuid)                to authenticated;
