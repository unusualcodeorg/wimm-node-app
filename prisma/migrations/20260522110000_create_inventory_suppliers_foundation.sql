-- Migration: Create inventory suppliers foundation
-- Created: 2026-05-22
-- Description:
--   - Creates company-scoped inventory suppliers
--   - Stores contact details, payment terms, and opening balance
--   - Adds indexes, updated_at trigger, RLS policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.inventory_suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  contact_person TEXT,
  phone TEXT,
  email TEXT,
  tax_id TEXT,
  address TEXT,
  payment_terms_days INTEGER NOT NULL DEFAULT 0,
  opening_balance NUMERIC(14, 2) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_suppliers_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT inventory_suppliers_contact_person_not_blank CHECK (
    contact_person IS NULL OR length(btrim(contact_person)) > 0
  ),
  CONSTRAINT inventory_suppliers_phone_not_blank CHECK (
    phone IS NULL OR length(btrim(phone)) > 0
  ),
  CONSTRAINT inventory_suppliers_email_not_blank CHECK (
    email IS NULL OR length(btrim(email)) > 0
  ),
  CONSTRAINT inventory_suppliers_tax_id_not_blank CHECK (
    tax_id IS NULL OR length(btrim(tax_id)) > 0
  ),
  CONSTRAINT inventory_suppliers_address_not_blank CHECK (
    address IS NULL OR length(btrim(address)) > 0
  ),
  CONSTRAINT inventory_suppliers_payment_terms_days_non_negative CHECK (
    payment_terms_days >= 0
  ),
  CONSTRAINT inventory_suppliers_opening_balance_non_negative CHECK (
    opening_balance >= 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_suppliers_company_id_id_unique
  ON public.inventory_suppliers(company_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_suppliers_company_lower_name_unique
  ON public.inventory_suppliers(company_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_inventory_suppliers_company_active_name
  ON public.inventory_suppliers(company_id, is_active, name);

CREATE INDEX IF NOT EXISTS idx_inventory_suppliers_company_created_at
  ON public.inventory_suppliers(company_id, created_at DESC);

DROP TRIGGER IF EXISTS update_inventory_suppliers_updated_at ON public.inventory_suppliers;
CREATE TRIGGER update_inventory_suppliers_updated_at
  BEFORE UPDATE ON public.inventory_suppliers
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.inventory_suppliers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view inventory suppliers in their company" ON public.inventory_suppliers;
CREATE POLICY "Users can view inventory suppliers in their company"
  ON public.inventory_suppliers
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert inventory suppliers in their company" ON public.inventory_suppliers;
CREATE POLICY "Users can insert inventory suppliers in their company"
  ON public.inventory_suppliers
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update inventory suppliers in their company" ON public.inventory_suppliers;
CREATE POLICY "Users can update inventory suppliers in their company"
  ON public.inventory_suppliers
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete inventory suppliers in their company" ON public.inventory_suppliers;
CREATE POLICY "Users can delete inventory suppliers in their company"
  ON public.inventory_suppliers
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_suppliers TO authenticated;
