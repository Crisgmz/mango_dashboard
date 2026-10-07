-- 20260813_fix_sweep_rpc_public_execute.sql
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOTFIX de seguridad: las RPC de los sweeps quedaron ejecutables con el anon
-- key. Postgres otorga EXECUTE a PUBLIC por defecto en toda función nueva, y
-- `revoke ... from anon, authenticated` NO quita ese grant heredado — anon
-- seguía pudiendo llamarlas y leer nombres de negocios, artículos bajo mínimo
-- y estado de cobro de TODOS los negocios.
--
-- Afecta a:
--   - fn_billing_reminders_due(int)  (20260617_billing_reminders_push)
--   - fn_low_stock_alerts_due()      (20260813_low_stock_push)
--
-- Ambas son security definer owner postgres; el service_role (la Edge
-- Function) es el único que debe poder ejecutarlas.
--
-- Idempotente: revoke/grant se pueden re-ejecutar sin efecto adicional.
-- ═══════════════════════════════════════════════════════════════════════════════

begin;

revoke all on function public.fn_billing_reminders_due(int) from public, anon, authenticated;
grant execute on function public.fn_billing_reminders_due(int) to service_role;

revoke all on function public.fn_low_stock_alerts_due() from public, anon, authenticated;
grant execute on function public.fn_low_stock_alerts_due() to service_role;

commit;
