-- 20260617_billing_reminders_push.sql
-- ═══════════════════════════════════════════════════════════════════════════════
-- Recordatorios de cobro por push (FCM).
--
-- Un job diario (pg_cron) invoca la Edge Function `push-notify` con
-- {"kind":"billing_reminder_sweep"} y el bearer service_role. La función llama a
-- `fn_billing_reminders_due()` (definida aquí) para saber A QUIÉN avisar hoy y
-- CON QUÉ mensaje, y hace fan-out a los device_tokens de cada negocio.
--
-- Por qué así: el envío FCM (service account / OAuth) vive en la Edge Function;
-- la selección + el texto viven en SQL (una sola fuente). El cron solo dispara.
--
-- Solo LEE memberships/plans/azul_payment_methods (la fila ancla del comercio).
-- No muta ninguna columna del motor de cobro (regla R3 del PRD).
--
-- Para no spamear: avisos de cobro/fin de prueba se disparan en offsets exactos
-- (5 y 1 días antes). `past_due` y `suspended` se avisan cada día (acción urgente).
--
-- SECRETO: el service_role key y la URL base NO se hardcodean; viven en
-- private.dashboard_cron_config (RLS denegado a todos). Poblar una sola vez:
--
--   insert into private.dashboard_cron_config (functions_base_url, service_role_key)
--   values ('https://supabase.mangopos.do/functions/v1', '<SERVICE_ROLE_KEY>')
--   on conflict (id) do update
--     set functions_base_url = excluded.functions_base_url,
--         service_role_key   = excluded.service_role_key,
--         updated_at = now();
--
-- IMPORTANTE: ese service_role_key debe ser el del proyecto (el mismo que la
-- Edge Function ve en SUPABASE_SERVICE_ROLE_KEY); la función valida el bearer.
--
-- Idempotente: si no hay pg_net / pg_cron, la migración no falla (solo avisa).
-- ═══════════════════════════════════════════════════════════════════════════════

begin;

create schema if not exists private;

-- Config singleton (una sola fila, id=true).
create table if not exists private.dashboard_cron_config (
  id boolean primary key default true check (id = true),
  functions_base_url text not null,
  service_role_key text not null,
  updated_at timestamptz not null default now()
);

alter table private.dashboard_cron_config enable row level security;
revoke all on private.dashboard_cron_config from anon, authenticated;
-- Sin políticas RLS => nadie (salvo postgres / security definer) puede leerla.

-- ── Quién recibe recordatorio hoy + el mensaje ──
-- Devuelve (business_id, title, body). La Edge Function fan-out a device_tokens.
create or replace function public.fn_billing_reminders_due(p_days int default 5)
returns table (business_id uuid, title text, body text)
language sql
security definer
set search_path = public
as $$
  -- past_due: urgente, cada día.
  select m.business_id,
         'Tienes un pago pendiente'::text,
         case
           when coalesce(m.current_attempt_number, 0) > 0 then
             format('El último cobro fue declinado (intento %s de 3). Actualiza tu tarjeta para evitar la suspensión del servicio.',
                    m.current_attempt_number)
           else 'Hay un cobro pendiente. Revisa tu método de pago.'
         end
  from public.memberships m
  where m.is_billing_anchor = true
    and m.billing_status = 'past_due'

  union all

  -- suspended: urgente, cada día.
  select m.business_id,
         'Suscripción suspendida'::text,
         'Tu servicio está suspendido por falta de pago. Actualiza tu tarjeta para reactivarlo.'::text
  from public.memberships m
  where m.is_billing_anchor = true
    and m.billing_status = 'suspended'

  union all

  -- active: próximo cobro, en offsets exactos (p_days y 1 día antes).
  select m.business_id,
         'Recordatorio de cobro'::text,
         format('Tu suscripción%s se renueva %s (%s).',
                coalesce(' de RD$ ' || to_char(p.price_cents_monthly / 100.0, 'FM999,999,990.00'), ''),
                case (m.next_billing_date - current_date)
                  when 0 then 'hoy' when 1 then 'mañana'
                  else format('en %s días', (m.next_billing_date - current_date)) end,
                to_char(m.next_billing_date, 'DD/MM/YYYY'))
  from public.memberships m
  left join public.plans p on p.id = m.plan_id
  where m.is_billing_anchor = true
    and m.billing_status = 'active'
    and m.next_billing_date is not null
    and (m.next_billing_date - current_date) = any (array[greatest(p_days, 2), 1])

  union all

  -- trial: fin de prueba, en offsets exactos (p_days y 1 día antes).
  select m.business_id,
         'Tu prueba está por terminar'::text,
         format('Tu período de prueba termina %s (%s). %s',
                case (m.trial_ends_at::date - current_date)
                  when 0 then 'hoy' when 1 then 'mañana'
                  else format('en %s días', (m.trial_ends_at::date - current_date)) end,
                to_char(m.trial_ends_at, 'DD/MM/YYYY'),
                case when exists (
                       select 1 from public.azul_payment_methods pm
                       where pm.business_id = m.business_id
                         and pm.is_default = true
                         and pm.status = 'verified')
                     then 'Tu suscripción continuará automáticamente.'
                     else 'Registra una tarjeta para no perder el servicio.' end)
  from public.memberships m
  where m.is_billing_anchor = true
    and m.billing_status = 'trial'
    and m.trial_ends_at is not null
    and (m.trial_ends_at::date - current_date) = any (array[greatest(p_days, 2), 1]);
$$;

alter function public.fn_billing_reminders_due(int) owner to postgres;
revoke all on function public.fn_billing_reminders_due(int) from anon, authenticated;
grant execute on function public.fn_billing_reminders_due(int) to service_role;

-- ── Disparador diario: invoca push-notify (sweep) vía pg_net ──
create or replace function private.fn_run_billing_reminders()
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_cfg private.dashboard_cron_config%rowtype;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net no disponible; el cron de recordatorios no puede invocar la Edge Function.';
    return;
  end if;

  select * into v_cfg from private.dashboard_cron_config where id = true;
  if not found then
    raise notice 'private.dashboard_cron_config sin configurar; el cron de recordatorios no hace nada.';
    return;
  end if;

  perform net.http_post(
    url := rtrim(v_cfg.functions_base_url, '/') || '/push-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_cfg.service_role_key
    ),
    body := jsonb_build_object('kind', 'billing_reminder_sweep')
  );
end;
$$;

alter function private.fn_run_billing_reminders() owner to postgres;

-- Agendar diario 13:00 UTC (~9am AST): un recordatorio matutino.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'billing_reminders_push';
    perform cron.schedule(
      'billing_reminders_push',
      '0 13 * * *',
      $cron$select private.fn_run_billing_reminders()$cron$
    );
  else
    raise notice 'pg_cron no disponible. Agenda manual: select cron.schedule(''billing_reminders_push'',''0 13 * * *'',''select private.fn_run_billing_reminders()'');';
  end if;
exception when insufficient_privilege then
  raise notice 'Sin privilegio para pg_cron; agendar manualmente fn_run_billing_reminders.';
end $$;

commit;
