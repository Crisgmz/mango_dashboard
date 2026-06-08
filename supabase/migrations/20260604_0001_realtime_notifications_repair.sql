-- Repara/asegura Realtime para las tablas de notificaciones del dashboard.
-- Idempotente: se puede correr varias veces sin romper nada.
--
-- Causa del error 42501 ("You do not have required role or permission to
-- perform an operation") al suscribirse: la BD en vivo no tenía las tablas en
-- la publicación supabase_realtime (o le faltaba el GRANT/replica identity),
-- aunque el esquema base sí los declara.

-- 1. Asegurar que la publicación exista (en self-hosted normalmente ya existe).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- 2. Agregar las 3 tablas a la publicación (ignorar si ya están).
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['order_items', 'cash_register_sessions', 'table_sessions']
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

-- 3. REPLICA IDENTITY FULL: realtime necesita el registro viejo + nuevo en UPDATE
--    para detectar transiciones (p.ej. status -> void, closed_at).
ALTER TABLE public.order_items            REPLICA IDENTITY FULL;
ALTER TABLE public.cash_register_sessions REPLICA IDENTITY FULL;
ALTER TABLE public.table_sessions         REPLICA IDENTITY FULL;

-- 4. Asegurar el GRANT de SELECT al rol authenticated (lo que el chequeo de
--    autorización de realtime valida; su ausencia produce 42501).
GRANT SELECT ON public.order_items            TO authenticated;
GRANT SELECT ON public.cash_register_sessions TO authenticated;
GRANT SELECT ON public.table_sessions         TO authenticated;

-- 5. Diagnóstico: muestra el estado final. Revisa la salida de este SELECT.
SELECT
  t.tablename,
  EXISTS (
    SELECT 1 FROM pg_publication_tables p
    WHERE p.pubname = 'supabase_realtime'
      AND p.schemaname = 'public' AND p.tablename = t.tablename
  ) AS en_publicacion,
  c.relreplident AS replica_identity,  -- 'f' = FULL (correcto)
  has_table_privilege('authenticated', 'public.' || t.tablename, 'SELECT') AS authenticated_puede_select
FROM (VALUES ('order_items'), ('cash_register_sessions'), ('table_sessions')) AS t(tablename)
JOIN pg_class c ON c.relname = t.tablename
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public';
