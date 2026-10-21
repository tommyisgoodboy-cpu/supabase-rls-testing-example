-- 電話登入加密鑰（10/15）：email_for_phone 之前 anon 直接 call 就攞到任何會員電郵（洩露風險）。
-- 而家要提供只有伺服器知道嘅密鑰（環境變數 PHONE_LOGIN_KEY）先會回傳電郵；冇設定密鑰 = 電話登入停用（安全預設）。
-- 密鑰唔寫入 migration / repo：部署時手動 insert 一次：
--   insert into private.app_secrets (name, value) values ('phone_login_key', '<隨機字串>') on conflict (name) do update set value = excluded.value;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.app_secrets (
  name  text primary key,
  value text not null
);
revoke all on private.app_secrets from public, anon, authenticated;

drop function if exists public.email_for_phone(text);
create or replace function public.email_for_phone(p_phone text, p_key text)
returns text
language sql stable security definer
set search_path = ''
as $$
  select u.email::text
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.phone = p_phone
    and p_key is not null
    and p_key = (select s.value from private.app_secrets s where s.name = 'phone_login_key')
  order by u.created_at
  limit 1;
$$;
revoke execute on function public.email_for_phone(text, text) from public;
grant execute on function public.email_for_phone(text, text) to anon, authenticated;
