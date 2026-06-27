-- Migration: Create inventory items foundation
-- Created: 2026-05-22
-- Description:
--   - Creates company-scoped inventory items
--   - Stores inline category, units, conversion, reorder level, and costing method
--   - Adds indexes, updated_at trigger, RLS policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Inventory enums
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'inventory_costing_method'
  ) THEN
    CREATE TYPE public.inventory_costing_method AS ENUM ('weighted_average');
  END IF;
END;
$$;

-- ============================================================
-- 2. Inventory items table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inventory_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku TEXT,
  name TEXT NOT NULL,
  description TEXT,
  category TEXT,
  purchase_unit TEXT NOT NULL,
  stock_unit TEXT NOT NULL,
  conversion_rate NUMERIC(14, 6) NOT NULL DEFAULT 1,
  costing_method public.inventory_costing_method NOT NULL DEFAULT 'weighted_average',
  reorder_level NUMERIC(14, 4) NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_items_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT inventory_items_sku_not_blank CHECK (
    sku IS NULL OR length(btrim(sku)) > 0
  ),
  CONSTRAINT inventory_items_category_not_blank CHECK (
    category IS NULL OR length(btrim(category)) > 0
  ),
  CONSTRAINT inventory_items_purchase_unit_not_blank CHECK (
    length(btrim(purchase_unit)) > 0
  ),
  CONSTRAINT inventory_items_stock_unit_not_blank CHECK (
    length(btrim(stock_unit)) > 0
  ),
  CONSTRAINT inventory_items_conversion_rate_positive CHECK (
    conversion_rate > 0
  ),
  CONSTRAINT inventory_items_reorder_level_non_negative CHECK (
    reorder_level >= 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_items_company_id_id_unique
  ON public.inventory_items(company_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_items_company_lower_name_unique
  ON public.inventory_items(company_id, lower(name));

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_items_company_lower_sku_unique
  ON public.inventory_items(company_id, lower(sku))
  WHERE sku IS NOT NULL AND length(btrim(sku)) > 0;

CREATE INDEX IF NOT EXISTS idx_inventory_items_company_category_active
  ON public.inventory_items(company_id, category, is_active);

CREATE INDEX IF NOT EXISTS idx_inventory_items_company_created_at
  ON public.inventory_items(company_id, created_at DESC);

DROP TRIGGER IF EXISTS update_inventory_items_updated_at ON public.inventory_items;
CREATE TRIGGER update_inventory_items_updated_at
  BEFORE UPDATE ON public.inventory_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Row level security
-- ============================================================
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view inventory items in their company" ON public.inventory_items;
CREATE POLICY "Users can view inventory items in their company"
  ON public.inventory_items
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert inventory items in their company" ON public.inventory_items;
CREATE POLICY "Users can insert inventory items in their company"
  ON public.inventory_items
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update inventory items in their company" ON public.inventory_items;
CREATE POLICY "Users can update inventory items in their company"
  ON public.inventory_items
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete inventory items in their company" ON public.inventory_items;
CREATE POLICY "Users can delete inventory items in their company"
  ON public.inventory_items
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_items TO authenticated;
