-- Migration: Create accounts foundation
-- Created: 2026-05-18
-- Description:
--   - Creates accounting account type and normal balance enums
--   - Creates company-owned accounts table for chart of accounts setup
--   - Adds indexes, updated_at trigger, RLS policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Accounting enums
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'account_type'
  ) THEN
    CREATE TYPE public.account_type AS ENUM (
      'asset',
      'liability',
      'equity',
      'revenue',
      'cogs',
      'expense',
      'other_income',
      'other_expense'
    );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'account_normal_balance'
  ) THEN
    CREATE TYPE public.account_normal_balance AS ENUM ('debit', 'credit');
  END IF;
END;
$$;

-- ============================================================
-- 2. Accounts table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  code VARCHAR(20) NOT NULL,
  name TEXT NOT NULL,
  type public.account_type NOT NULL,
  subtype TEXT,
  parent_account_id UUID,
  normal_balance public.account_normal_balance NOT NULL,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  allows_manual_entries BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accounts_code_not_blank CHECK (length(btrim(code)) > 0),
  CONSTRAINT accounts_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT accounts_parent_not_self CHECK (id IS DISTINCT FROM parent_account_id),
  CONSTRAINT accounts_company_code_unique UNIQUE (company_id, code)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_company_id_id_unique
  ON public.accounts(company_id, id);

ALTER TABLE public.accounts
  DROP CONSTRAINT IF EXISTS accounts_parent_account_fk;

ALTER TABLE public.accounts
  ADD CONSTRAINT accounts_parent_account_fk
  FOREIGN KEY (company_id, parent_account_id)
  REFERENCES public.accounts(company_id, id)
  ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_company_lower_name_unique
  ON public.accounts(company_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_accounts_company_type_active
  ON public.accounts(company_id, type, is_active);

CREATE INDEX IF NOT EXISTS idx_accounts_company_parent
  ON public.accounts(company_id, parent_account_id);

CREATE INDEX IF NOT EXISTS idx_accounts_company_created_at
  ON public.accounts(company_id, created_at DESC);

DROP TRIGGER IF EXISTS update_accounts_updated_at ON public.accounts;
CREATE TRIGGER update_accounts_updated_at
  BEFORE UPDATE ON public.accounts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Row level security
-- ============================================================
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view accounts in their company" ON public.accounts;
CREATE POLICY "Users can view accounts in their company"
  ON public.accounts
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert accounts in their company" ON public.accounts;
CREATE POLICY "Users can insert accounts in their company"
  ON public.accounts
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update accounts in their company" ON public.accounts;
CREATE POLICY "Users can update accounts in their company"
  ON public.accounts
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete accounts in their company" ON public.accounts;
CREATE POLICY "Users can delete accounts in their company"
  ON public.accounts
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.accounts TO authenticated;
