-- Migration: Create trial balance view
-- Created: 2026-05-19
-- Description:
--   - Creates an accounting trial balance view based on posted and reversed journals
--   - Preserves accounts with no movement so the full chart can be reported
--   - Includes outlet dimension for later outlet-filtered reporting

-- ============================================================
-- 1. Trial balance view
-- ============================================================
CREATE OR REPLACE VIEW public.trial_balance_view
WITH (security_invoker = true) AS
SELECT
  a.company_id,
  jel.outlet_id,
  a.id AS account_id,
  a.code AS account_code,
  a.name AS account_name,
  a.type AS account_type,
  a.subtype AS account_subtype,
  a.normal_balance,
  a.is_active,
  COALESCE(SUM(jel.debit), 0::NUMERIC) AS total_debits,
  COALESCE(SUM(jel.credit), 0::NUMERIC) AS total_credits,
  CASE
    WHEN a.normal_balance = 'debit'::public.account_normal_balance
      THEN COALESCE(SUM(jel.debit), 0::NUMERIC) - COALESCE(SUM(jel.credit), 0::NUMERIC)
    ELSE
      COALESCE(SUM(jel.credit), 0::NUMERIC) - COALESCE(SUM(jel.debit), 0::NUMERIC)
  END AS closing_balance,
  MIN(je.entry_date) AS first_entry_date,
  MAX(je.entry_date) AS last_entry_date,
  COUNT(DISTINCT je.id) AS journal_entry_count
FROM public.accounts a
LEFT JOIN public.journal_entry_lines jel
  ON jel.company_id = a.company_id
  AND jel.account_id = a.id
LEFT JOIN public.journal_entries je
  ON je.company_id = jel.company_id
  AND je.id = jel.journal_entry_id
  AND je.status IN (
    'posted'::public.journal_entry_status,
    'reversed'::public.journal_entry_status
  )
WHERE je.id IS NOT NULL OR jel.id IS NULL
GROUP BY
  a.company_id,
  jel.outlet_id,
  a.id,
  a.code,
  a.name,
  a.type,
  a.subtype,
  a.normal_balance,
  a.is_active;

COMMENT ON VIEW public.trial_balance_view IS
  'Aggregated trial balance by company, account, and outlet using posted and reversed journal entries.';

GRANT SELECT ON public.trial_balance_view TO authenticated;
