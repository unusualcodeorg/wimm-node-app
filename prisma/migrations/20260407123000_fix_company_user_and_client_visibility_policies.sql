-- Migration: Fix company-wide visibility for users and clients in reports
-- Created: 2026-04-07
-- Description:
--   - Restores same-company user profile visibility for authenticated users
--   - Allows account-manager super_admin users to view any user profile
--   - Aligns client visibility to the same security-definer helper pattern
--   - Ensures security_invoker report views can resolve waiter/client names consistently

-- ============================================================
-- 1. Helper functions
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_auth_user_role()
RETURNS public.user_role
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.role
  FROM public.users u
  WHERE u.id = auth.uid()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_auth_user_role() TO authenticated;

CREATE OR REPLACE FUNCTION public.auth_user_can_view_company_user(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.get_auth_user_role() = 'super_admin'
    OR EXISTS (
      SELECT 1
      FROM public.users u
      JOIN public.outlets o ON o.id = u.outlet_id
      WHERE u.id = p_user_id
        AND o.company_id = public.get_auth_user_company_id()
    );
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_view_company_user(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.auth_user_can_view_company_client(p_client_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.clients c
    WHERE c.id = p_client_id
      AND c.company_id = public.get_auth_user_company_id()
  );
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_view_company_client(UUID) TO authenticated;

-- ============================================================
-- 2. Users policies
-- ============================================================
DROP POLICY IF EXISTS "Users can view their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can view colleagues from same company" ON public.users;
DROP POLICY IF EXISTS "Users can view colleagues" ON public.users;
DROP POLICY IF EXISTS "Users can view profiles in their company" ON public.users;

CREATE POLICY "Users can view profiles in their company"
  ON public.users
  FOR SELECT
  TO authenticated
  USING (
    id = auth.uid()
    OR public.auth_user_can_view_company_user(id)
  );

DROP POLICY IF EXISTS "Super users can update company users" ON public.users;
DROP POLICY IF EXISTS "Super users can manage users in their company" ON public.users;

CREATE POLICY "Super users can update company users"
  ON public.users
  FOR UPDATE
  TO authenticated
  USING (
    id <> auth.uid()
    AND public.get_auth_user_role() = 'super'
    AND public.auth_user_can_view_company_user(id)
  )
  WITH CHECK (
    id <> auth.uid()
    AND public.get_auth_user_role() = 'super'
    AND public.auth_user_can_view_company_user(id)
  );

-- ============================================================
-- 3. Clients policy alignment
-- ============================================================
DROP POLICY IF EXISTS "Users can view clients in their company" ON public.clients;

CREATE POLICY "Users can view clients in their company"
  ON public.clients
  FOR SELECT
  TO authenticated
  USING (public.auth_user_can_view_company_client(id));
