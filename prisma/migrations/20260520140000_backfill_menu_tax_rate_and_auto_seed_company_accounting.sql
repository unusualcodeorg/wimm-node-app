-- ============================================================
-- Migration: Backfill menu tax rate and auto-seed company accounting
-- Created: 2026-05-20
-- Description:
--   - Sets all existing menu_items.tax_rate values to 18.00
--   - Makes 18.00 the default tax_rate for future menu items
--   - Automatically seeds company-scoped accounting defaults for new companies
--   - Re-runs the current seed helper for existing companies safely
--
-- Notes:
--   - POS accounting logic already interprets tax_rate as a percentage.
--     Example: 18 means 18%, not 0.18.
--   - Company accounting defaults are company-scoped, so new outlets inherit
--     them through their company and do not require separate chart seeding.

-- ============================================================
-- 1. Menu item tax rate standardization
-- ============================================================
-- ALTER TABLE public.menu_items
--   ALTER COLUMN tax_rate SET DEFAULT 18.00;

UPDATE public.menu_items
SET tax_rate = 18.00
WHERE tax_rate IS DISTINCT FROM 18.00;

-- ============================================================
-- 2. Auto-seed accounting defaults for new companies
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_company_accounting_setup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.seed_company_default_accounts(NEW.id, NEW.created_by);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS seed_company_default_accounts_after_insert
  ON public.companies;

CREATE TRIGGER seed_company_default_accounts_after_insert
  AFTER INSERT ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_company_accounting_setup();

-- ============================================================
-- 3. Safe backfill for existing companies
-- ============================================================
DO $$
DECLARE
  company_row RECORD;
BEGIN
  FOR company_row IN
    SELECT c.id, c.created_by
    FROM public.companies c
  LOOP
    PERFORM public.seed_company_default_accounts(
      company_row.id,
      company_row.created_by
    );
  END LOOP;
END;
$$;
