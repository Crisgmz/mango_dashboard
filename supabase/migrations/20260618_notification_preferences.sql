-- Per-user, per-business notification preferences.
--
-- Opt-out model: a MISSING row means the event is ENABLED. A row with
-- enabled=false suppresses that event for that user+business. The push-notify
-- Edge Function reads these with the service role (bypasses RLS) to decide who
-- to notify; the in-app NotificationService reads its own rows via RLS.
--
-- event_type canonical keys — MUST match the Dart NotificationEventType enum and
-- the push-notify Edge Function:
--   item_voided    -> Producto anulado     (push + in-app)
--   cash_closed    -> Cierre de caja        (push + in-app)
--   cash_mismatch  -> Caja descuadrada      (push only)
--   table_opened   -> Nueva cuenta abierta  (in-app only)

create table if not exists public.notification_preferences (
  user_id     uuid not null references auth.users (id) on delete cascade,
  business_id uuid not null,
  event_type  text not null,
  enabled     boolean not null default true,
  updated_at  timestamptz not null default now(),
  primary key (user_id, business_id, event_type)
);

create index if not exists notification_preferences_lookup_idx
  on public.notification_preferences (business_id, event_type)
  where enabled = false;

alter table public.notification_preferences enable row level security;

-- A user reads/writes only their own preferences.
create policy notification_preferences_select on public.notification_preferences
  for select to authenticated using (user_id = auth.uid());

create policy notification_preferences_insert on public.notification_preferences
  for insert to authenticated with check (user_id = auth.uid());

create policy notification_preferences_update on public.notification_preferences
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy notification_preferences_delete on public.notification_preferences
  for delete to authenticated using (user_id = auth.uid());
