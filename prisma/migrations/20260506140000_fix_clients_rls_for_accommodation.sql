-- Migration: Fix clients INSERT and UPDATE RLS policies
-- Created: 2026-05-06
-- Description:
--   The original INSERT and UPDATE policies on public.clients (from
--   20260213160000_create_sales_order_flow_foundation.sql) used an inline
--   subquery that joins public.outlets and public.users directly inside the
--   WITH CHECK expression. Because both those tables have their own RLS
--   policies, evaluating the subquery causes a fragile nested-RLS execution
--   path that can silently return 0 rows (e.g. when the outer statement is
--   already running inside a policy check context), making the WITH CHECK
--   evaluate to FALSE and throwing "new row violates row-level security policy".
--
--   Every modern policy in this codebase uses SECURITY DEFINER helper
--   functions to bypass this problem (get_auth_user_company_id,
--   auth_user_can_manage_accommodation, etc.). This migration brings the
--   clients INSERT and UPDATE policies into line with that pattern.

-- ============================================================
-- 1. INSERT policy  — replace inline subquery with helper function
-- ============================================================
DROP POLICY IF EXISTS "Users can create clients in their company" ON public.clients;

CREATE POLICY "Users can create clients in their company"
  ON public.clients
  FOR INSERT
  TO authenticated
  WITH CHECK (
    company_id = public.get_auth_user_company_id()
  );

-- ============================================================
-- 2. UPDATE policy  — same fix; also align USING clause
-- ============================================================
DROP POLICY IF EXISTS "Users can update clients in their company" ON public.clients;

CREATE POLICY "Users can update clients in their company"
  ON public.clients
  FOR UPDATE
  TO authenticated
  USING  (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());
