-- Migration: Create tax configurations foundation
-- Created: 2026-05-18
-- Description:
--   - Creates tax application and tax rate status enums
--   - Creates company-owned tax_rates table for accounting and operational tax setup
--   - Adds account mapping support for output and input tax accounts
--   - Adds indexes, updated_at trigger, row-level security policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Tax enums
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'tax_application'
  ) THEN
    CREATE TYPE public.tax_application AS ENUM (
      'sales',
      'purchase',
      'both'
    );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'tax_rate_status'
  ) THEN
    CREATE TYPE public.tax_rate_status AS ENUM (
      'active',
      'inactive'
    );
  END IF;
END;
$$;

-- ============================================================
-- 2. Tax rates table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.tax_rates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  rate NUMERIC(8, 4) NOT NULL,
  application public.tax_application NOT NULL DEFAULT 'sales',
  status public.tax_rate_status NOT NULL DEFAULT 'active',
  output_account_id UUID,
  input_account_id UUID,
  description TEXT,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT tax_rates_code_not_blank CHECK (length(btrim(code)) > 0),
  CONSTRAINT tax_rates_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT tax_rates_rate_non_negative CHECK (rate >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_rates_company_id_id_unique
  ON public.tax_rates(company_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_rates_company_code_unique
  ON public.tax_rates(company_id, code);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_rates_company_lower_name_unique
  ON public.tax_rates(company_id, lower(name));

ALTER TABLE public.tax_rates
  DROP CONSTRAINT IF EXISTS tax_rates_output_account_fk;

ALTER TABLE public.tax_rates
  ADD CONSTRAINT tax_rates_output_account_fk
  FOREIGN KEY (company_id, output_account_id)
  REFERENCES public.accounts(company_id, id)
  ON DELETE SET NULL;

ALTER TABLE public.tax_rates
  DROP CONSTRAINT IF EXISTS tax_rates_input_account_fk;

ALTER TABLE public.tax_rates
  ADD CONSTRAINT tax_rates_input_account_fk
  FOREIGN KEY (company_id, input_account_id)
  REFERENCES public.accounts(company_id, id)
  ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tax_rates_company_status
  ON public.tax_rates(company_id, status);

CREATE INDEX IF NOT EXISTS idx_tax_rates_company_application
  ON public.tax_rates(company_id, application);

CREATE INDEX IF NOT EXISTS idx_tax_rates_company_output_account
  ON public.tax_rates(company_id, output_account_id);

CREATE INDEX IF NOT EXISTS idx_tax_rates_company_input_account
  ON public.tax_rates(company_id, input_account_id);

DROP TRIGGER IF EXISTS update_tax_rates_updated_at ON public.tax_rates;
CREATE TRIGGER update_tax_rates_updated_at
  BEFORE UPDATE ON public.tax_rates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Row level security
-- ============================================================
ALTER TABLE public.tax_rates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view tax rates in their company" ON public.tax_rates;
CREATE POLICY "Users can view tax rates in their company"
  ON public.tax_rates
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert tax rates in their company" ON public.tax_rates;
CREATE POLICY "Users can insert tax rates in their company"
  ON public.tax_rates
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update tax rates in their company" ON public.tax_rates;
CREATE POLICY "Users can update tax rates in their company"
  ON public.tax_rates
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete tax rates in their company" ON public.tax_rates;
CREATE POLICY "Users can delete tax rates in their company"
  ON public.tax_rates
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tax_rates TO authenticated;
