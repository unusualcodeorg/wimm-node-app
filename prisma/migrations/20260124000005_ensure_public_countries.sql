-- Migration: Ensure public access to supported_countries
-- Created: 2026-01-24
-- Description: Ensures anon users can view supported_countries. Handles existing policies.

-- 1. Grant permissions
GRANT SELECT ON supported_countries TO anon;

-- 2. Drop existing policy if it exists to avoid conflict
DROP POLICY IF EXISTS "Public can view supported countries" ON supported_countries;

-- 3. Create permission policy for anon
CREATE POLICY "Public can view supported countries"
  ON supported_countries FOR SELECT
  TO anon
  USING (true);
