-- Migration: Create outlet printers and section printer mappings
-- Created: 2026-02-20
-- Description:
--   - Stores configured printers per outlet (usb, serial, bluetooth, network)
--   - Stores section printer mappings by operation (KOT, BILL, RECEIPT)
--   - Adds views for simpler querying from the renderer app

-- ============================================================
-- 1. Enums
-- ============================================================
CREATE TYPE public.printer_connection_type AS ENUM ('usb', 'serial', 'bluetooth', 'network');
CREATE TYPE public.printer_paper_size AS ENUM ('58mm', '80mm');
CREATE TYPE public.printer_operation AS ENUM ('KOT', 'BILL', 'RECEIPT');

-- ============================================================
-- 2. Outlet printers table
-- ============================================================
CREATE TABLE public.outlet_printers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  printer_identifier TEXT NOT NULL,
  connection_type public.printer_connection_type NOT NULL DEFAULT 'usb',
  ip_address TEXT,
  port INTEGER,
  paper_size public.printer_paper_size NOT NULL DEFAULT '80mm',
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT outlet_printers_name_not_empty CHECK (LENGTH(TRIM(name)) > 0),
  CONSTRAINT outlet_printers_identifier_not_empty CHECK (LENGTH(TRIM(printer_identifier)) > 0),
  CONSTRAINT outlet_printers_network_requires_ip CHECK (
    connection_type <> 'network'
    OR (ip_address IS NOT NULL AND LENGTH(TRIM(ip_address)) > 0)
    OR (details->>'source') = 'installed'
  ),
  CONSTRAINT outlet_printers_valid_port CHECK (port IS NULL OR (port >= 1 AND port <= 65535))
);

CREATE UNIQUE INDEX idx_outlet_printers_unique_name_per_outlet
  ON public.outlet_printers(outlet_id, LOWER(name));
CREATE INDEX idx_outlet_printers_outlet_id
  ON public.outlet_printers(outlet_id);
CREATE INDEX idx_outlet_printers_connection_type
  ON public.outlet_printers(connection_type);

CREATE TRIGGER update_outlet_printers_updated_at
  BEFORE UPDATE ON public.outlet_printers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 3. Section printer mappings table
-- ============================================================
CREATE TABLE public.section_printer_mappings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  section_id INTEGER NOT NULL REFERENCES public.outlet_sections(id) ON DELETE CASCADE,
  printer_id UUID NOT NULL REFERENCES public.outlet_printers(id) ON DELETE RESTRICT,
  operation public.printer_operation NOT NULL,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT section_printer_mapping_unique_operation UNIQUE(section_id, operation)
);

CREATE INDEX idx_section_printer_mappings_outlet_id
  ON public.section_printer_mappings(outlet_id);
CREATE INDEX idx_section_printer_mappings_section_id
  ON public.section_printer_mappings(section_id);
CREATE INDEX idx_section_printer_mappings_printer_id
  ON public.section_printer_mappings(printer_id);
CREATE INDEX idx_section_printer_mappings_operation
  ON public.section_printer_mappings(operation);

CREATE TRIGGER update_section_printer_mappings_updated_at
  BEFORE UPDATE ON public.section_printer_mappings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- 4. Consistency guards (mapping outlet must match related rows)
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_section_printer_mapping_outlet_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_section_outlet_id UUID;
  v_printer_outlet_id UUID;
BEGIN
  SELECT os.outlet_id INTO v_section_outlet_id
  FROM public.outlet_sections os
  WHERE os.id = NEW.section_id;

  SELECT op.outlet_id INTO v_printer_outlet_id
  FROM public.outlet_printers op
  WHERE op.id = NEW.printer_id;

  IF v_section_outlet_id IS NULL OR v_printer_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Invalid section or printer reference in section printer mapping';
  END IF;

  IF NEW.outlet_id <> v_section_outlet_id OR NEW.outlet_id <> v_printer_outlet_id THEN
    RAISE EXCEPTION 'Section printer mapping outlet mismatch';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_section_printer_mapping_outlet_match_trigger
  BEFORE INSERT OR UPDATE ON public.section_printer_mappings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_section_printer_mapping_outlet_match();

