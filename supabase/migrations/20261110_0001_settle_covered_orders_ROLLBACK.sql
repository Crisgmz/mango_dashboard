-- =============================================================================
-- ROLLBACK de 20261110_0001 — Órdenes cobradas de mesas liberadas
-- =============================================================================
-- Quita la regla. Las órdenes que ya cerró se quedan cerradas (estaban
-- cobradas completas); para revisarlas, las que cerró esta regla tienen
-- closed_at = la hora exacta de su último pago completado.
-- =============================================================================

begin;

set local lock_timeout = '5s';

drop trigger if exists trg_zz_settle_on_session_close on public.table_sessions;
drop trigger if exists trg_zz_settle_on_payment on public.payments;
drop function if exists public.fn_settle_on_session_close();
drop function if exists public.fn_settle_on_payment();
drop function if exists private.fn_settle_order_if_covered(uuid);

commit;
