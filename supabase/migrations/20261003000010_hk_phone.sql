-- =============================================================
-- 10 · 香港電話格式
-- 所有聯絡電話統一做香港 8 位號碼（2–9 字頭），儲存格式「XXXX XXXX」。
-- 接受用戶輸入 +852 / 852 前綴、空格同連字號。
-- 用 trigger 喺資料庫層面把關，經 RPC、後台或者直接 API 寫入都一樣檢查。
-- =============================================================

create or replace function public.normalize_hk_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if length(v) = 11 and left(v, 3) = '852' then
    v := substr(v, 4);
  end if;
  if v !~ '^[2-9][0-9]{7}$' then
    return null;
  end if;
  return substr(v, 1, 4) || ' ' || substr(v, 5, 4);
end;
$$;

-- 報名 parent_phone、profile phone、訂製查詢 contact_phone 共用
create or replace function public.trg_normalize_phone()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_column text := tg_argv[0];
  v_raw text := to_jsonb(new) ->> v_column;
  v_normalized text;
begin
  if v_raw is null or btrim(v_raw) = '' then
    return new;
  end if;
  v_normalized := public.normalize_hk_phone(v_raw);
  if v_normalized is null then
    raise exception using errcode = 'EB003', message = '請輸入有效嘅香港電話號碼（8 位數字）';
  end if;
  return jsonb_populate_record(new, jsonb_build_object(v_column, v_normalized));
end;
$$;

revoke execute on function public.trg_normalize_phone() from public, anon, authenticated;

create trigger enrollments_normalize_phone
  before insert or update of parent_phone on public.enrollments
  for each row execute function public.trg_normalize_phone('parent_phone');

create trigger profiles_normalize_phone
  before insert or update of phone on public.profiles
  for each row execute function public.trg_normalize_phone('phone');

create trigger custom_requests_normalize_phone
  before insert or update of contact_phone on public.custom_requests
  for each row execute function public.trg_normalize_phone('contact_phone');
