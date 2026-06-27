-- Migration: Create journal entries foundation
-- Created: 2026-05-18
-- Description:
--   - Creates journal source module and journal entry status enums
--   - Creates company-owned journal_entries table
--   - Adds indexes, updated_at trigger, RLS policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Journal enums
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'journal_source_module'
  ) THEN
    CREATE TYPE public.journal_source_module AS ENUM (
      'sales',
      'inventory',
      'accommodation',
      'booking_com',
      'manual',
      'system'
    );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'journal_entry_status'
  ) THEN
    CREATE TYPE public.journal_entry_status AS ENUM (
      'draft',
      'posted',
      'voided',
      'reversed'
    );
  END IF;
END;
$$;

-- ============================================================
-- 2. Journal entries table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.journal_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID,
  reference_type TEXT,
  reference_id UUID,
  source_module public.journal_source_module NOT NULL DEFAULT 'manual',
  entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
  memo TEXT,
  status public.journal_entry_status NOT NULL DEFAULT 'draft',
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT journal_entries_reference_type_not_blank CHECK (
    reference_type IS NULL OR length(btrim(reference_type)) > 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_company_id_id_unique
  ON public.journal_entries(company_id, id);

ALTER TABLE public.journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_outlet_fk;

ALTER TABLE public.journal_entries
  ADD CONSTRAINT journal_entries_outlet_fk
  FOREIGN KEY (company_id, outlet_id)
  REFERENCES public.outlets(company_id, id)
  ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_journal_entries_company_entry_date
  ON public.journal_entries(company_id, entry_date DESC);

CREATE INDEX IF NOT EXISTS idx_journal_entries_company_outlet
  ON public.journal_entries(company_id, outlet_id);

CREATE INDEX IF NOT EXISTS idx_journal_entries_company_status
  ON public.journal_entries(company_id, status);

CREATE INDEX IF NOT EXISTS idx_journal_entries_company_source_module
  ON public.journal_entries(company_id, source_module);

CREATE INDEX IF NOT EXISTS idx_journal_entries_company_reference
  ON public.journal_entries(company_id, reference_type, reference_id);

CREATE INDEX IF NOT EXISTS idx_journal_entries_created_by
  ON public.journal_entries(created_by);

DROP TRIGGER IF EXISTS update_journal_entries_updated_at ON public.journal_entries;
CREATE TRIGGER update_journal_entries_updated_at
  BEFORE UPDATE ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Row level security
-- ============================================================
ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view journal entries in their company" ON public.journal_entries;
CREATE POLICY "Users can view journal entries in their company"
  ON public.journal_entries
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert journal entries in their company" ON public.journal_entries;
CREATE POLICY "Users can insert journal entries in their company"
  ON public.journal_entries
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update journal entries in their company" ON public.journal_entries;
CREATE POLICY "Users can update journal entries in their company"
  ON public.journal_entries
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete journal entries in their company" ON public.journal_entries;
CREATE POLICY "Users can delete journal entries in their company"
  ON public.journal_entries
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.journal_entries TO authenticated;
