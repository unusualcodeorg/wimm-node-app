-- Migration: Create outlet_sections and outlet_tables
-- Created: 2026-02-11
-- Description: Creates tables for managing outlet sections (areas) and tables,
--   with role-based RLS policies:
--   - Super users: full CRUD on all outlets within their company
--   - Managers: create/update on their own outlet only
--   - All other roles: read-only on their own outlet only
--   Note: Requires 'manager' role to be added to user_role enum first
--   (see migration 20260211121800_add_manager_role.sql)

-- ============================================================
-- 1. Create outlet_sections table
-- ============================================================
CREATE TABLE public.outlet_sections (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  is_hidden BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_outlet_sections_outlet_id ON public.outlet_sections(outlet_id);
CREATE UNIQUE INDEX idx_outlet_sections_outlet_name ON public.outlet_sections(outlet_id, LOWER(name));

-- Auto-update timestamp trigger
CREATE TRIGGER update_outlet_sections_updated_at
  BEFORE UPDATE ON public.outlet_sections
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 2. Create outlet_tables table
-- ============================================================
CREATE TABLE public.outlet_tables (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  section_id INTEGER NOT NULL REFERENCES public.outlet_sections(id) ON DELETE CASCADE,
  is_hidden BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_outlet_tables_section_id ON public.outlet_tables(section_id);

-- Auto-update timestamp trigger
CREATE TRIGGER update_outlet_tables_updated_at
  BEFORE UPDATE ON public.outlet_tables
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. Enable RLS
-- ============================================================
ALTER TABLE public.outlet_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outlet_tables ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. RLS Policies for outlet_sections
-- ============================================================

-- SELECT: All authenticated users can view sections for their own outlet
CREATE POLICY "Users can view sections of their outlet"
  ON public.outlet_sections
  FOR SELECT
  TO authenticated
  USING (
    outlet_id IN (
      SELECT u.outlet_id FROM public.users u WHERE u.id = auth.uid()
    )
  );

-- SELECT: Super users can view sections for ALL outlets in their company
CREATE POLICY "Super users can view all company sections"
  ON public.outlet_sections
  FOR SELECT
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

-- INSERT: Super users can create sections for any outlet in their company
CREATE POLICY "Super users can create sections for company outlets"
  ON public.outlet_sections
  FOR INSERT
  TO authenticated
  WITH CHECK (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

-- INSERT: Managers can create sections for their own outlet
CREATE POLICY "Managers can create sections for their outlet"
  ON public.outlet_sections
  FOR INSERT
  TO authenticated
  WITH CHECK (
    outlet_id IN (
      SELECT u.outlet_id FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'manager'
    )
  );

-- UPDATE: Super users can update sections for any outlet in their company
CREATE POLICY "Super users can update company sections"
  ON public.outlet_sections
  FOR UPDATE
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

-- UPDATE: Managers can update sections for their own outlet
CREATE POLICY "Managers can update sections for their outlet"
  ON public.outlet_sections
  FOR UPDATE
  TO authenticated
  USING (
    outlet_id IN (
      SELECT u.outlet_id FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'manager'
    )
  );

-- DELETE: Only super users can delete sections (for any outlet in their company)
CREATE POLICY "Super users can delete company sections"
  ON public.outlet_sections
  FOR DELETE
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

-- ============================================================
-- 5. RLS Policies for outlet_tables
-- ============================================================

-- SELECT: All authenticated users can view tables for sections in their outlet
CREATE POLICY "Users can view tables of their outlet"
  ON public.outlet_tables
  FOR SELECT
  TO authenticated
  USING (
    section_id IN (
      SELECT os.id FROM public.outlet_sections os
      WHERE os.outlet_id IN (
        SELECT u.outlet_id FROM public.users u WHERE u.id = auth.uid()
      )
    )
  );

-- SELECT: Super users can view tables for ALL outlets in their company
CREATE POLICY "Super users can view all company tables"
  ON public.outlet_tables
  FOR SELECT
  TO authenticated
  USING (
    section_id IN (
      SELECT os.id FROM public.outlet_sections os
      WHERE os.outlet_id IN (
        SELECT o.id FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid() AND u.role = 'super'
        )
      )
    )
  );

-- INSERT: Super users can create tables for any outlet in their company
CREATE POLICY "Super users can create tables for company outlets"
  ON public.outlet_tables
  FOR INSERT
  TO authenticated
  WITH CHECK (
    section_id IN (
      SELECT os.id FROM public.outlet_sections os
      WHERE os.outlet_id IN (
        SELECT o.id FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid() AND u.role = 'super'
        )
      )
    )
  );

-- INSERT: Managers can create tables for sections in their outlet
CREATE POLICY "Managers can create tables for their outlet"
  ON public.outlet_tables
  FOR INSERT
  TO authenticated
  WITH CHECK (
    section_id IN (
      SELECT os.id FROM public.outlet_sections os
      WHERE os.outlet_id IN (
        SELECT u.outlet_id FROM public.users u
        WHERE u.id = auth.uid() AND u.role = 'manager'
      )
    )
  );

-- UPDATE: Super users can update tables for any outlet in their company
CREATE POLICY "Super users can update company tables"
  ON public.outlet_tables
  FOR UPDATE
  TO authenticated
  USING (
    section_id IN (
      SELECT os.id FROM public.outlet_sections os
      WHERE os.outlet_id IN (
        SELECT o.id FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid() AND u.role = 'super'
        )
      )
    )
  );

-- UPDATE: Managers can update tables for sections in their outlet
CREATE POLICY "Managers can update tables for their outlet"
  ON public.outlet_tables
  FOR UPDATE
  TO authenticated
  USING (
    section_id IN (
      SELECT os.id FROM public.outlet_sections os
      WHERE os.outlet_id IN (
        SELECT u.outlet_id FROM public.users u
        WHERE u.id = auth.uid() AND u.role = 'manager'
      )
    )
  );

-- DELETE: Only super users can delete tables (for any outlet in their company)
CREATE POLICY "Super users can delete company tables"
  ON public.outlet_tables
  FOR DELETE
  TO authenticated
  USING (
    section_id IN (
      SELECT os.id FROM public.outlet_sections os
      WHERE os.outlet_id IN (
        SELECT o.id FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid() AND u.role = 'super'
        )
      )
    )
  );

-- ============================================================
-- 6. Grant permissions
-- ============================================================
GRANT ALL ON public.outlet_sections TO authenticated;
GRANT ALL ON public.outlet_tables TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.outlet_sections_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.outlet_tables_id_seq TO authenticated;
