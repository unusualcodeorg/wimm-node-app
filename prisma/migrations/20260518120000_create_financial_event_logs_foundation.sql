-- Migration: Create financial event logs foundation
-- Created: 2026-05-18
-- Description:
--   - Creates financial event status enum
--   - Creates company-owned financial_event_logs table for accounting event tracking and idempotency
--   - Adds indexes, updated_at trigger, row-level security policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Financial event enums
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'financial_event_status'
  ) THEN
    CREATE TYPE public.financial_event_status AS ENUM (
      'pending',
      'processed',
      'failed',
      'ignored'
    );
  END IF;
END;
$$;

-- ============================================================
-- 2. Financial event logs table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.financial_event_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID,
  event_type TEXT NOT NULL,
  source_module public.journal_source_module NOT NULL,
  reference_type TEXT NOT NULL,
  reference_id UUID NOT NULL,
  idempotency_key TEXT NOT NULL,
  status public.financial_event_status NOT NULL DEFAULT 'pending',
  journal_entry_id UUID,
  payload JSONB,
  error_message TEXT,
  processed_at TIMESTAMPTZ,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT financial_event_logs_event_type_not_blank CHECK (length(btrim(event_type)) > 0),
  CONSTRAINT financial_event_logs_reference_type_not_blank CHECK (length(btrim(reference_type)) > 0),
  CONSTRAINT financial_event_logs_idempotency_key_not_blank CHECK (length(btrim(idempotency_key)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_event_logs_company_id_id_unique
  ON public.financial_event_logs(company_id, id);

ALTER TABLE public.financial_event_logs
  DROP CONSTRAINT IF EXISTS financial_event_logs_outlet_fk;

ALTER TABLE public.financial_event_logs
  ADD CONSTRAINT financial_event_logs_outlet_fk
  FOREIGN KEY (company_id, outlet_id)
  REFERENCES public.outlets(company_id, id)
  ON DELETE SET NULL;

ALTER TABLE public.financial_event_logs
  DROP CONSTRAINT IF EXISTS financial_event_logs_journal_entry_fk;

ALTER TABLE public.financial_event_logs
  ADD CONSTRAINT financial_event_logs_journal_entry_fk
  FOREIGN KEY (company_id, journal_entry_id)
  REFERENCES public.journal_entries(company_id, id)
  ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_event_logs_company_idempotency_key_unique
  ON public.financial_event_logs(company_id, idempotency_key);

CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_event_logs_company_event_reference_unique
  ON public.financial_event_logs(company_id, source_module, event_type, reference_type, reference_id);

CREATE INDEX IF NOT EXISTS idx_financial_event_logs_company_status
  ON public.financial_event_logs(company_id, status);

CREATE INDEX IF NOT EXISTS idx_financial_event_logs_company_source_module
  ON public.financial_event_logs(company_id, source_module);

CREATE INDEX IF NOT EXISTS idx_financial_event_logs_company_outlet
  ON public.financial_event_logs(company_id, outlet_id);

CREATE INDEX IF NOT EXISTS idx_financial_event_logs_company_processed_at
  ON public.financial_event_logs(company_id, processed_at DESC);

DROP TRIGGER IF EXISTS update_financial_event_logs_updated_at ON public.financial_event_logs;
CREATE TRIGGER update_financial_event_logs_updated_at
  BEFORE UPDATE ON public.financial_event_logs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Row level security
-- ============================================================
ALTER TABLE public.financial_event_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view financial event logs in their company" ON public.financial_event_logs;
CREATE POLICY "Users can view financial event logs in their company"
  ON public.financial_event_logs
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert financial event logs in their company" ON public.financial_event_logs;
CREATE POLICY "Users can insert financial event logs in their company"
  ON public.financial_event_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update financial event logs in their company" ON public.financial_event_logs;
CREATE POLICY "Users can update financial event logs in their company"
  ON public.financial_event_logs
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete financial event logs in their company" ON public.financial_event_logs;
CREATE POLICY "Users can delete financial event logs in their company"
  ON public.financial_event_logs
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.financial_event_logs TO authenticated;
