-- Migration: Add unique constraint for company billing records
-- Created: 2026-01-30
-- Description: Ensures each company can have only one billing record

-- Add unique constraint on company_id to ensure one billing record per company
ALTER TABLE billing_records
ADD CONSTRAINT billing_records_company_id_unique UNIQUE (company_id);

-- Create index for faster lookups (if not exists)
CREATE INDEX IF NOT EXISTS idx_billing_company_id_unique ON billing_records(company_id);
