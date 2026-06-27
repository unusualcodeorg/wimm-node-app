-- Migration: Create payment method account mappings
-- Created: 2026-05-18
-- Description:
--   - Adds company-owned payment method to account mapping support
--   - Keeps payment_methods global while allowing each company to map methods to its own accounts

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Payment method account mappings table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.payment_method_account_mappings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  payment_method_id INTEGER NOT NULL REFERENCES public.payment_methods(id) ON DELETE CASCADE,
  account_id UUID NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT payment_method_account_mappings_company_payment_method_unique
    UNIQUE (company_id, payment_method_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_method_account_mappings_company_id_id_unique
  ON public.payment_method_account_mappings(company_id, id);

ALTER TABLE public.payment_method_account_mappings
  DROP CONSTRAINT IF EXISTS payment_method_account_mappings_account_fk;

ALTER TABLE public.payment_method_account_mappings
  ADD CONSTRAINT payment_method_account_mappings_account_fk
  FOREIGN KEY (company_id, account_id)
  REFERENCES public.accounts(company_id, id)
  ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_payment_method_account_mappings_company_account
  ON public.payment_method_account_mappings(company_id, account_id);

CREATE INDEX IF NOT EXISTS idx_payment_method_account_mappings_payment_method
  ON public.payment_method_account_mappings(payment_method_id);

DROP TRIGGER IF EXISTS update_payment_method_account_mappings_updated_at
  ON public.payment_method_account_mappings;
CREATE TRIGGER update_payment_method_account_mappings_updated_at
  BEFORE UPDATE ON public.payment_method_account_mappings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 2. Row level security
-- ============================================================
ALTER TABLE public.payment_method_account_mappings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view payment method mappings in their company" ON public.payment_method_account_mappings;
CREATE POLICY "Users can view payment method mappings in their company"
  ON public.payment_method_account_mappings
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert payment method mappings in their company" ON public.payment_method_account_mappings;
CREATE POLICY "Users can insert payment method mappings in their company"
  ON public.payment_method_account_mappings
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update payment method mappings in their company" ON public.payment_method_account_mappings;
CREATE POLICY "Users can update payment method mappings in their company"
  ON public.payment_method_account_mappings
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete payment method mappings in their company" ON public.payment_method_account_mappings;
CREATE POLICY "Users can delete payment method mappings in their company"
  ON public.payment_method_account_mappings
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 3. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_method_account_mappings TO authenticated;
