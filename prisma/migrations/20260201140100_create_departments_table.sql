-- Migration: Create departments table
-- Created: 2026-02-01
-- Description: Creates departments table for menu item routing to printers

-- Create department status enum
CREATE TYPE department_status AS ENUM ('active', 'inactive');

-- Create departments table
CREATE TABLE departments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  status department_status NOT NULL DEFAULT 'active',
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create unique constraint for department name per outlet
CREATE UNIQUE INDEX idx_departments_outlet_name ON departments(outlet_id, LOWER(name));

-- Create index for outlet lookup
CREATE INDEX idx_departments_outlet_id ON departments(outlet_id);

-- Create index for status filtering
CREATE INDEX idx_departments_status ON departments(status);

-- Create trigger for updated_at
CREATE TRIGGER update_departments_updated_at BEFORE UPDATE ON departments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;

-- Departments policies: Users can view departments from their company's outlets
-- Departments policies: Users can view departments from their company's outlets
CREATE POLICY "Users can view departments from their company outlets"
  ON departments FOR SELECT
  USING (outlet_id IN (
    SELECT o.id FROM outlets o
    WHERE o.company_id IN (
      SELECT o2.company_id FROM outlets o2
      JOIN public.users u ON u.outlet_id = o2.id
      WHERE u.id = auth.uid()
    )
  ));

-- Super users can manage departments
CREATE POLICY "Super users can manage departments"
  ON departments FOR ALL
  USING (outlet_id IN (
    SELECT o.id FROM outlets o
    WHERE o.company_id IN (
      SELECT o2.company_id FROM outlets o2
      JOIN public.users u ON u.outlet_id = o2.id
      WHERE u.id = auth.uid() AND u.role = 'super'
    )
  ));

-- Grant permissions
GRANT ALL ON departments TO authenticated;
