-- Migration: Define outlet-filtered financial reporting behavior
-- Created: 2026-05-19
-- Description:
--   - Defines reusable helpers for outlet-scoped financial report filtering
--   - Establishes the rule that company-scoped entries appear only in company-wide reports
--   - Prevents duplicated company-level balances across outlet-specific report totals

-- Reporting rule:
--   1. A company-wide report (no outlet filter) includes all entries.
--   2. An outlet-filtered report includes only entries posted to that outlet.
--   3. Company-scoped entries (outlet_id IS NULL / posting_scope = company)
--      remain visible only in company-wide reporting, not outlet-specific views.

-- ============================================================
-- 1. Outlet-filter matching helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.financial_report_matches_outlet(
  p_report_outlet_id UUID,
  p_entry_outlet_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_report_outlet_id IS NULL THEN TRUE
    ELSE p_entry_outlet_id = p_report_outlet_id
  END
$$;

COMMENT ON FUNCTION public.financial_report_matches_outlet(UUID, UUID) IS
  'Returns true when a financial report should include a row for the selected outlet filter. Company-wide reports include all rows; outlet-filtered reports include only rows posted to that outlet.';

GRANT EXECUTE ON FUNCTION public.financial_report_matches_outlet(UUID, UUID) TO authenticated;

-- ============================================================
-- 2. Optional normalized report scope label helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.financial_report_scope_label(
  p_entry_outlet_id UUID
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_entry_outlet_id IS NULL THEN 'company'
    ELSE 'outlet'
  END
$$;

COMMENT ON FUNCTION public.financial_report_scope_label(UUID) IS
  'Returns company or outlet to describe the reporting scope of a financial row.';

GRANT EXECUTE ON FUNCTION public.financial_report_scope_label(UUID) TO authenticated;
