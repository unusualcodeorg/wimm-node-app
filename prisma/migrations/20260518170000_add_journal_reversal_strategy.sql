-- Migration: Add journal reversal strategy
-- Created: 2026-05-18
-- Description:
--   - Adds explicit reversal linkage fields to journal_entries
--   - Enforces one-to-one reversal relationships within the same company
--   - Requires reversal metadata when an entry is marked as reversed

-- ============================================================
-- 1. Extend journal entries with reversal metadata
-- ============================================================
ALTER TABLE public.journal_entries
  ADD COLUMN IF NOT EXISTS reversal_of_journal_entry_id UUID,
  ADD COLUMN IF NOT EXISTS reversed_by_journal_entry_id UUID,
  ADD COLUMN IF NOT EXISTS reversed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reversed_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE public.journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_reversal_of_fk;

ALTER TABLE public.journal_entries
  ADD CONSTRAINT journal_entries_reversal_of_fk
  FOREIGN KEY (company_id, reversal_of_journal_entry_id)
  REFERENCES public.journal_entries(company_id, id)
  ON DELETE RESTRICT;

ALTER TABLE public.journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_reversed_by_entry_fk;

ALTER TABLE public.journal_entries
  ADD CONSTRAINT journal_entries_reversed_by_entry_fk
  FOREIGN KEY (company_id, reversed_by_journal_entry_id)
  REFERENCES public.journal_entries(company_id, id)
  ON DELETE RESTRICT;

ALTER TABLE public.journal_entries
  DROP CONSTRAINT IF EXISTS journal_entries_reversal_self_check;

ALTER TABLE public.journal_entries
  ADD CONSTRAINT journal_entries_reversal_self_check
  CHECK (
    id IS DISTINCT FROM reversal_of_journal_entry_id
    AND id IS DISTINCT FROM reversed_by_journal_entry_id
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_company_reversal_of_unique
  ON public.journal_entries(company_id, reversal_of_journal_entry_id)
  WHERE reversal_of_journal_entry_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_journal_entries_company_reversed_by_entry_unique
  ON public.journal_entries(company_id, reversed_by_journal_entry_id)
  WHERE reversed_by_journal_entry_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_journal_entries_company_reversed_at
  ON public.journal_entries(company_id, reversed_at DESC);

-- ============================================================
-- 2. Reversal metadata enforcement
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_journal_reversal_metadata()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'reversed'::public.journal_entry_status THEN
    IF NEW.reversed_by_journal_entry_id IS NULL THEN
      RAISE EXCEPTION
        'Reversed journal entries must reference the reversing journal entry.';
    END IF;

    IF NEW.reversed_at IS NULL THEN
      NEW.reversed_at := NOW();
    END IF;

    IF NEW.reversed_by IS NULL THEN
      NEW.reversed_by := auth.uid();
    END IF;
  ELSE
    NEW.reversed_at := NULL;
    NEW.reversed_by := NULL;

    IF NEW.reversal_of_journal_entry_id IS NULL THEN
      NEW.reversed_by_journal_entry_id := NULL;
    END IF;
  END IF;

  IF NEW.reversal_of_journal_entry_id IS NOT NULL
     AND NEW.status <> 'posted'::public.journal_entry_status THEN
    RAISE EXCEPTION
      'Reversal journal entries must be created as posted entries.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_journal_reversal_metadata_before_write
  ON public.journal_entries;
CREATE TRIGGER enforce_journal_reversal_metadata_before_write
  BEFORE INSERT OR UPDATE ON public.journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_journal_reversal_metadata();
