-- Migration: Restore 'Users can view colleagues' policy safely
-- Created: 2026-01-27
-- Description: Restores the ability for users to view colleagues using a CASE statement
--              to strictly enforce evaluation order. This prevents the query optimizer from
--              executing the recursive subquery when evaluating the current user's own row.

CREATE POLICY "Users can view colleagues"
  ON users FOR SELECT
  USING (
    CASE
      -- When checking own row, return false immediately.
      -- Access is granted by the separate "Users can view their own profile" policy.
      -- This ensures we NEVER run the recursive subquery for the auth user.
      WHEN id = auth.uid() THEN false

      -- For other rows, check the company/outlet match
      ELSE outlet_id IN (
        SELECT id FROM outlets WHERE company_id = get_auth_user_company_id()
      )
    END
  );
