-- 用電話登入（10/15）：伺服器端 action 用電話搵返登入電郵，再用電郵 + 密碼登入。電郵唔會傳去瀏覽器。
-- 示範站：anon 都可以 call；正式客戶版應加 rate limit / 驗證碼。
create or replace function public.email_for_phone(p_phone text)
returns text
language sql stable security definer
set search_path = ''
as $$
  select u.email::text
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.phone = p_phone
  order by u.created_at
  limit 1;
$$;
revoke execute on function public.email_for_phone(text) from public;
grant execute on function public.email_for_phone(text) to anon, authenticated;
