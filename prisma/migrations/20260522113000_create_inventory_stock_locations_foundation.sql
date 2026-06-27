-- Migration: Create inventory stock locations foundation
-- Created: 2026-05-22
-- Description:
--   - Creates outlet-scoped inventory stock locations
--   - Stores location type, description, and active status
--   - Adds indexes, updated_at trigger, RLS policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'inventory_stock_location_type'
  ) THEN
    CREATE TYPE public.inventory_stock_location_type AS ENUM (
      'store',
      'kitchen',
      'bar',
      'pantry',
      'warehouse',
      'production'
    );
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.inventory_stock_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type public.inventory_stock_location_type NOT NULL DEFAULT 'store',
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_stock_locations_name_not_blank CHECK (
    length(btrim(name)) > 0
  ),
  CONSTRAINT inventory_stock_locations_description_not_blank CHECK (
    description IS NULL OR length(btrim(description)) > 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_stock_locations_company_outlet_id_unique
  ON public.inventory_stock_locations(company_id, outlet_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_stock_locations_outlet_lower_name_unique
  ON public.inventory_stock_locations(company_id, outlet_id, lower(name));

CREATE INDEX IF NOT EXISTS idx_inventory_stock_locations_outlet_active_type
  ON public.inventory_stock_locations(company_id, outlet_id, is_active, type);

CREATE INDEX IF NOT EXISTS idx_inventory_stock_locations_outlet_created_at
  ON public.inventory_stock_locations(company_id, outlet_id, created_at DESC);

DROP TRIGGER IF EXISTS update_inventory_stock_locations_updated_at ON public.inventory_stock_locations;
CREATE TRIGGER update_inventory_stock_locations_updated_at
  BEFORE UPDATE ON public.inventory_stock_locations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.inventory_stock_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view inventory stock locations in their company" ON public.inventory_stock_locations;
CREATE POLICY "Users can view inventory stock locations in their company"
  ON public.inventory_stock_locations
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert inventory stock locations in their company" ON public.inventory_stock_locations;
CREATE POLICY "Users can insert inventory stock locations in their company"
  ON public.inventory_stock_locations
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update inventory stock locations in their company" ON public.inventory_stock_locations;
CREATE POLICY "Users can update inventory stock locations in their company"
  ON public.inventory_stock_locations
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete inventory stock locations in their company" ON public.inventory_stock_locations;
CREATE POLICY "Users can delete inventory stock locations in their company"
  ON public.inventory_stock_locations
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_stock_locations TO authenticated;
