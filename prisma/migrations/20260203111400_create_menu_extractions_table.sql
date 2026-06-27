-- Migration: Create menu_extractions table for AI menu import
-- Created: 2026-02-03
-- Description: Creates menu_extractions table to store AI-extracted menu data from uploaded files

-- Create extraction status enum
CREATE TYPE menu_extraction_status AS ENUM ('pending', 'reviewed', 'declined', 'committed');

-- Create menu_extractions table
CREATE TABLE menu_extractions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  raw_text TEXT NOT NULL,
  json_output JSONB,
  file_name TEXT,
  file_type TEXT,
  status menu_extraction_status DEFAULT 'pending',
  version INT DEFAULT 1,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- The json_output structure should follow this schema for AI response:
-- {
--   "menu_metadata": {
--     "currency": "USD",
--     "extracted_at": "2026-02-03T10:30:00Z"
--   },
--   "categories": [
--     {
--       "category_name": "Mains",
--       "items": [
--         {
--           "item_name": "Pork Spare Ribs",
--           "base_price": 25.00,
--           "department": "Kitchen",
--           "description": "Slow-cooked ribs with BBQ glaze",
--           "addons": [
--             { "name": "Wedges", "price_override": 0.00 },
--             { "name": "Rice", "price_override": 0.00 }
--           ]
--         }
--       ]
--     }
--   ],
--   "addon_library_discovery": ["Wedges", "Rice", "Plantain"]
-- }

-- Create indexes for faster lookups
CREATE INDEX idx_menu_extractions_outlet ON menu_extractions(outlet_id);
CREATE INDEX idx_menu_extractions_status ON menu_extractions(status);
CREATE INDEX idx_menu_extractions_created_by ON menu_extractions(created_by);

-- Create update trigger for updated_at
CREATE TRIGGER menu_extractions_updated_at
  BEFORE UPDATE ON menu_extractions
  FOR EACH ROW
  EXECUTE FUNCTION update_menu_updated_at();

-- Enable Row Level Security
ALTER TABLE menu_extractions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for menu_extractions
-- Users can view extractions from their company's outlets
CREATE POLICY "Users can view extractions from their outlets"
  ON menu_extractions FOR SELECT
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

-- Only Super users can manage extractions (create, update, delete)
CREATE POLICY "Super users can manage extractions"
  ON menu_extractions FOR ALL
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

-- Grant permissions
GRANT SELECT ON menu_extractions TO authenticated;
GRANT ALL ON menu_extractions TO service_role;
