-- Migration: Create account activity view
-- Created: 2026-05-19
-- Description:
--   - Creates a daily account activity summary view based on posted and reversed journals
--   - Aggregates debit, credit, and net movement by account, outlet, source module, and date
--   - Supports lightweight account drilldowns and dashboard summaries

-- ============================================================
-- 1. Account activity view
-- ============================================================
CREATE OR REPLACE VIEW public.account_activity_view
WITH (security_invoker = true) AS
SELECT
  je.company_id,
  jel.outlet_id,
  a.id AS account_id,
  a.code AS account_code,
  a.name AS account_name,
  a.type AS account_type,
  a.subtype AS account_subtype,
  a.normal_balance,
  je.entry_date,
  je.source_module,
  je.reference_type,
  COUNT(DISTINCT je.id) AS journal_entry_count,
  COUNT(jel.id) AS journal_line_count,
  COALESCE(SUM(jel.debit), 0::NUMERIC) AS total_debits,
  COALESCE(SUM(jel.credit), 0::NUMERIC) AS total_credits,
  CASE
    WHEN a.normal_balance = 'debit'::public.account_normal_balance
      THEN COALESCE(SUM(jel.debit), 0::NUMERIC) - COALESCE(SUM(jel.credit), 0::NUMERIC)
    ELSE
      COALESCE(SUM(jel.credit), 0::NUMERIC) - COALESCE(SUM(jel.debit), 0::NUMERIC)
  END AS net_activity
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
)
GROUP BY
  je.company_id,
  jel.outlet_id,
  a.id,
  a.code,
  a.name,
  a.type,
  a.subtype,
  a.normal_balance,
  je.entry_date,
  je.source_module,
  je.reference_type;

COMMENT ON VIEW public.account_activity_view IS
  'Daily account activity summary by company, outlet, account, source module, and reference type using posted and reversed journals.';

GRANT SELECT ON public.account_activity_view TO authenticated;
