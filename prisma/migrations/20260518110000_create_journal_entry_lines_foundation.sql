-- Migration: Create journal entry lines foundation
-- Created: 2026-05-18
-- Description:
--   - Creates company-owned journal_entry_lines table
--   - Links journal lines to journal entries and chart-of-accounts records
--   - Adds indexes, row-level security policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Journal entry lines table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.journal_entry_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  journal_entry_id UUID NOT NULL,
  account_id UUID NOT NULL,
  outlet_id UUID,
  debit NUMERIC(14, 2) NOT NULL DEFAULT 0,
  credit NUMERIC(14, 2) NOT NULL DEFAULT 0,
  description TEXT,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.journal_entry_lines
  DROP CONSTRAINT IF EXISTS journal_entry_lines_journal_entry_fk;

ALTER TABLE public.journal_entry_lines
  ADD CONSTRAINT journal_entry_lines_journal_entry_fk
  FOREIGN KEY (company_id, journal_entry_id)
  REFERENCES public.journal_entries(company_id, id)
  ON DELETE CASCADE;

ALTER TABLE public.journal_entry_lines
  DROP CONSTRAINT IF EXISTS journal_entry_lines_account_fk;

ALTER TABLE public.journal_entry_lines
  ADD CONSTRAINT journal_entry_lines_account_fk
  FOREIGN KEY (company_id, account_id)
  REFERENCES public.accounts(company_id, id)
  ON DELETE RESTRICT;

ALTER TABLE public.journal_entry_lines
  DROP CONSTRAINT IF EXISTS journal_entry_lines_outlet_fk;

ALTER TABLE public.journal_entry_lines
  ADD CONSTRAINT journal_entry_lines_outlet_fk
  FOREIGN KEY (company_id, outlet_id)
  REFERENCES public.outlets(company_id, id)
  ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_company_journal_entry
  ON public.journal_entry_lines(company_id, journal_entry_id);

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_company_account
  ON public.journal_entry_lines(company_id, account_id);

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_company_outlet
  ON public.journal_entry_lines(company_id, outlet_id);

CREATE INDEX IF NOT EXISTS idx_journal_entry_lines_created_by
  ON public.journal_entry_lines(created_by);

-- ============================================================
-- 2. Row level security
-- ============================================================
ALTER TABLE public.journal_entry_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view journal entry lines in their company" ON public.journal_entry_lines;
CREATE POLICY "Users can view journal entry lines in their company"
  ON public.journal_entry_lines
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert journal entry lines in their company" ON public.journal_entry_lines;
CREATE POLICY "Users can insert journal entry lines in their company"
  ON public.journal_entry_lines
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update journal entry lines in their company" ON public.journal_entry_lines;
CREATE POLICY "Users can update journal entry lines in their company"
  ON public.journal_entry_lines
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete journal entry lines in their company" ON public.journal_entry_lines;
CREATE POLICY "Users can delete journal entry lines in their company"
  ON public.journal_entry_lines
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 3. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.journal_entry_lines TO authenticated;
