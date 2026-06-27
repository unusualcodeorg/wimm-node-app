-- Migration: Drop recursive 'Users can view colleagues' policy
-- Created: 2026-01-27
-- Description: Drops the policy causing infinite recursion on the users table as requested.

DROP POLICY IF EXISTS "Users can view colleagues" ON users;
