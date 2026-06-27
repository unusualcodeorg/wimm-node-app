-- Migration: Create inventory stock movements foundation
-- Created: 2026-05-22
-- Description:
--   - Creates outlet- and location-scoped inventory stock movement history
--   - Stores movement type, reference linkage, quantity, and valuation impact
--   - Adds indexes for fast stock history and valuation reporting
--   - Adds row-level security policies and grants

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'inventory_stock_movement_type'
  ) THEN
    CREATE TYPE public.inventory_stock_movement_type AS ENUM (
      'purchase_receipt',
      'sale_consumption',
      'transfer_out',
      'transfer_in',
      'adjustment_increase',
      'adjustment_decrease',
      'wastage',
      'return_to_supplier',
      'stock_count_correction'
    );
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.inventory_stock_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  stock_location_id UUID NOT NULL REFERENCES public.inventory_stock_locations(id) ON DELETE CASCADE,
  inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
  movement_type public.inventory_stock_movement_type NOT NULL,
  reference_type TEXT,
  reference_id TEXT,
  quantity NUMERIC(14, 4) NOT NULL,
  unit_cost NUMERIC(14, 4),
  total_cost NUMERIC(14, 2),
  movement_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_stock_movements_reference_type_not_blank CHECK (
    reference_type IS NULL OR length(btrim(reference_type)) > 0
  ),
  CONSTRAINT inventory_stock_movements_reference_id_not_blank CHECK (
    reference_id IS NULL OR length(btrim(reference_id)) > 0
  ),
  CONSTRAINT inventory_stock_movements_quantity_not_zero CHECK (
    quantity <> 0
  ),
  CONSTRAINT inventory_stock_movements_unit_cost_non_negative CHECK (
    unit_cost IS NULL OR unit_cost >= 0
  ),
  CONSTRAINT inventory_stock_movements_total_cost_non_negative CHECK (
    total_cost IS NULL OR total_cost >= 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_stock_movements_company_outlet_id_unique
  ON public.inventory_stock_movements(company_id, outlet_id, id);

CREATE INDEX IF NOT EXISTS idx_inventory_stock_movements_outlet_location_date
  ON public.inventory_stock_movements(
    company_id,
    outlet_id,
    stock_location_id,
    movement_date DESC
  );

CREATE INDEX IF NOT EXISTS idx_inventory_stock_movements_item_date
  ON public.inventory_stock_movements(
    company_id,
    inventory_item_id,
    movement_date DESC
  );

CREATE INDEX IF NOT EXISTS idx_inventory_stock_movements_type_date
  ON public.inventory_stock_movements(
    company_id,
    outlet_id,
    movement_type,
    movement_date DESC
  );

CREATE INDEX IF NOT EXISTS idx_inventory_stock_movements_reference_lookup
  ON public.inventory_stock_movements(
    company_id,
    reference_type,
    reference_id
  );

ALTER TABLE public.inventory_stock_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view inventory stock movements in their company" ON public.inventory_stock_movements;
CREATE POLICY "Users can view inventory stock movements in their company"
  ON public.inventory_stock_movements
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert inventory stock movements in their company" ON public.inventory_stock_movements;
CREATE POLICY "Users can insert inventory stock movements in their company"
  ON public.inventory_stock_movements
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update inventory stock movements in their company" ON public.inventory_stock_movements;
CREATE POLICY "Users can update inventory stock movements in their company"
  ON public.inventory_stock_movements
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete inventory stock movements in their company" ON public.inventory_stock_movements;
CREATE POLICY "Users can delete inventory stock movements in their company"
  ON public.inventory_stock_movements
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_stock_movements TO authenticated;
