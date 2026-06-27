-- Migration: Create accounting periods foundation
-- Created: 2026-05-18
-- Description:
--   - Creates accounting period status enum
--   - Creates company-owned accounting_periods table
--   - Adds indexes, updated_at trigger, row-level security policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Accounting period enums
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'accounting_period_status'
  ) THEN
    CREATE TYPE public.accounting_period_status AS ENUM (
      'open',
      'closed'
    );
  END IF;
END;
$$;

-- ============================================================
-- 2. Accounting periods table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accounting_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID,
  name TEXT NOT NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  status public.accounting_period_status NOT NULL DEFAULT 'open',
  closed_at TIMESTAMPTZ,
  closed_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  notes TEXT,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accounting_periods_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT accounting_periods_date_range_check CHECK (period_end >= period_start),
  CONSTRAINT accounting_periods_closed_fields_check CHECK (
    (status = 'open' AND closed_at IS NULL)
    OR (status = 'closed' AND closed_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_accounting_periods_company_id_id_unique
  ON public.accounting_periods(company_id, id);

ALTER TABLE public.accounting_periods
  DROP CONSTRAINT IF EXISTS accounting_periods_outlet_fk;

ALTER TABLE public.accounting_periods
  ADD CONSTRAINT accounting_periods_outlet_fk
  FOREIGN KEY (company_id, outlet_id)
  REFERENCES public.outlets(company_id, id)
  ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_accounting_periods_company_outlet_name_unique
  ON public.accounting_periods(company_id, COALESCE(outlet_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name));

CREATE UNIQUE INDEX IF NOT EXISTS idx_accounting_periods_company_outlet_dates_unique
  ON public.accounting_periods(company_id, COALESCE(outlet_id, '00000000-0000-0000-0000-000000000000'::uuid), period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_accounting_periods_company_status
  ON public.accounting_periods(company_id, status);

CREATE INDEX IF NOT EXISTS idx_accounting_periods_company_outlet
  ON public.accounting_periods(company_id, outlet_id);

CREATE INDEX IF NOT EXISTS idx_accounting_periods_company_dates
  ON public.accounting_periods(company_id, period_start DESC, period_end DESC);

DROP TRIGGER IF EXISTS update_accounting_periods_updated_at ON public.accounting_periods;
CREATE TRIGGER update_accounting_periods_updated_at
  BEFORE UPDATE ON public.accounting_periods
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Row level security
-- ============================================================
ALTER TABLE public.accounting_periods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view accounting periods in their company" ON public.accounting_periods;
CREATE POLICY "Users can view accounting periods in their company"
  ON public.accounting_periods
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert accounting periods in their company" ON public.accounting_periods;
CREATE POLICY "Users can insert accounting periods in their company"
  ON public.accounting_periods
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update accounting periods in their company" ON public.accounting_periods;
CREATE POLICY "Users can update accounting periods in their company"
  ON public.accounting_periods
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete accounting periods in their company" ON public.accounting_periods;
CREATE POLICY "Users can delete accounting periods in their company"
  ON public.accounting_periods
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.accounting_periods TO authenticated;
