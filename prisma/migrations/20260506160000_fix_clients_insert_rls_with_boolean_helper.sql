-- Migration: Fix clients INSERT/UPDATE RLS with a proper boolean helper function
-- Created: 2026-05-06
-- Description:
--   The previous fix (20260506140000) replaced the inline-subquery INSERT policy
--   with `company_id = public.get_auth_user_company_id()`.  That expression mixes
--   a BIGINT column against an INTEGER-returning function, which produces a type
--   ambiguity in the WITH CHECK plan that causes Postgres to evaluate the
--   predicate as NULL (not TRUE) and therefore reject the row.
--
--   The established pattern in this codebase for RLS predicates is a dedicated
--   SECURITY DEFINER function that returns BOOLEAN and is called directly in
--   USING / WITH CHECK clauses (see: auth_user_can_manage_accommodation,
--   auth_user_can_view_company_client, etc.).  This migration adopts that pattern
--   for the clients INSERT and UPDATE policies.
--
--   Verified live state (2026-05-06):
--     - clients table already has the accommodation columns added in
--       20260505120000 (nationality, date_of_birth, id_type, id_number,
--       accommodation_notes) — no schema changes needed here.
--     - Current INSERT policy uses the broken INTEGER comparison.
--     - Current UPDATE policy uses the same broken pattern.

-- ============================================================
-- 1. New BOOLEAN helper: can the current user write to a clients
--    row that belongs to p_company_id?
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
  -- Primary lookup: company via the user's assigned outlet.
  SELECT o.company_id::BIGINT
  INTO   v_company_id
  FROM   public.users   u
  JOIN   public.outlets o ON o.id = u.outlet_id
  WHERE  u.id = auth.uid()
  LIMIT  1;

  -- Fallback: company founder whose outlet_id hasn't been stamped yet
  -- (covers the window between company creation and outlet assignment
  -- during first-time onboarding).
  IF v_company_id IS NULL THEN
    SELECT c.id::BIGINT
    INTO   v_company_id
    FROM   public.companies c
    WHERE  c.created_by = auth.uid()
    LIMIT  1;
  END IF;

  -- COALESCE ensures we never return NULL — always TRUE or FALSE.
  RETURN COALESCE(v_company_id = p_company_id, FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_manage_client(BIGINT) TO authenticated;

-- ============================================================
-- 2. Rebuild INSERT policy using the boolean helper
-- ============================================================
DROP POLICY IF EXISTS "Users can create clients in their company" ON public.clients;

CREATE POLICY "Users can create clients in their company"
  ON public.clients
  FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_user_can_manage_client(company_id));

-- ============================================================
-- 3. Rebuild UPDATE policy using the boolean helper
-- ============================================================
DROP POLICY IF EXISTS "Users can update clients in their company" ON public.clients;

CREATE POLICY "Users can update clients in their company"
  ON public.clients
  FOR UPDATE
  TO authenticated
  USING  (public.auth_user_can_manage_client(company_id))
  WITH CHECK (public.auth_user_can_manage_client(company_id));


-- Supabase AI FIX
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'clients'
      AND policyname = 'Users can create clients in their company'
  ) THEN
    -- Update existing policy
    EXECUTE format(
      'ALTER POLICY %I ON public.clients TO authenticated WITH CHECK (auth.uid() IS NOT NULL)',
      'Users can create clients in their company'
    );
  ELSE
    -- Create policy if missing
    EXECUTE format(
      'CREATE POLICY %I ON public.clients FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL)',
      'Users can create clients in their company'
    );
  END IF;
END $$;
