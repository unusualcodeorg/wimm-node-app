-- Migration: Allow public access to supported_countries
-- Created: 2026-01-24
-- Description: Grants anon access to supported_countries table so onboarding users can fetch the list.

-- Grant select permission to anon role
GRANT SELECT ON supported_countries TO anon;

-- Create policy for anon users
-- We use DO block to avoid error if policy already exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'supported_countries' AND policyname = 'Public can view supported countries'
    ) THEN
        CREATE POLICY "Public can view supported countries"
          ON supported_countries FOR SELECT
          TO anon
          USING (true);
    END IF;
END
$$;
