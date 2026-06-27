-- Migration: Fix recursive RLS policies
-- Created: 2026-01-26
-- Description: Refactors RLS policies to use a SECURITY DEFINER function for resolving
--              company association. This prevents infinite recursion errors caused by
--              circular policy dependencies between users and outlets tables.

-- 1. Create helper function to get current user's company_id safely
--    SECURITY DEFINER ensures this runs with owner privileges, bypassing RLS recursion
CREATE OR REPLACE FUNCTION get_auth_user_company_id()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id INTEGER;
BEGIN
  SELECT o.company_id INTO v_company_id
  FROM users u
  JOIN outlets o ON o.id = u.outlet_id
  WHERE u.id = auth.uid();

  RETURN v_company_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_auth_user_company_id TO authenticated;

-- 2. Fix Companies Policies
DROP POLICY IF EXISTS "Users can view their own company" ON companies;
CREATE POLICY "Users can view their own company"
  ON companies FOR SELECT
  USING (id = get_auth_user_company_id());

DROP POLICY IF EXISTS "Super users can update their company" ON companies;
CREATE POLICY "Super users can update their company"
  ON companies FOR UPDATE
  USING (id = get_auth_user_company_id() AND (SELECT role FROM users WHERE id = auth.uid()) = 'super');

-- 3. Fix Outlets Policies (The source of the recursion error)
DROP POLICY IF EXISTS "Users can view outlets from their company" ON outlets;
CREATE POLICY "Users can view outlets from their company"
  ON outlets FOR SELECT
  USING (company_id = get_auth_user_company_id());

DROP POLICY IF EXISTS "Super users can manage outlets" ON outlets;
CREATE POLICY "Super users can manage outlets"
  ON outlets FOR ALL
  USING (company_id = get_auth_user_company_id() AND (SELECT role FROM users WHERE id = auth.uid()) = 'super');

-- 4. Fix Users Policies
DROP POLICY IF EXISTS "Users can view colleagues from same company" ON users;
CREATE POLICY "Users can view colleagues from same company"
  ON users FOR SELECT
  USING (outlet_id IN (
    SELECT id FROM outlets WHERE company_id = get_auth_user_company_id()
  ));

DROP POLICY IF EXISTS "Super users can manage users in their company" ON users;
CREATE POLICY "Super users can manage users in their company"
  ON users FOR ALL
  USING (outlet_id IN (
    SELECT id FROM outlets WHERE company_id = get_auth_user_company_id()
  ) AND (SELECT role FROM users WHERE id = auth.uid()) = 'super');

-- 5. Fix Billing Records Policies
DROP POLICY IF EXISTS "Super users can view billing for their outlets" ON billing_records;
CREATE POLICY "Super users can view billing for their outlets"
  ON billing_records FOR SELECT
  USING (outlet_id IN (
    SELECT id FROM outlets WHERE company_id = get_auth_user_company_id()
  ) AND (SELECT role FROM users WHERE id = auth.uid()) = 'super');

DROP POLICY IF EXISTS "Super users can manage billing" ON billing_records;
CREATE POLICY "Super users can manage billing"
  ON billing_records FOR ALL
  USING (outlet_id IN (
    SELECT id FROM outlets WHERE company_id = get_auth_user_company_id()
  ) AND (SELECT role FROM users WHERE id = auth.uid()) = 'super');
