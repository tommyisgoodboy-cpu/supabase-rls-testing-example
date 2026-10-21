-- 示範站「還原」只准三個試玩帳戶撳（10/15）：避免新註冊訪客 / 第三者喺客人試玩途中將資料還原、令客人被踢出。
create or replace function public.demo_reset_now()
returns text
language plpgsql security definer
set search_path = public, auth, extensions
as $$
declare
  v_last timestamptz;
  v_email text;
begin
  if auth.uid() is null then return 'login'; end if;
  select email into v_email from auth.users where id = auth.uid();
  if v_email is null or v_email not in ('admin@educasketball.test', 'coach@educasketball.test', 'member@educasketball.test') then
    return 'demo_only';
  end if;
  select last_reset into v_last from demo_admin.reset_log where id = 1;
  if v_last is not null and now() - v_last < interval '3 minutes' then return 'cooldown'; end if;
  insert into demo_admin.reset_log (id, last_reset) values (1, now())
    on conflict (id) do update set last_reset = excluded.last_reset;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
  perform demo_admin.reset();
  return 'ok';
end;
$$;
