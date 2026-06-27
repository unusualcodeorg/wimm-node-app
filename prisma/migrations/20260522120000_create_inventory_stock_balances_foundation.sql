-- Migration: Create inventory stock balances foundation
-- Created: 2026-05-22
-- Description:
--   - Creates outlet- and location-scoped inventory stock balances
--   - Stores quantity on hand, average cost, and total value per item/location
--   - Adds indexes, updated_at trigger, RLS policies, and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.inventory_stock_balances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  stock_location_id UUID NOT NULL REFERENCES public.inventory_stock_locations(id) ON DELETE CASCADE,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
  quantity_on_hand NUMERIC(14, 4) NOT NULL DEFAULT 0,
  average_cost NUMERIC(14, 4) NOT NULL DEFAULT 0,
  total_value NUMERIC(14, 2) NOT NULL DEFAULT 0,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_stock_balances_quantity_non_negative CHECK (
    quantity_on_hand >= 0
  ),
  CONSTRAINT inventory_stock_balances_average_cost_non_negative CHECK (
    average_cost >= 0
  ),
  CONSTRAINT inventory_stock_balances_total_value_non_negative CHECK (
    total_value >= 0
  ),
  CONSTRAINT inventory_stock_balances_value_matches_components CHECK (
    total_value = ROUND((quantity_on_hand * average_cost)::numeric, 2)
  ),
  CONSTRAINT inventory_stock_balances_company_outlet_location_item_unique UNIQUE (
    company_id,
    outlet_id,
    stock_location_id,
    inventory_item_id
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_stock_balances_company_outlet_id_unique
  ON public.inventory_stock_balances(company_id, outlet_id, id);

CREATE INDEX IF NOT EXISTS idx_inventory_stock_balances_outlet_location_item
  ON public.inventory_stock_balances(
    company_id,
    outlet_id,
    stock_location_id,
    inventory_item_id
  );

CREATE INDEX IF NOT EXISTS idx_inventory_stock_balances_item_lookup
  ON public.inventory_stock_balances(company_id, inventory_item_id);

CREATE INDEX IF NOT EXISTS idx_inventory_stock_balances_updated_at
  ON public.inventory_stock_balances(company_id, outlet_id, updated_at DESC);

DROP TRIGGER IF EXISTS update_inventory_stock_balances_updated_at ON public.inventory_stock_balances;
CREATE TRIGGER update_inventory_stock_balances_updated_at
  BEFORE UPDATE ON public.inventory_stock_balances
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.inventory_stock_balances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view inventory stock balances in their company" ON public.inventory_stock_balances;
CREATE POLICY "Users can view inventory stock balances in their company"
  ON public.inventory_stock_balances
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert inventory stock balances in their company" ON public.inventory_stock_balances;
CREATE POLICY "Users can insert inventory stock balances in their company"
  ON public.inventory_stock_balances
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update inventory stock balances in their company" ON public.inventory_stock_balances;
CREATE POLICY "Users can update inventory stock balances in their company"
  ON public.inventory_stock_balances
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete inventory stock balances in their company" ON public.inventory_stock_balances;
CREATE POLICY "Users can delete inventory stock balances in their company"
  ON public.inventory_stock_balances
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_stock_balances TO authenticated;
