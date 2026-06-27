-- Migration: Create general ledger view
-- Created: 2026-05-19
-- Description:
--   - Creates a line-level general ledger view based on posted and reversed journals
--   - Exposes journal, line, account, outlet, and reversal linkage details
--   - Computes account-oriented running balances for drill-down reporting

-- ============================================================
-- 1. General ledger view
-- ============================================================
CREATE OR REPLACE VIEW public.general_ledger_view
WITH (security_invoker = true) AS
SELECT
  je.company_id,
  jel.outlet_id,
  je.id AS journal_entry_id,
  jel.id AS journal_entry_line_id,
  je.entry_date,
  je.source_module,
  je.reference_type,
  je.reference_id,
  je.memo,
  je.status,
  je.reversal_of_journal_entry_id,
  je.reversed_by_journal_entry_id,
  je.reversed_at,
  a.id AS account_id,
  a.code AS account_code,
  a.name AS account_name,
  a.type AS account_type,
  a.subtype AS account_subtype,
  a.normal_balance,
  jel.description AS line_description,
  jel.debit,
  jel.credit,
  CASE
    WHEN a.normal_balance = 'debit'::public.account_normal_balance
      THEN jel.debit - jel.credit
    ELSE
      jel.credit - jel.debit
  END AS balance_delta,
  SUM(
    CASE
      WHEN a.normal_balance = 'debit'::public.account_normal_balance
        THEN jel.debit - jel.credit
      ELSE
        jel.credit - jel.debit
    END
  ) OVER (
    PARTITION BY je.company_id, jel.outlet_id, a.id
    ORDER BY je.entry_date, je.created_at, jel.created_at, jel.id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS running_balance,
  je.created_at AS journal_created_at,
  jel.created_at AS line_created_at,
  je.created_by,
  jel.created_by AS line_created_by
FROM public.journal_entry_lines jel
INNER JOIN public.journal_entries je
  ON je.company_id = jel.company_id
  AND je.id = jel.journal_entry_id
INNER JOIN public.accounts a
  ON a.company_id = jel.company_id
  AND a.id = jel.account_id
WHERE je.status IN (
  'posted'::public.journal_entry_status,
  'reversed'::public.journal_entry_status
);

COMMENT ON VIEW public.general_ledger_view IS
  'Line-level general ledger by company, outlet, account, and journal entry using posted and reversed journals.';

GRANT SELECT ON public.general_ledger_view TO authenticated;
