-- Device push tokens for FCM. One row per device token; re-pointed to the
-- current user + business when the app registers it. Used by the push-notify
-- Edge Function to target a business's devices.
--
-- NOTE: business_id is typed uuid to match businesses.id. If your businesses.id
-- is a different type, change it here accordingly.
create table if not exists public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  business_id uuid not null,
  platform    text,
  updated_at  timestamptz not null default now()
);

create index if not exists device_tokens_business_idx
  on public.device_tokens (business_id);

alter table public.device_tokens enable row level security;

-- A user manages only their own device tokens. The Edge Function reads tokens
-- with the service role, which bypasses RLS.
create policy device_tokens_select on public.device_tokens
  for select to authenticated using (user_id = auth.uid());

create policy device_tokens_insert on public.device_tokens
  for insert to authenticated with check (user_id = auth.uid());

create policy device_tokens_update on public.device_tokens
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy device_tokens_delete on public.device_tokens
  for delete to authenticated using (user_id = auth.uid());
