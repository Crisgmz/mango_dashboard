-- Enable Realtime for notification-relevant tables
-- These tables must be part of the supabase_realtime publication
-- for the dashboard to receive live notifications.

-- Safely add tables (ignore if already added)
DO $$
BEGIN
  -- order_items: notify when product is voided
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'order_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.order_items;
  END IF;

  -- cash_register_sessions: notify when cash register is closed
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'cash_register_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cash_register_sessions;
  END IF;

  -- table_sessions: notify when a new account/table is opened
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'table_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.table_sessions;
  END IF;
END $$;

-- Enable REPLICA IDENTITY FULL so realtime sends old + new record on updates
-- This is needed for the dashboard to detect status transitions (e.g. void)
ALTER TABLE public.order_items REPLICA IDENTITY FULL;
ALTER TABLE public.cash_register_sessions REPLICA IDENTITY FULL;
ALTER TABLE public.table_sessions REPLICA IDENTITY FULL;
