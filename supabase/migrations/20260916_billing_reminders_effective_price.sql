-- 20260916_billing_reminders_effective_price.sql
-- ═══════════════════════════════════════════════════════════════════════════════
-- Recordatorio push de cobro con el PRECIO EFECTIVO (precio especial incluido).
--
-- fn_billing_reminders_due (20260617_billing_reminders_push) armaba "Tu
-- suscripción de RD$ X se renueva…" con plans.price_cents_monthly. A un comercio
-- con precio especial (mangospos 20260915_0006) le avisaba el precio de lista y
-- después se le cobraba menos.
--
-- Ahora usa subscription_effective_price_cents(membresía, next_billing_date): la
-- misma función y la misma fecha que azul-charge-subscription usa para cobrar.
--
-- Idéntica a 20260617 salvo el monto de la rama `active`. Conserva los permisos
-- de 20260813_fix_sweep_rpc_public_execute (solo service_role).
--
-- DEPENDE de mangospos/supabase/migrations/20260915_0006_subscription_price_override.sql.
-- Idempotente.
-- ═══════════════════════════════════════════════════════════════════════════════

begin;

do $$
begin
  if to_regprocedure('public.subscription_effective_price_cents(uuid,date)') is null then
    raise exception
      'Falta mangospos 20260915_0006_subscription_price_override.sql. Aplicarla antes que esta.';
  end if;
end $$;

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
  -- Monto = lo que se va a cobrar ESE día (precio especial vigente o lista).
  select m.business_id,
         'Recordatorio de cobro'::text,
         format('Tu suscripción%s se renueva %s (%s).',
                coalesce(' de RD$ ' || to_char(
                  public.subscription_effective_price_cents(m.id, m.next_billing_date) / 100.0,
                  'FM999,999,990.00'), ''),
                case (m.next_billing_date - current_date)
                  when 0 then 'hoy' when 1 then 'mañana'
                  else format('en %s días', (m.next_billing_date - current_date)) end,
                to_char(m.next_billing_date, 'DD/MM/YYYY'))
  from public.memberships m
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
revoke all on function public.fn_billing_reminders_due(int) from public, anon, authenticated;
grant execute on function public.fn_billing_reminders_due(int) to service_role;

commit;
