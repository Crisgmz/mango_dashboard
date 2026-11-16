-- =============================================================================
-- 20261110_0001 — Una orden COBRADA de una mesa ya liberada queda pagada
-- =============================================================================
--
-- PROBLEMA (GFC, 2026-11-10). El dashboard mostraba «Ventas del día»
-- RD$ 2,198.40 mientras la caja abierta llevaba RD$ 6,189.40 cobrados, y
-- «Por Cobrar» RD$ 120,637.92 en 28 órdenes «activas». El dashboard cuenta
-- como venta solo los pagos de órdenes CERRADAS (orders.closed_at) y como
-- activa toda orden sin closed_at. Una orden cuyo cobro cubre todo pero que
-- quedó sin cerrar (la mesa se liberó, la sesión se cerró, la orden no):
--   * su dinero está en la caja pero no en «Ventas del día»;
--   * sigue «activa» y la versión publicada del dashboard suma lo cobrado a
--     «Por Cobrar».
-- Mismo patrón que la limpieza manual de f054fbc2 (supabase/
-- CERRAR_ordenes_cobradas_abiertas.sql, 2026-08-30). Aquí se vuelve regla
-- del servidor, para que no dependa de la versión de la app.
--
-- REGLA. Si la sesión de mesa YA está cerrada y lo cobrado (pagos
-- completados, neto del vuelto) cubre lo vendido (ítems no anulados:
-- subtotal + tax − discounts, con RD$ 1 de tolerancia, como 20260830), la
-- orden queda como la deja fn_close_order_and_table al cobrar:
--   status_ext = status = 'paid', closed_at = el momento del ÚLTIMO cobro
--   (así cada venta cae en el día en que se cobró, no hoy), y sus
--   subcuentas cerradas. Si orders.business_id está vacío, se toma de la
--   sesión (el dashboard filtra las ventas por esa columna).
-- Se revisa al cerrarse la sesión y al completarse un pago (un cobro
-- offline que llega después de liberada la mesa).
--
-- QUÉ NO TOCA:
--   * Órdenes con la sesión abierta (la mesa sigue en uso: el cliente puede
--     pedir más), anuladas, ya cerradas, en revisión (orders.review_reason,
--     20261010_0020: las decide una persona) o cobradas a medias.
--   * order_items: el KDS sigue igual (filtra por el estado del ítem).
--   * dining_tables ni table_sessions.
--   * Ningún error frena la operación del POS: se avisa con WARNING.
--
-- ATRASADO: esta migración NO cierra lo que ya está atascado (cambia las
-- ventas de días pasados). Eso va aparte, con su vista previa:
-- scripts/CERRAR_cobradas_abiertas_sesion_cerrada.sql.
--
-- IDEMPOTENTE. ROLLBACK: 20261110_0001_settle_covered_orders_ROLLBACK.sql
-- Prueba: supabase/tests/settle_covered_orders_local_test.sh
-- Aplicar en horario de poca venta (los triggers esperan el candado de
-- payments y table_sessions; lock_timeout 5 s, si vence se vuelve a correr).
-- =============================================================================

begin;

set local lock_timeout = '5s';

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- 1. La regla
-- ---------------------------------------------------------------------------
-- true si cerró la orden. Para el trigger y para la limpieza del atrasado.
create or replace function private.fn_settle_order_if_covered(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_business uuid;
  v_last_paid        timestamptz;
  v_paid             numeric;
  v_sold             numeric;
begin
  if p_order_id is null then
    return false;
  end if;

  select ts.business_id
    into v_session_business
  from public.orders o
  join public.table_sessions ts on ts.id = o.session_id
  where o.id = p_order_id
    and o.closed_at is null
    and o.status_ext::text not in ('paid', 'void')
    and ts.closed_at is not null
    and (to_jsonb(o) ->> 'review_reason') is null
  for update of o;
  if not found then
    return false;
  end if;

  select coalesce(sum(p.amount - coalesce(p.change_amount, 0)), 0),
         max(p.created_at)
    into v_paid, v_last_paid
  from public.payments p
  where p.order_id = p_order_id
    and p.status = 'completed';

  select coalesce(sum(i.subtotal + i.tax - coalesce(i.discounts, 0)), 0)
    into v_sold
  from public.order_items i
  where i.order_id = p_order_id
    and i.status::text <> 'void';

  if v_last_paid is null or v_sold <= 0 or v_paid + 1 < v_sold then
    return false;
  end if;

  update public.orders o
     set status_ext  = 'paid',
         status      = 'paid',
         closed_at   = v_last_paid,
         business_id = coalesce(o.business_id, v_session_business)
   where o.id = p_order_id;

  update public.order_checks c
     set is_closed = true,
         closed_at = coalesce(c.closed_at, v_last_paid)
   where c.order_id = p_order_id
     and coalesce(c.is_closed, false) = false;

  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Cuándo se revisa
-- ---------------------------------------------------------------------------
create or replace function public.fn_settle_on_session_close()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order uuid;
begin
  for v_order in
    select o.id from public.orders o
    where o.session_id = new.id
      and o.closed_at is null
      and o.status_ext::text not in ('paid', 'void')
  loop
    begin
      perform private.fn_settle_order_if_covered(v_order);
    exception when others then
      raise warning 'fn_settle_on_session_close (orden %): % (%)', v_order, sqlerrm, sqlstate;
    end;
  end loop;
  return null;
end;
$$;

create or replace function public.fn_settle_on_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform private.fn_settle_order_if_covered(new.order_id);
  exception when others then
    raise warning 'fn_settle_on_payment (orden %): % (%)', new.order_id, sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

drop trigger if exists trg_zz_settle_on_session_close on public.table_sessions;
create trigger trg_zz_settle_on_session_close
  after update of closed_at on public.table_sessions
  for each row
  when (old.closed_at is null and new.closed_at is not null)
  execute function public.fn_settle_on_session_close();

drop trigger if exists trg_zz_settle_on_payment on public.payments;
create trigger trg_zz_settle_on_payment
  after insert or update of status on public.payments
  for each row
  when (new.status = 'completed' and new.order_id is not null)
  execute function public.fn_settle_on_payment();

revoke all on function private.fn_settle_order_if_covered(uuid) from public;
revoke all on function public.fn_settle_on_session_close() from public, anon, authenticated;
revoke all on function public.fn_settle_on_payment() from public, anon, authenticated;

commit;

-- Verificación (correr aparte):
--   select tgname, tgrelid::regclass from pg_trigger
--    where tgname in ('trg_zz_settle_on_session_close', 'trg_zz_settle_on_payment');
