-- Migration: Seed default accommodation liability and receivable accounts
-- Created: 2026-05-19
-- Description:
--   - Extends the default chart-of-accounts seed helper with missing accommodation receivable defaults
--   - Backfills the missing accommodation-focused account for existing companies

-- Note:
--   - Unearned Room Revenue (2100) and Advance Guest Deposits (2120) were
--     already included in the earlier seed helper.
--   - This migration closes the remaining gap on the accommodation receivable side.

-- ============================================================
-- 1. Update seed helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.seed_company_default_accounts(
  p_company_id BIGINT,
  p_created_by UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.accounts (
    company_id,
    code,
    name,
    type,
    subtype,
    normal_balance,
    is_system,
    is_active,
    allows_manual_entries,
    created_by
  )
  SELECT
    p_company_id,
    seed.code,
    seed.name,
    seed.type,
    seed.subtype,
    seed.normal_balance,
    TRUE,
    TRUE,
    TRUE,
    p_created_by
  FROM (
    VALUES
      ('1000', 'Cash on Hand', 'asset'::public.account_type, 'cash', 'debit'::public.account_normal_balance),
      ('1010', 'Main Bank Account', 'asset'::public.account_type, 'bank', 'debit'::public.account_normal_balance),
      ('1020', 'Mobile Money Clearing', 'asset'::public.account_type, 'cash_equivalent', 'debit'::public.account_normal_balance),
      ('1040', 'Undeposited Funds', 'asset'::public.account_type, 'cash_clearing', 'debit'::public.account_normal_balance),
      ('1050', 'Input VAT / Tax Recoverable', 'asset'::public.account_type, 'tax_recoverable', 'debit'::public.account_normal_balance),
      ('1100', 'Accounts Receivable', 'asset'::public.account_type, 'receivable', 'debit'::public.account_normal_balance),
      ('1110', 'Guest Receivables', 'asset'::public.account_type, 'receivable_guest', 'debit'::public.account_normal_balance),
      ('1120', 'Corporate Receivables', 'asset'::public.account_type, 'receivable_corporate', 'debit'::public.account_normal_balance),
      ('1130', 'OTA Receivables', 'asset'::public.account_type, 'receivable_ota', 'debit'::public.account_normal_balance),
      ('1200', 'Inventory Asset', 'asset'::public.account_type, 'inventory', 'debit'::public.account_normal_balance),
      ('1210', 'Food Inventory', 'asset'::public.account_type, 'inventory_food', 'debit'::public.account_normal_balance),
      ('1220', 'Beverage Inventory', 'asset'::public.account_type, 'inventory_beverage', 'debit'::public.account_normal_balance),
      ('1230', 'Room Amenities Inventory', 'asset'::public.account_type, 'inventory_amenities', 'debit'::public.account_normal_balance),
      ('2000', 'Accounts Payable', 'liability'::public.account_type, 'payable', 'credit'::public.account_normal_balance),
      ('2030', 'Taxes Payable', 'liability'::public.account_type, 'tax_payable', 'credit'::public.account_normal_balance),
      ('2040', 'VAT Payable', 'liability'::public.account_type, 'vat_payable', 'credit'::public.account_normal_balance),
      ('2100', 'Unearned Room Revenue', 'liability'::public.account_type, 'deferred_revenue', 'credit'::public.account_normal_balance),
      ('2120', 'Advance Guest Deposits', 'liability'::public.account_type, 'guest_deposits', 'credit'::public.account_normal_balance),
      ('2200', 'Booking.com Clearing', 'liability'::public.account_type, 'ota_clearing', 'credit'::public.account_normal_balance),
      ('2220', 'OTA Commission Payable', 'liability'::public.account_type, 'ota_commission', 'credit'::public.account_normal_balance),
      ('3000', 'Owner Equity', 'equity'::public.account_type, 'equity', 'credit'::public.account_normal_balance),
      ('4000', 'Room Revenue', 'revenue'::public.account_type, 'room_revenue', 'credit'::public.account_normal_balance),
      ('4100', 'Late Checkout Fees', 'revenue'::public.account_type, 'late_checkout', 'credit'::public.account_normal_balance),
      ('4120', 'Cleaning Fees', 'revenue'::public.account_type, 'cleaning_fees', 'credit'::public.account_normal_balance),
      ('4200', 'Dining Sales', 'revenue'::public.account_type, 'dining_sales', 'credit'::public.account_normal_balance),
      ('4210', 'Takeaway Sales', 'revenue'::public.account_type, 'takeaway_sales', 'credit'::public.account_normal_balance),
      ('4220', 'Beverage Sales', 'revenue'::public.account_type, 'beverage_sales', 'credit'::public.account_normal_balance),
      ('4230', 'Alcohol Sales', 'revenue'::public.account_type, 'alcohol_sales', 'credit'::public.account_normal_balance),
      ('5000', 'Food Cost', 'cogs'::public.account_type, 'food_cost', 'debit'::public.account_normal_balance),
      ('5010', 'Beverage Cost', 'cogs'::public.account_type, 'beverage_cost', 'debit'::public.account_normal_balance),
      ('5020', 'Alcohol Cost', 'cogs'::public.account_type, 'alcohol_cost', 'debit'::public.account_normal_balance),
      ('5100', 'Guest Amenities Cost', 'cogs'::public.account_type, 'guest_amenities_cost', 'debit'::public.account_normal_balance),
      ('6000', 'Salaries & Wages', 'expense'::public.account_type, 'payroll', 'debit'::public.account_normal_balance),
      ('6110', 'Electricity', 'expense'::public.account_type, 'utilities', 'debit'::public.account_normal_balance),
      ('6150', 'Property Maintenance', 'expense'::public.account_type, 'maintenance', 'debit'::public.account_normal_balance),
      ('6300', 'Booking.com Commission', 'expense'::public.account_type, 'ota_commission_expense', 'debit'::public.account_normal_balance),
      ('6320', 'Payment Processing Fees', 'expense'::public.account_type, 'processing_fees', 'debit'::public.account_normal_balance),
      ('6600', 'Wastage Expense', 'expense'::public.account_type, 'wastage', 'debit'::public.account_normal_balance),
      ('6610', 'Inventory Adjustment Loss', 'expense'::public.account_type, 'inventory_adjustment_loss', 'debit'::public.account_normal_balance)
  ) AS seed(code, name, type, subtype, normal_balance)
  ON CONFLICT (company_id, code) DO UPDATE
  SET
    name = EXCLUDED.name,
    type = EXCLUDED.type,
    subtype = EXCLUDED.subtype,
    normal_balance = EXCLUDED.normal_balance,
    is_system = EXCLUDED.is_system,
    is_active = EXCLUDED.is_active,
    allows_manual_entries = EXCLUDED.allows_manual_entries,
    updated_at = NOW();
END;
$$;

-- ============================================================
-- 2. Backfill existing companies
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
