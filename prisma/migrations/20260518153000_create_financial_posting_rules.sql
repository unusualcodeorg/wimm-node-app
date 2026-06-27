-- Migration: Create financial posting rules
-- Created: 2026-05-18
-- Description:
--   - Creates posting rule direction and status enums
--   - Creates company-owned financial_posting_rules table
--   - Supports configurable source-module and event-level account mappings for automation
--   - Adds indexes, updated_at trigger, row-level security policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Posting rule enums
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'financial_posting_rule_direction'
  ) THEN
    CREATE TYPE public.financial_posting_rule_direction AS ENUM (
      'debit',
      'credit'
    );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'financial_posting_rule_status'
  ) THEN
    CREATE TYPE public.financial_posting_rule_status AS ENUM (
      'active',
      'inactive'
    );
  END IF;
END;
$$;

-- ============================================================
-- 2. Financial posting rules table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.financial_posting_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID,
  source_module public.journal_source_module NOT NULL,
  event_type TEXT NOT NULL,
  reference_type TEXT,
  rule_name TEXT NOT NULL,
  direction public.financial_posting_rule_direction NOT NULL,
  account_id UUID NOT NULL,
  tax_rate_id UUID,
  payment_method_id INTEGER,
  priority INTEGER NOT NULL DEFAULT 100,
  status public.financial_posting_rule_status NOT NULL DEFAULT 'active',
  metadata JSONB,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT financial_posting_rules_event_type_not_blank CHECK (length(btrim(event_type)) > 0),
  CONSTRAINT financial_posting_rules_rule_name_not_blank CHECK (length(btrim(rule_name)) > 0),
  CONSTRAINT financial_posting_rules_priority_non_negative CHECK (priority >= 0),
  CONSTRAINT financial_posting_rules_reference_type_not_blank CHECK (
    reference_type IS NULL OR length(btrim(reference_type)) > 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_financial_posting_rules_company_id_id_unique
  ON public.financial_posting_rules(company_id, id);

ALTER TABLE public.financial_posting_rules
  DROP CONSTRAINT IF EXISTS financial_posting_rules_outlet_fk;

ALTER TABLE public.financial_posting_rules
  ADD CONSTRAINT financial_posting_rules_outlet_fk
  FOREIGN KEY (company_id, outlet_id)
  REFERENCES public.outlets(company_id, id)
  ON DELETE CASCADE;

ALTER TABLE public.financial_posting_rules
  DROP CONSTRAINT IF EXISTS financial_posting_rules_account_fk;

ALTER TABLE public.financial_posting_rules
  ADD CONSTRAINT financial_posting_rules_account_fk
  FOREIGN KEY (company_id, account_id)
  REFERENCES public.accounts(company_id, id)
  ON DELETE RESTRICT;

ALTER TABLE public.financial_posting_rules
  DROP CONSTRAINT IF EXISTS financial_posting_rules_tax_rate_fk;

ALTER TABLE public.financial_posting_rules
  ADD CONSTRAINT financial_posting_rules_tax_rate_fk
  FOREIGN KEY (company_id, tax_rate_id)
  REFERENCES public.tax_rates(company_id, id)
  ON DELETE SET NULL;

ALTER TABLE public.financial_posting_rules
  DROP CONSTRAINT IF EXISTS financial_posting_rules_payment_method_fk;

ALTER TABLE public.financial_posting_rules
  ADD CONSTRAINT financial_posting_rules_payment_method_fk
  FOREIGN KEY (payment_method_id)
  REFERENCES public.payment_methods(id)
  ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_financial_posting_rules_company_module_event
  ON public.financial_posting_rules(company_id, source_module, event_type, status, priority);

CREATE INDEX IF NOT EXISTS idx_financial_posting_rules_company_outlet
  ON public.financial_posting_rules(company_id, outlet_id);

CREATE INDEX IF NOT EXISTS idx_financial_posting_rules_company_account
  ON public.financial_posting_rules(company_id, account_id);

CREATE INDEX IF NOT EXISTS idx_financial_posting_rules_company_tax_rate
  ON public.financial_posting_rules(company_id, tax_rate_id);

CREATE INDEX IF NOT EXISTS idx_financial_posting_rules_payment_method
  ON public.financial_posting_rules(payment_method_id);

DROP TRIGGER IF EXISTS update_financial_posting_rules_updated_at
  ON public.financial_posting_rules;
CREATE TRIGGER update_financial_posting_rules_updated_at
  BEFORE UPDATE ON public.financial_posting_rules
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Row level security
-- ============================================================
ALTER TABLE public.financial_posting_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view financial posting rules in their company" ON public.financial_posting_rules;
CREATE POLICY "Users can view financial posting rules in their company"
  ON public.financial_posting_rules
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert financial posting rules in their company" ON public.financial_posting_rules;
CREATE POLICY "Users can insert financial posting rules in their company"
  ON public.financial_posting_rules
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update financial posting rules in their company" ON public.financial_posting_rules;
CREATE POLICY "Users can update financial posting rules in their company"
  ON public.financial_posting_rules
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete financial posting rules in their company" ON public.financial_posting_rules;
CREATE POLICY "Users can delete financial posting rules in their company"
  ON public.financial_posting_rules
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.financial_posting_rules TO authenticated;
