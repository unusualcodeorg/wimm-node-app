-- ─── Inventory Recipes Foundation ────────────────────────────────────────────
-- Recipes (bill of materials) link menu items to inventory ingredients.
-- Recipe items quantities are stored in stock units to match stock_balances.

CREATE TABLE IF NOT EXISTS public.inventory_recipes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id        UUID REFERENCES public.outlets(id) ON DELETE CASCADE,
  menu_item_id     UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  description      TEXT,
  yield_quantity   NUMERIC(12, 4) NOT NULL DEFAULT 1,
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_by       UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.inventory_recipe_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id           UUID NOT NULL REFERENCES public.inventory_recipes(id) ON DELETE CASCADE,
  inventory_item_id   UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
  quantity            NUMERIC(12, 4) NOT NULL CHECK (quantity > 0),
  unit_id             UUID REFERENCES public.inventory_units(id),
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_inventory_recipes_company
  ON public.inventory_recipes(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_recipes_outlet
  ON public.inventory_recipes(outlet_id) WHERE outlet_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_recipes_menu_item
  ON public.inventory_recipes(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_inventory_recipe_items_recipe
  ON public.inventory_recipe_items(recipe_id);
CREATE INDEX IF NOT EXISTS idx_inventory_recipe_items_item
  ON public.inventory_recipe_items(inventory_item_id);

-- Updated_at triggers
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_inventory_recipes_updated_at
  BEFORE UPDATE ON public.inventory_recipes
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER trg_inventory_recipe_items_updated_at
  BEFORE UPDATE ON public.inventory_recipe_items
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ─── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.inventory_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_recipe_items ENABLE ROW LEVEL SECURITY;

-- inventory_recipes
CREATE POLICY "inventory_recipes_select" ON public.inventory_recipes
  FOR SELECT TO authenticated
  USING (company_id = public.get_auth_user_company_id());

CREATE POLICY "inventory_recipes_insert" ON public.inventory_recipes
  FOR INSERT TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

CREATE POLICY "inventory_recipes_update" ON public.inventory_recipes
  FOR UPDATE TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

CREATE POLICY "inventory_recipes_delete" ON public.inventory_recipes
  FOR DELETE TO authenticated
  USING (company_id = public.get_auth_user_company_id());

-- inventory_recipe_items (access gated through recipe ownership)
CREATE POLICY "inventory_recipe_items_select" ON public.inventory_recipe_items
  FOR SELECT TO authenticated
  USING (
    recipe_id IN (
      SELECT id FROM public.inventory_recipes
      WHERE company_id = public.get_auth_user_company_id()
    )
  );

CREATE POLICY "inventory_recipe_items_insert" ON public.inventory_recipe_items
  FOR INSERT TO authenticated
  WITH CHECK (
    recipe_id IN (
      SELECT id FROM public.inventory_recipes
      WHERE company_id = public.get_auth_user_company_id()
    )
  );

CREATE POLICY "inventory_recipe_items_update" ON public.inventory_recipe_items
  FOR UPDATE TO authenticated
  USING (
    recipe_id IN (
      SELECT id FROM public.inventory_recipes
      WHERE company_id = public.get_auth_user_company_id()
    )
  );

CREATE POLICY "inventory_recipe_items_delete" ON public.inventory_recipe_items
  FOR DELETE TO authenticated
  USING (
    recipe_id IN (
      SELECT id FROM public.inventory_recipes
      WHERE company_id = public.get_auth_user_company_id()
    )
  );
