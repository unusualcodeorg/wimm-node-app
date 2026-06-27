-- Migration: Fix clients RLS policies (SELECT / INSERT / UPDATE)
-- Created: 2026-05-06
-- Description:
--   Restores authenticated users' ability to create, view, and update
--   clients within their own company.  The accommodation rollout
--   (20260505120000) extended the clients table with new columns; in the
--   process the INSERT policy on `public.clients` drifted through several
--   unrecorded hotfixes:
--
--     1. Original (20260213160000): inline subquery against outlets+users
--     2. Hotfix attempt: `company_id = get_auth_user_company_id()` —
--        broken because the helper returns INTEGER while the column is
--        BIGINT, so the WITH CHECK predicate evaluated to NULL → reject.
--     3. Manual patch: `(auth.uid() IS NOT NULL)` — too permissive;
--        any authenticated user could insert a row for any company.
--
--   This migration consolidates the three policies onto a single
--   BOOLEAN-returning SECURITY DEFINER helper that:
--     - Resolves the caller's company via their outlet assignment, or
--     - Falls back to the company they founded (covers the onboarding
--       window before an outlet is stamped on the user record).
--
--   The same helper is used for SELECT, INSERT, and UPDATE so the
--   visibility surface is consistent across all client operations.

-- ============================================================
-- 1. Boolean helper: can the caller act on a clients row owned
--    by p_company_id?
-- ============================================================
CREATE OR REPLACE FUNCTION public.auth_user_can_manage_client(p_company_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id BIGINT;
BEGIN
  IF p_company_id IS NULL OR auth.uid() IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Primary: user's company via their assigned outlet.
  SELECT o.company_id::BIGINT
  INTO   v_company_id
  FROM   public.users   u
  JOIN   public.outlets o ON o.id = u.outlet_id
  WHERE  u.id = auth.uid()
  LIMIT  1;

  -- Fallback: founder whose outlet_id has not been stamped yet
  -- (covers the onboarding window between company creation and
  -- outlet assignment).
  IF v_company_id IS NULL THEN
    SELECT c.id::BIGINT
    INTO   v_company_id
    FROM   public.companies c
    WHERE  c.created_by = auth.uid()
    LIMIT  1;
  END IF;

  RETURN COALESCE(v_company_id = p_company_id, FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_manage_client(BIGINT) TO authenticated;

-- ============================================================
-- 2. Drop the orphaned helper from the unrecorded 20260506140000
--    hotfix so we don't carry two near-identical helpers.
-- ============================================================
DROP FUNCTION IF EXISTS public.auth_user_can_create_client_for_company(BIGINT);

-- ============================================================
-- 3. Rebuild all three clients policies using the same helper.
-- ============================================================
DROP POLICY IF EXISTS "Users can view clients in their company"   ON public.clients;
DROP POLICY IF EXISTS "Users can create clients in their company" ON public.clients;
DROP POLICY IF EXISTS "Users can update clients in their company" ON public.clients;

CREATE POLICY "Users can view clients in their company"
  ON public.clients
  FOR SELECT
  TO authenticated
  USING (public.auth_user_can_manage_client(company_id));

CREATE POLICY "Users can create clients in their company"
  ON public.clients
  FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_user_can_manage_client(company_id));

CREATE POLICY "Users can update clients in their company"
  ON public.clients
  FOR UPDATE
  TO authenticated
  USING      (public.auth_user_can_manage_client(company_id))
  WITH CHECK (public.auth_user_can_manage_client(company_id));

-- ============================================================
-- 4. Ensure baseline grants are still in place.
-- ============================================================
GRANT SELECT, INSERT, UPDATE ON public.clients TO authenticated;
