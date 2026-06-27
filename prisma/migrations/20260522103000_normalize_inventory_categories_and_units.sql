-- Migration: Normalize inventory categories and units
-- Created: 2026-05-22
-- Description:
--   - Creates inventory_categories and inventory_units as company-scoped lookup tables
--   - Backfills categories and units from inventory_items
--   - Replaces inline category/unit columns with foreign keys

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Lookup tables
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inventory_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_categories_name_not_blank CHECK (length(btrim(name)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_categories_company_id_id_unique
  ON public.inventory_categories(company_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_categories_company_lower_name_unique
  ON public.inventory_categories(company_id, lower(name));

DROP TRIGGER IF EXISTS update_inventory_categories_updated_at ON public.inventory_categories;
CREATE TRIGGER update_inventory_categories_updated_at
  BEFORE UPDATE ON public.inventory_categories
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.inventory_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  abbreviation TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT inventory_units_name_not_blank CHECK (length(btrim(name)) > 0),
  CONSTRAINT inventory_units_abbreviation_not_blank CHECK (
    abbreviation IS NULL OR length(btrim(abbreviation)) > 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_units_company_id_id_unique
  ON public.inventory_units(company_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_units_company_lower_name_unique
  ON public.inventory_units(company_id, lower(name));

DROP TRIGGER IF EXISTS update_inventory_units_updated_at ON public.inventory_units;
CREATE TRIGGER update_inventory_units_updated_at
  BEFORE UPDATE ON public.inventory_units
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 2. Add foreign key columns to inventory_items
-- ============================================================
ALTER TABLE public.inventory_items
  ADD COLUMN IF NOT EXISTS category_id UUID,
  ADD COLUMN IF NOT EXISTS purchase_unit_id UUID,
  ADD COLUMN IF NOT EXISTS stock_unit_id UUID;

-- ============================================================
-- 3. Backfill categories and units from inline values
-- ============================================================
INSERT INTO public.inventory_categories (company_id, name)
SELECT DISTINCT company_id, btrim(category)
FROM public.inventory_items
WHERE category IS NOT NULL
  AND length(btrim(category)) > 0
ON CONFLICT (company_id, lower(name)) DO NOTHING;

INSERT INTO public.inventory_units (company_id, name)
SELECT DISTINCT company_id, btrim(unit_name)
FROM (
  SELECT company_id, purchase_unit AS unit_name
  FROM public.inventory_items
  UNION ALL
  SELECT company_id, stock_unit AS unit_name
  FROM public.inventory_items
) units
WHERE unit_name IS NOT NULL
  AND length(btrim(unit_name)) > 0
ON CONFLICT (company_id, lower(name)) DO NOTHING;

UPDATE public.inventory_items items
SET category_id = categories.id
FROM public.inventory_categories categories
WHERE items.company_id = categories.company_id
  AND items.category IS NOT NULL
  AND lower(btrim(items.category)) = lower(categories.name)
  AND items.category_id IS NULL;

UPDATE public.inventory_items items
SET purchase_unit_id = units.id
FROM public.inventory_units units
WHERE items.company_id = units.company_id
  AND lower(btrim(items.purchase_unit)) = lower(units.name)
  AND items.purchase_unit_id IS NULL;

UPDATE public.inventory_items items
SET stock_unit_id = units.id
FROM public.inventory_units units
WHERE items.company_id = units.company_id
  AND lower(btrim(items.stock_unit)) = lower(units.name)
  AND items.stock_unit_id IS NULL;

-- ============================================================
-- 4. Constraints and foreign keys
-- ============================================================
ALTER TABLE public.inventory_items
  ALTER COLUMN purchase_unit_id SET NOT NULL,
  ALTER COLUMN stock_unit_id SET NOT NULL;

ALTER TABLE public.inventory_items
  DROP CONSTRAINT IF EXISTS inventory_items_category_fk,
  DROP CONSTRAINT IF EXISTS inventory_items_purchase_unit_fk,
  DROP CONSTRAINT IF EXISTS inventory_items_stock_unit_fk;

ALTER TABLE public.inventory_items
  ADD CONSTRAINT inventory_items_category_fk
    FOREIGN KEY (company_id, category_id)
    REFERENCES public.inventory_categories(company_id, id)
    ON DELETE RESTRICT,
  ADD CONSTRAINT inventory_items_purchase_unit_fk
    FOREIGN KEY (company_id, purchase_unit_id)
    REFERENCES public.inventory_units(company_id, id)
    ON DELETE RESTRICT,
  ADD CONSTRAINT inventory_items_stock_unit_fk
    FOREIGN KEY (company_id, stock_unit_id)
    REFERENCES public.inventory_units(company_id, id)
    ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_inventory_items_company_category_id_active
  ON public.inventory_items(company_id, category_id, is_active);

CREATE INDEX IF NOT EXISTS idx_inventory_items_company_purchase_unit_id
  ON public.inventory_items(company_id, purchase_unit_id);

CREATE INDEX IF NOT EXISTS idx_inventory_items_company_stock_unit_id
  ON public.inventory_items(company_id, stock_unit_id);

-- ============================================================
-- 5. Drop old inline columns
-- ============================================================
ALTER TABLE public.inventory_items
  DROP COLUMN IF EXISTS category,
  DROP COLUMN IF EXISTS purchase_unit,
  DROP COLUMN IF EXISTS stock_unit;

-- ============================================================
-- 6. Row level security
-- ============================================================
ALTER TABLE public.inventory_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_units ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view inventory categories in their company" ON public.inventory_categories;
CREATE POLICY "Users can view inventory categories in their company"
  ON public.inventory_categories
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert inventory categories in their company" ON public.inventory_categories;
CREATE POLICY "Users can insert inventory categories in their company"
  ON public.inventory_categories
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update inventory categories in their company" ON public.inventory_categories;
CREATE POLICY "Users can update inventory categories in their company"
  ON public.inventory_categories
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete inventory categories in their company" ON public.inventory_categories;
CREATE POLICY "Users can delete inventory categories in their company"
  ON public.inventory_categories
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can view inventory units in their company" ON public.inventory_units;
CREATE POLICY "Users can view inventory units in their company"
  ON public.inventory_units
  FOR SELECT
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert inventory units in their company" ON public.inventory_units;
CREATE POLICY "Users can insert inventory units in their company"
  ON public.inventory_units
  FOR INSERT
  TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update inventory units in their company" ON public.inventory_units;
CREATE POLICY "Users can update inventory units in their company"
  ON public.inventory_units
  FOR UPDATE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete inventory units in their company" ON public.inventory_units;
CREATE POLICY "Users can delete inventory units in their company"
  ON public.inventory_units
  FOR DELETE
  TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- ============================================================
-- 7. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_categories TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_units TO authenticated;
