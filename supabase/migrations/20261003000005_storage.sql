-- =============================================================
-- 05 · Storage buckets + policies
--   product-images  public   商品相（admin 上載）
--   coach-photos    public   教練相（admin 上載）
--   team-logos      private  團體訂製 logo（訪客 / 會員上載，admin 下載）
--   payment-proofs  private  付款截圖（會員上載到自己 folder）
-- 路徑約定：team-logos / payment-proofs 第一層 folder = 上載者 uid
--          （訪客上載 team-logos 用 "guest/<隨機 uuid>/檔名"）
-- =============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('product-images', 'product-images', true,  5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('coach-photos',   'coach-photos',   true,  5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('team-logos',     'team-logos',     false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'image/svg+xml', 'application/pdf']),
  ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

-- ---------- 公開 bucket ----------
create policy "public images: 任何人可讀" on storage.objects
  for select to anon, authenticated
  using (bucket_id in ('product-images', 'coach-photos'));

create policy "public images: admin 可上載" on storage.objects
  for insert to authenticated
  with check (bucket_id in ('product-images', 'coach-photos') and (select public.is_admin()));

create policy "public images: admin 可更新" on storage.objects
  for update to authenticated
  using (bucket_id in ('product-images', 'coach-photos') and (select public.is_admin()));

create policy "public images: admin 可刪除" on storage.objects
  for delete to authenticated
  using (bucket_id in ('product-images', 'coach-photos') and (select public.is_admin()));

-- ---------- team-logos ----------
create policy "team-logos: 訪客可上載到 guest folder" on storage.objects
  for insert to anon
  with check (bucket_id = 'team-logos' and (storage.foldername(name))[1] = 'guest');

create policy "team-logos: 會員可上載到自己 folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'team-logos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "team-logos: 會員可讀自己檔案" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'team-logos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "team-logos: admin 全權" on storage.objects
  for all to authenticated
  using (bucket_id = 'team-logos' and (select public.is_admin()))
  with check (bucket_id = 'team-logos' and (select public.is_admin()));

-- ---------- payment-proofs ----------
create policy "payment-proofs: 會員可上載到自己 folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "payment-proofs: 會員可讀自己檔案" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "payment-proofs: admin 全權" on storage.objects
  for all to authenticated
  using (bucket_id = 'payment-proofs' and (select public.is_admin()))
  with check (bucket_id = 'payment-proofs' and (select public.is_admin()));
