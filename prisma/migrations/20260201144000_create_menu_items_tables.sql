-- Migration: Create menu items and related tables
-- Created: 2026-02-01
-- Description: Creates menu_categories, menu_items, addon_library, and item_addons tables

-- Create menu item status enum
CREATE TYPE menu_item_status AS ENUM ('active', 'inactive', 'out_of_stock');

-- Create menu categories table
CREATE TABLE menu_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  display_order INT DEFAULT 0,
  status menu_item_status DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique category name per outlet (case-insensitive)
  CONSTRAINT unique_category_name_per_outlet UNIQUE (outlet_id, name)
);

-- Create index for faster lookups
CREATE INDEX idx_menu_categories_outlet ON menu_categories(outlet_id);
CREATE INDEX idx_menu_categories_status ON menu_categories(status);

-- Create menu items table
CREATE TABLE menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  category_id UUID REFERENCES menu_categories(id) ON DELETE SET NULL,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  description TEXT,
  base_price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  image_url TEXT,
  sku TEXT,
  status menu_item_status DEFAULT 'active',
  display_order INT DEFAULT 0,
  is_taxable BOOLEAN DEFAULT true,
  tax_rate DECIMAL(5, 2) DEFAULT 0.00,
  preparation_time INT, -- in minutes
  calories INT,
  allergens TEXT[], -- array of allergens
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique item name per outlet (case-insensitive)
  CONSTRAINT unique_item_name_per_outlet UNIQUE (outlet_id, name)
);

-- Create indexes for faster lookups
CREATE INDEX idx_menu_items_outlet ON menu_items(outlet_id);
CREATE INDEX idx_menu_items_category ON menu_items(category_id);
CREATE INDEX idx_menu_items_department ON menu_items(department_id);
CREATE INDEX idx_menu_items_status ON menu_items(status);
CREATE INDEX idx_menu_items_sku ON menu_items(sku);

-- Create addon library table (central list of addons per outlet)
CREATE TABLE addon_library (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  default_price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  status menu_item_status DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique addon name per outlet (case-insensitive)
  CONSTRAINT unique_addon_name_per_outlet UNIQUE (outlet_id, name)
);

-- Create index for faster lookups
CREATE INDEX idx_addon_library_outlet ON addon_library(outlet_id);
CREATE INDEX idx_addon_library_status ON addon_library(status);

-- Create item-addon mapping table (junction table with price override)
CREATE TABLE item_addons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
  addon_id UUID NOT NULL REFERENCES addon_library(id) ON DELETE CASCADE,
  price_override DECIMAL(10, 2), -- NULL means use default_price from addon_library
  is_required BOOLEAN DEFAULT false,
  max_quantity INT DEFAULT 1,
  display_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique addon per item
  CONSTRAINT unique_addon_per_item UNIQUE (item_id, addon_id)
);

-- Create index for faster lookups
CREATE INDEX idx_item_addons_item ON item_addons(item_id);
CREATE INDEX idx_item_addons_addon ON item_addons(addon_id);

-- Create update triggers for updated_at
CREATE OR REPLACE FUNCTION update_menu_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = public, pg_catalog;

CREATE TRIGGER menu_categories_updated_at
  BEFORE UPDATE ON menu_categories
  FOR EACH ROW
  EXECUTE FUNCTION update_menu_updated_at();

CREATE TRIGGER menu_items_updated_at
  BEFORE UPDATE ON menu_items
  FOR EACH ROW
  EXECUTE FUNCTION update_menu_updated_at();

CREATE TRIGGER addon_library_updated_at
  BEFORE UPDATE ON addon_library
  FOR EACH ROW
  EXECUTE FUNCTION update_menu_updated_at();

-- Enable Row Level Security
ALTER TABLE menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE addon_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_addons ENABLE ROW LEVEL SECURITY;

-- RLS Policies for menu_categories
CREATE POLICY "Users can view categories from their outlets"
  ON menu_categories FOR SELECT
  USING (
    outlet_id IN (
      SELECT o.id FROM outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  );

CREATE POLICY "Super users can manage categories"
  ON menu_categories FOR ALL
  USING (
    outlet_id IN (
      SELECT o.id FROM outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

-- RLS Policies for menu_items
CREATE POLICY "Users can view items from their outlets"
  ON menu_items FOR SELECT
  USING (
    outlet_id IN (
      SELECT o.id FROM outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  );

CREATE POLICY "Super users can manage items"
  ON menu_items FOR ALL
  USING (
    outlet_id IN (
      SELECT o.id FROM outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

-- RLS Policies for addon_library
CREATE POLICY "Users can view addons from their outlets"
  ON addon_library FOR SELECT
  USING (
    outlet_id IN (
      SELECT o.id FROM outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  );

CREATE POLICY "Super users can manage addons"
  ON addon_library FOR ALL
  USING (
    outlet_id IN (
      SELECT o.id FROM outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

-- RLS Policies for item_addons
CREATE POLICY "Users can view item addons from their outlets"
  ON item_addons FOR SELECT
  USING (
    item_id IN (
      SELECT id FROM menu_items WHERE outlet_id IN (
        SELECT o.id FROM outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id FROM outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Super users can manage item addons"
  ON item_addons FOR ALL
  USING (
    item_id IN (
      SELECT id FROM menu_items WHERE outlet_id IN (
        SELECT o.id FROM outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id FROM outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid() AND u.role = 'super'
        )
      )
    )
  );

-- Grant permissions to authenticated users
GRANT SELECT ON menu_categories TO authenticated;
GRANT SELECT ON menu_items TO authenticated;
GRANT SELECT ON addon_library TO authenticated;
GRANT SELECT ON item_addons TO authenticated;

-- Grant full permissions to service role
GRANT ALL ON menu_categories TO service_role;
GRANT ALL ON menu_items TO service_role;
GRANT ALL ON addon_library TO service_role;
GRANT ALL ON item_addons TO service_role;