-- ============================================================
-- 5. Views
-- ============================================================
CREATE OR REPLACE VIEW public.outlet_printers_view AS
SELECT
  op.id,
  op.outlet_id,
  o.company_id,
  o.name AS outlet_name,
  op.name,
  op.printer_identifier,
  op.connection_type,
  op.ip_address,
  op.port,
  op.paper_size,
  op.details,
  op.is_active,
  op.created_by,
  CONCAT_WS(' ', creator.first_name, creator.last_name) AS created_by_name,
  op.created_at,
  op.updated_at
FROM public.outlet_printers op
LEFT JOIN public.outlets o ON o.id = op.outlet_id
LEFT JOIN public.users creator ON creator.id = op.created_by;

ALTER VIEW public.outlet_printers_view SET (security_invoker = on);
GRANT SELECT ON public.outlet_printers_view TO authenticated;

CREATE OR REPLACE VIEW public.section_printer_mappings_view AS
SELECT
  spm.id,
  spm.outlet_id,
  o.company_id,
  os.name AS section_name,
  spm.section_id,
  spm.operation,
  spm.printer_id,
  op.name AS printer_name,
  op.connection_type,
  op.printer_identifier,
  op.ip_address,
  op.port,
  op.paper_size,
  spm.created_at,
  spm.updated_at
FROM public.section_printer_mappings spm
JOIN public.outlet_sections os ON os.id = spm.section_id
JOIN public.outlets o ON o.id = spm.outlet_id
JOIN public.outlet_printers op ON op.id = spm.printer_id;

ALTER VIEW public.section_printer_mappings_view SET (security_invoker = on);
GRANT SELECT ON public.section_printer_mappings_view TO authenticated;

-- ============================================================
-- 6. RLS
-- ============================================================
ALTER TABLE public.outlet_printers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.section_printer_mappings ENABLE ROW LEVEL SECURITY;

-- Outlet printers policies
CREATE POLICY "Users can view outlet printers from their outlet"
  ON public.outlet_printers FOR SELECT TO authenticated
  USING (
    outlet_id IN (
      SELECT u.outlet_id
      FROM public.users u
      WHERE u.id = auth.uid()
    )
  );

CREATE POLICY "Super users can manage company outlet printers"
  ON public.outlet_printers FOR ALL TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  )
  WITH CHECK (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

CREATE POLICY "Managers can manage outlet printers"
  ON public.outlet_printers FOR ALL TO authenticated
  USING (
    outlet_id IN (
      SELECT u.outlet_id
      FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'manager'
    )
  )
  WITH CHECK (
    outlet_id IN (
      SELECT u.outlet_id
      FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'manager'
    )
  );

-- Section printer mappings policies
CREATE POLICY "Users can view section printer mappings from their outlet"
  ON public.section_printer_mappings FOR SELECT TO authenticated
  USING (
    outlet_id IN (
      SELECT u.outlet_id
      FROM public.users u
      WHERE u.id = auth.uid()
    )
  );

CREATE POLICY "Super users can manage company section printer mappings"
  ON public.section_printer_mappings FOR ALL TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  )
  WITH CHECK (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid() AND u.role = 'super'
      )
    )
  );

CREATE POLICY "Managers can manage section printer mappings"
  ON public.section_printer_mappings FOR ALL TO authenticated
  USING (
    outlet_id IN (
      SELECT u.outlet_id
      FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'manager'
    )
  )
  WITH CHECK (
    outlet_id IN (
      SELECT u.outlet_id
      FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'manager'
    )
  );

-- ============================================================
-- 7. Grants
-- ============================================================
GRANT ALL ON public.outlet_printers TO authenticated;
GRANT ALL ON public.section_printer_mappings TO authenticated;
