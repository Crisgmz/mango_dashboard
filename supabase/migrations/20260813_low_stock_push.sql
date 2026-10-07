-- 20260813_low_stock_push.sql
-- ═══════════════════════════════════════════════════════════════════════════════
-- Alerta diaria de stock bajo por push (FCM) — estilo Square.
--
-- Un job diario (pg_cron) invoca la Edge Function `push-notify` con
-- {"kind":"low_stock_sweep"} y el bearer service_role. La función llama a
-- `fn_low_stock_alerts_due()` (definida aquí) para saber QUÉ negocios tienen
-- artículos bajo mínimo hoy y CON QUÉ mensaje, y hace fan-out a los
-- device_tokens de cada negocio (owners/admins, respetando el toggle
-- `stock_low` de notification_preferences).
--
-- Fuente de verdad: v_inventory_reorder_suggestions (20260516_0016) — ya
-- excluye items inactivos, sin min_stock y la bodega __IN_TRANSIT__.
--
-- Anti-spam: un solo push por negocio por día (resumen), solo si hay ≥1
-- artículo bajo mínimo. El usuario puede apagarlo por negocio en Ajustes →
-- Notificaciones (event_type = 'stock_low').
--
-- Reusa private.dashboard_cron_config (creada en 20260617_billing_reminders_push);
-- si no está poblada, el cron no hace nada (solo un notice).
--
-- Idempotente: CREATE OR REPLACE + unschedule/schedule del job.
-- ═══════════════════════════════════════════════════════════════════════════════

begin;

-- ── Qué negocios alertar hoy + el mensaje ──
-- Devuelve (business_id, title, body). La Edge Function fan-out a device_tokens.
create or replace function public.fn_low_stock_alerts_due()
returns table (business_id uuid, title text, body text)
language sql
security definer
set search_path = public
as $$
  with low as (
    select
      s.business_id,
      s.name,
      s.deficit
    from public.v_inventory_reorder_suggestions s
  ),
  agg as (
    select
      l.business_id,
      count(*)::int as item_count,
      -- Los 3 con mayor faltante, para que el push diga QUÉ falta.
      (array_agg(l.name order by l.deficit desc))[1:3] as top_names
    from low l
    group by l.business_id
  )
  select
    a.business_id,
    case
      when a.item_count = 1 then 'Stock bajo: 1 artículo'
      else format('Stock bajo: %s artículos', a.item_count)
    end as title,
    case
      when a.item_count <= 3 then
        format('Bajo mínimo: %s. Revisa "Qué comprar hoy".',
               array_to_string(a.top_names, ', '))
      else
        format('Bajo mínimo: %s y %s más. Revisa "Qué comprar hoy".',
               array_to_string(a.top_names, ', '),
               a.item_count - 3)
    end as body
  from agg a;
$$;

alter function public.fn_low_stock_alerts_due() owner to postgres;
-- OJO: el revoke debe incluir PUBLIC — Postgres da EXECUTE a public por
-- defecto y anon lo hereda aunque se le revoque directamente.
revoke all on function public.fn_low_stock_alerts_due() from public, anon, authenticated;
grant execute on function public.fn_low_stock_alerts_due() to service_role;

comment on function public.fn_low_stock_alerts_due() is
  'Negocios con artículos bajo mínimo hoy + mensaje del push. Consumida por '
  'la Edge Function push-notify (kind=low_stock_sweep) vía pg_cron.';

-- ── Disparador diario: invoca push-notify (sweep) vía pg_net ──
create or replace function private.fn_run_low_stock_alerts()
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_cfg private.dashboard_cron_config%rowtype;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'pg_net no disponible; el cron de stock bajo no puede invocar la Edge Function.';
    return;
  end if;

  select * into v_cfg from private.dashboard_cron_config where id = true;
  if not found then
    raise notice 'private.dashboard_cron_config sin configurar; el cron de stock bajo no hace nada.';
    return;
  end if;

  perform net.http_post(
    url := rtrim(v_cfg.functions_base_url, '/') || '/push-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_cfg.service_role_key
    ),
    body := jsonb_build_object('kind', 'low_stock_sweep')
  );
end;
$$;

alter function private.fn_run_low_stock_alerts() owner to postgres;

-- Agendar diario 12:00 UTC (~8am AST): antes de abrir, para comprar temprano.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'low_stock_push';
    perform cron.schedule(
      'low_stock_push',
      '0 12 * * *',
      $cron$select private.fn_run_low_stock_alerts()$cron$
    );
  else
    raise notice 'pg_cron no disponible. Agenda manual: select cron.schedule(''low_stock_push'',''0 12 * * *'',''select private.fn_run_low_stock_alerts()'');';
  end if;
exception when insufficient_privilege then
  raise notice 'Sin privilegio para pg_cron; agendar manualmente fn_run_low_stock_alerts.';
end $$;

commit;
