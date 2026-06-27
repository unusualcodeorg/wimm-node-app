-- Migration: Add journal balance validation
-- Created: 2026-05-18
-- Description:
--   - Adds helper function to validate journal entry line balance
--   - Prevents journal entries from being marked as posted unless debits equal credits
--   - Requires at least one journal line before posting

-- ============================================================
-- 1. Journal balance validation helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.validate_journal_entry_can_post(
  p_company_id BIGINT,
  p_journal_entry_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_line_count INTEGER;
  v_total_debit NUMERIC(14, 2);
  v_total_credit NUMERIC(14, 2);
BEGIN
  SELECT
    COUNT(*),
    COALESCE(SUM(jel.debit), 0),
    COALESCE(SUM(jel.credit), 0)
  INTO v_line_count, v_total_debit, v_total_credit
  FROM public.journal_entry_lines jel
  WHERE jel.company_id = p_company_id
    AND jel.journal_entry_id = p_journal_entry_id;

  IF v_line_count = 0 THEN
    RAISE EXCEPTION 'Journal entry must contain at least one line before posting.';
  END IF;

  IF v_total_debit <> v_total_credit THEN
    RAISE EXCEPTION
      'Journal entry is unbalanced. Total debit (%s) must equal total credit (%s).',
      v_total_debit,
      v_total_credit;
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_journal_entry_can_post(BIGINT, UUID) TO authenticated;

-- ============================================================
-- 2. Posting validation trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_posted_journal_entry_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'posted'::public.journal_entry_status
     AND (
       TG_OP = 'INSERT'
       OR OLD.status IS DISTINCT FROM NEW.status
       OR NEW.company_id IS DISTINCT FROM OLD.company_id
       OR NEW.id IS DISTINCT FROM OLD.id
     ) THEN
    PERFORM public.validate_journal_entry_can_post(NEW.company_id, NEW.id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_journal_entries_before_posting ON public.journal_entries;
CREATE TRIGGER validate_journal_entries_before_posting
  BEFORE INSERT OR UPDATE ON public.journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_posted_journal_entry_balance();
