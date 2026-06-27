-- Migration: Fix recursion in users policies
-- Created: 2026-01-27
-- Description: Updates users table policies to guard against infinite recursion by
--              explicitly separating "Self" access (simple) from "Colleague" access (recursive).
--              Uses 'id != auth.uid()' to prevent recursive checks when querying own profile.

-- 1. Drop existing problematic recursive policies
DROP POLICY IF EXISTS "Users can view colleagues from same company" ON users;
DROP POLICY IF EXISTS "Super users can manage users in their company" ON users;
DROP POLICY IF EXISTS "Users can view their own profile" ON users;
DROP POLICY IF EXISTS "Users can update their own profile" ON users;

-- 2. Simple "Self" Policies (Non-recursive base cases)
-- These allow accessing one's own row without triggering function calls or subqueries
CREATE POLICY "Users can view their own profile"
  ON users FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "Users can update their own profile"
  ON users FOR UPDATE
  USING (id = auth.uid());

-- Super users can update others
CREATE POLICY "Super users can update company users"
  ON users FOR UPDATE
  USING (
    id != auth.uid()
    AND
    (SELECT role FROM users WHERE id = auth.uid()) = 'super'
    AND
    outlet_id IN (
      SELECT id FROM outlets WHERE company_id = get_auth_user_company_id()
    )
  );
