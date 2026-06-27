-- Migration: Add journal posting scope
-- Created: 2026-05-18
-- Description:
--   - Adds explicit posting scope to journal_entries
--   - Distinguishes company-level entries from outlet-level entries
--   - Enforces outlet_id consistency with posting scope

-- ============================================================
-- 1. Posting scope enum
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'journal_posting_scope'
  ) THEN
    CREATE TYPE public.journal_posting_scope AS ENUM (
      'company',
      'outlet'
    );
  END IF;
END;
$$;

-- ============================================================
-- 2. Extend journal_entries
-- ============================================================
ALTER TABLE public.journal_entries
  ADD COLUMN IF NOT EXISTS posting_scope public.journal_posting_scope;

UPDATE public.journal_entries
SET posting_scope = CASE
  WHEN outlet_id IS NULL THEN 'company'::public.journal_posting_scope
  ELSE 'outlet'::public.journal_posting_scope
END
WHERE posting_scope IS NULL;

ALTER TABLE public.journal_entries
  ALTER COLUMN posting_scope SET NOT NULL;

ALTER TABLE public.journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_posting_scope_outlet_check;

ALTER TABLE public.journal_entries
  ADD CONSTRAINT journal_entries_posting_scope_outlet_check
  CHECK (
    (posting_scope = 'company'::public.journal_posting_scope AND outlet_id IS NULL)
    OR (posting_scope = 'outlet'::public.journal_posting_scope AND outlet_id IS NOT NULL)
  );

CREATE INDEX IF NOT EXISTS idx_journal_entries_company_posting_scope
  ON public.journal_entries(company_id, posting_scope);
