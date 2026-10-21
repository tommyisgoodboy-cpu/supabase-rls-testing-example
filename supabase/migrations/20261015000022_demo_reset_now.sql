-- 示範站「一鍵還原」（10/15）：已登入嘅用戶可以隨時還原示範資料（每 3 分鐘最多一次），唔使等夜間自動還原。
-- 只存在於示範資料庫（依賴 demo_admin.reset）。還原會清走所有帳戶，包括撳掣嗰個，所以前端要重新登入。
create table if not exists demo_admin.reset_log (
  id         int primary key default 1 check (id = 1),
  last_reset timestamptz not null
);
revoke all on demo_admin.reset_log from public, anon, authenticated;

create or replace function public.demo_reset_now()
returns text
language plpgsql security definer
set search_path = public, auth, extensions
as $$
declare
  v_last timestamptz;
begin
  if auth.uid() is null then return 'login'; end if;
  select last_reset into v_last from demo_admin.reset_log where id = 1;
  if v_last is not null and now() - v_last < interval '3 minutes' then return 'cooldown'; end if;
  insert into demo_admin.reset_log (id, last_reset) values (1, now())
    on conflict (id) do update set last_reset = excluded.last_reset;
  -- 觸發器（改角色 / 訂單 guard）靠 auth.uid() 分辨「用戶」同「系統」；還原係系統動作，所以清走 JWT 身份
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
  perform demo_admin.reset();
  return 'ok';
end;
$$;
revoke execute on function public.demo_reset_now() from public, anon;
grant execute on function public.demo_reset_now() to authenticated;
