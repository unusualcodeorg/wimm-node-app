-- Migration: Add Supported Countries and Schema Updates
-- Created: 2026-01-23
-- Description: Creates supported_countries table, updates companies.country to country_id,
--              adds day_open to outlets, and removes company_id from users

-- ============================================
-- 1. Create supported_countries table
-- ============================================
CREATE TABLE supported_countries (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  currency_prefix TEXT NOT NULL,
  is_supported BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add trigger for updated_at
CREATE TRIGGER update_supported_countries_updated_at BEFORE UPDATE ON supported_countries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Populate with initial countries
INSERT INTO supported_countries (name, currency_prefix, is_supported) VALUES
  ('Uganda', 'UGX', true),
  ('Kenya', 'KES', true),
  ('Rwanda', 'RWF', true),
  ('Tanzania', 'TZS', true);

-- Enable RLS
ALTER TABLE supported_countries ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone authenticated can view supported countries
CREATE POLICY "Authenticated users can view supported countries"
  ON supported_countries FOR SELECT
  TO authenticated
  USING (true);

-- ============================================
-- 2. Update companies table: Replace country with country_id
-- ============================================

-- Add country_id column
ALTER TABLE companies ADD COLUMN country_id INTEGER REFERENCES supported_countries(id);

-- Migrate existing data (if any) - match by country name
UPDATE companies c
SET country_id = sc.id
FROM supported_countries sc
WHERE LOWER(c.country) = LOWER(sc.name);

-- Set default for companies without matching country (default to Uganda)
UPDATE companies
SET country_id = (SELECT id FROM supported_countries WHERE name = 'Uganda' LIMIT 1)
WHERE country_id IS NULL;

-- Make country_id NOT NULL after migration
ALTER TABLE companies ALTER COLUMN country_id SET NOT NULL;

-- Drop old country column
ALTER TABLE companies DROP COLUMN country;

-- Create index for country_id
CREATE INDEX idx_companies_country_id ON companies(country_id);

-- ============================================
-- 3. Add day_open to outlets table
-- ============================================

-- Create enum for day_open status
CREATE TYPE day_status AS ENUM ('open', 'closed');

-- Add day_open column with default 'closed'
ALTER TABLE outlets ADD COLUMN day_open day_status NOT NULL DEFAULT 'closed';

-- ============================================
-- 4. Remove company_id from users table
-- ============================================

-- Note: Users are now associated with companies via their outlet_id
-- outlet -> company relationship provides the company association

-- First, drop the existing policies that reference company_id in users
DROP POLICY IF EXISTS "Users can view their own company" ON companies;
DROP POLICY IF EXISTS "Super users can update their company" ON companies;
DROP POLICY IF EXISTS "Users can view outlets from their company" ON outlets;
DROP POLICY IF EXISTS "Super users can manage outlets" ON outlets;
DROP POLICY IF EXISTS "Users can view colleagues from same company" ON users;
DROP POLICY IF EXISTS "Super users can manage users in their company" ON users;
DROP POLICY IF EXISTS "Super users can view billing for their outlets" ON billing_records;
DROP POLICY IF EXISTS "Super users can manage billing" ON billing_records;

-- Drop index on company_id
DROP INDEX IF EXISTS idx_users_company_id;

-- Drop company_id column from users
ALTER TABLE users DROP COLUMN company_id;

-- ============================================
-- 5. Recreate RLS policies without company_id in users
-- ============================================

-- Companies policies (via outlet -> company relationship)
CREATE POLICY "Users can view their own company"
  ON companies FOR SELECT
  USING (id IN (
    SELECT o.company_id FROM outlets o
    JOIN users u ON u.outlet_id = o.id
    WHERE u.id = auth.uid()
  ));

CREATE POLICY "Super users can update their company"
  ON companies FOR UPDATE
  USING (id IN (
    SELECT o.company_id FROM outlets o
    JOIN users u ON u.outlet_id = o.id
    WHERE u.id = auth.uid() AND u.role = 'super'
  ));

-- Outlets policies (via user's outlet -> company)
CREATE POLICY "Users can view outlets from their company"
  ON outlets FOR SELECT
  USING (company_id IN (
    SELECT o.company_id FROM outlets o
    JOIN users u ON u.outlet_id = o.id
    WHERE u.id = auth.uid()
  ));

CREATE POLICY "Super users can manage outlets"
  ON outlets FOR ALL
  USING (company_id IN (
    SELECT o.company_id FROM outlets o
    JOIN users u ON u.outlet_id = o.id
    WHERE u.id = auth.uid() AND u.role = 'super'
  ));

-- Users policies (view colleagues via outlet -> company)
CREATE POLICY "Users can view colleagues from same company"
  ON users FOR SELECT
  USING (outlet_id IN (
    SELECT o2.id FROM outlets o2
    WHERE o2.company_id IN (
      SELECT o.company_id FROM outlets o
      JOIN users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid()
    )
  ));

CREATE POLICY "Super users can manage users in their company"
  ON users FOR ALL
  USING (outlet_id IN (
    SELECT o2.id FROM outlets o2
    WHERE o2.company_id IN (
      SELECT o.company_id FROM outlets o
      JOIN users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid() AND u.role = 'super'
    )
  ));

-- Billing records policies (unchanged logic but re-expressed for clarity)
CREATE POLICY "Super users can view billing for their outlets"
  ON billing_records FOR SELECT
  USING (outlet_id IN (
    SELECT o2.id FROM outlets o2
    WHERE o2.company_id IN (
      SELECT o.company_id FROM outlets o
      JOIN users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid() AND u.role = 'super'
    )
  ));

CREATE POLICY "Super users can manage billing"
  ON billing_records FOR ALL
  USING (outlet_id IN (
    SELECT o2.id FROM outlets o2
    WHERE o2.company_id IN (
      SELECT o.company_id FROM outlets o
      JOIN users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid() AND u.role = 'super'
    )
  ));

-- ============================================
-- 6. Update create_company function to use country_id
-- ============================================
CREATE OR REPLACE FUNCTION create_company(
  p_business_name TEXT,
  p_business_type TEXT,
  p_country_id INTEGER
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id BIGINT;
BEGIN
  INSERT INTO companies (business_name, business_type, country_id)
  VALUES (p_business_name, p_business_type::business_type, p_country_id)
  RETURNING id INTO v_company_id;

  RETURN v_company_id;
END;
$$;

-- Grant permissions on new table
GRANT ALL ON supported_countries TO authenticated;
GRANT USAGE ON SEQUENCE supported_countries_id_seq TO authenticated;
