-- Migration: Move billing records from outlet-based to company-based
-- Created: 2026-01-30
-- Description: Transforms billing_records to be associated with companies instead of outlets
-- This allows all users in a company to access subscription details

-- Step 1: Add company_id column to billing_records
ALTER TABLE billing_records
ADD COLUMN company_id BIGINT;

-- Step 2: Populate company_id from existing outlet_id relationships
UPDATE billing_records br
SET company_id = o.company_id
FROM outlets o
WHERE br.outlet_id = o.id;

-- Step 3: Make company_id NOT NULL after populating data
ALTER TABLE billing_records
ALTER COLUMN company_id SET NOT NULL;

-- Step 4: Add foreign key constraint
ALTER TABLE billing_records
ADD CONSTRAINT billing_records_company_id_fkey
FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;

-- Step 5: Drop the old outlet_id constraint and column
ALTER TABLE billing_records
DROP CONSTRAINT IF EXISTS billing_records_outlet_id_fkey;

-- Drop the old index
DROP INDEX IF EXISTS idx_billing_outlet_id;

-- Make outlet_id nullable (for backwards compatibility during transition)
ALTER TABLE billing_records
ALTER COLUMN outlet_id DROP NOT NULL;

-- Step 6: Create new index on company_id
CREATE INDEX idx_billing_company_id ON billing_records(company_id);

-- Step 7: Create index on stripe IDs for faster lookups
CREATE INDEX idx_billing_stripe_customer_id ON billing_records(stripe_customer_id);
CREATE INDEX idx_billing_stripe_subscription_id ON billing_records(stripe_subscription_id);

-- Step 8: Update RLS policies to use company_id instead of outlet_id

-- Drop old policies
DROP POLICY IF EXISTS "Super users can view billing for their outlets" ON billing_records;
DROP POLICY IF EXISTS "Super users can manage billing" ON billing_records;

-- Create new policies for company-based access
CREATE POLICY "Users can view billing for their company"
  ON billing_records FOR SELECT
  USING (company_id IN (
    SELECT company_id FROM users WHERE id = auth.uid()
  ));

CREATE POLICY "Super users can manage billing for their company"
  ON billing_records FOR ALL
  USING (company_id IN (
    SELECT company_id FROM users WHERE id = auth.uid() AND role = 'super'
  ));

-- Step 9: Add additional billing fields for better tracking
ALTER TABLE billing_records
ADD COLUMN current_period_start TIMESTAMPTZ,
ADD COLUMN current_period_end TIMESTAMPTZ,
ADD COLUMN cancel_at_period_end BOOLEAN DEFAULT false,
ADD COLUMN canceled_at TIMESTAMPTZ;

-- Step 10: Create a function to get active subscription for a company
CREATE OR REPLACE FUNCTION get_company_subscription(p_company_id BIGINT)
RETURNS TABLE (
  id UUID,
  package subscription_package,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  trial_ends_at TIMESTAMPTZ,
  subscription_status subscription_status,
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancel_at_period_end BOOLEAN,
  canceled_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    br.id,
    br.package,
    br.stripe_customer_id,
    br.stripe_subscription_id,
    br.trial_ends_at,
    br.subscription_status,
    br.current_period_start,
    br.current_period_end,
    br.cancel_at_period_end,
    br.canceled_at
  FROM billing_records br
  WHERE br.company_id = p_company_id
  ORDER BY br.created_at DESC
  LIMIT 1;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_company_subscription(BIGINT) TO authenticated;
