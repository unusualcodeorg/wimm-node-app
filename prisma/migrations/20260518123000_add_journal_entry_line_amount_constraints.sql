-- Migration: Add journal entry line amount constraints
-- Created: 2026-05-18
-- Description:
--   - Adds validation constraints for debit and credit values on journal_entry_lines
--   - Prevents negative values and invalid mixed/empty line amounts

-- ============================================================
-- 1. Debit and credit validation constraints
-- ============================================================
ALTER TABLE public.journal_entry_lines
  DROP CONSTRAINT IF EXISTS journal_entry_lines_debit_non_negative,
  DROP CONSTRAINT IF EXISTS journal_entry_lines_credit_non_negative,
  DROP CONSTRAINT IF EXISTS journal_entry_lines_single_sided_amount_check;

ALTER TABLE public.journal_entry_lines
  ADD CONSTRAINT journal_entry_lines_debit_non_negative
    CHECK (debit >= 0),
  ADD CONSTRAINT journal_entry_lines_credit_non_negative
    CHECK (credit >= 0),
  ADD CONSTRAINT journal_entry_lines_single_sided_amount_check
    CHECK (
      (debit > 0 AND credit = 0)
      OR (credit > 0 AND debit = 0)
    );
