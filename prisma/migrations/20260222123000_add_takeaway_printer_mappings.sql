-- Migration: Add takeaway printer mappings by device and department
-- Created: 2026-02-22
-- Description:
--   - Adds takeaway_printer_mappings for sectionless order printing
--   - Routes KOT by department per device and BILL/RECEIPT per device
--   - Adds view + RLS policies

-- ============================================================
-- 1. Takeaway printer mappings table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.takeaway_printer_mappings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  printer_id UUID NOT NULL REFERENCES public.outlet_printers(id) ON DELETE RESTRICT,
  operation public.printer_operation NOT NULL,
  department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT takeaway_printer_mappings_device_not_empty CHECK (LENGTH(TRIM(device_id)) > 0),
  CONSTRAINT takeaway_printer_mappings_operation_rule CHECK (
    (operation = 'KOT' AND department_id IS NOT NULL)
    OR (operation IN ('BILL', 'RECEIPT') AND department_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_outlet_id
  ON public.takeaway_printer_mappings(outlet_id);

CREATE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_device_id
  ON public.takeaway_printer_mappings(device_id);

CREATE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_printer_id
  ON public.takeaway_printer_mappings(printer_id);

CREATE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_department_id
  ON public.takeaway_printer_mappings(department_id);

CREATE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_operation
  ON public.takeaway_printer_mappings(operation);

CREATE UNIQUE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_unique_device_department_kot
  ON public.takeaway_printer_mappings(outlet_id, device_id, department_id)
  WHERE operation = 'KOT';

CREATE UNIQUE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_unique_device_bill
  ON public.takeaway_printer_mappings(outlet_id, device_id)
  WHERE operation = 'BILL';

CREATE UNIQUE INDEX IF NOT EXISTS idx_takeaway_printer_mappings_unique_device_receipt
  ON public.takeaway_printer_mappings(outlet_id, device_id)
  WHERE operation = 'RECEIPT';

DROP TRIGGER IF EXISTS update_takeaway_printer_mappings_updated_at ON public.takeaway_printer_mappings;
CREATE TRIGGER update_takeaway_printer_mappings_updated_at
  BEFORE UPDATE ON public.takeaway_printer_mappings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 2. Consistency guard
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_takeaway_printer_mapping_outlet_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_printer_outlet_id UUID;
  v_department_outlet_id UUID;
BEGIN
  SELECT op.outlet_id INTO v_printer_outlet_id
  FROM public.outlet_printers op
  WHERE op.id = NEW.printer_id;

  IF v_printer_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Invalid printer reference in takeaway printer mapping';
  END IF;

  IF NEW.outlet_id <> v_printer_outlet_id THEN
    RAISE EXCEPTION 'Takeaway printer mapping outlet mismatch';
  END IF;

  IF NEW.department_id IS NOT NULL THEN
    SELECT d.outlet_id INTO v_department_outlet_id
    FROM public.departments d
    WHERE d.id = NEW.department_id;

    IF v_department_outlet_id IS NULL THEN
      RAISE EXCEPTION 'Invalid department reference in takeaway printer mapping';
    END IF;

    IF NEW.outlet_id <> v_department_outlet_id THEN
      RAISE EXCEPTION 'Takeaway printer mapping department outlet mismatch';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_takeaway_printer_mapping_outlet_match_trigger
  ON public.takeaway_printer_mappings;

CREATE TRIGGER enforce_takeaway_printer_mapping_outlet_match_trigger
  BEFORE INSERT OR UPDATE ON public.takeaway_printer_mappings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_takeaway_printer_mapping_outlet_match();

-- ============================================================
-- 3. View
-- ============================================================
CREATE OR REPLACE VIEW public.takeaway_printer_mappings_view AS
SELECT
  tpm.id,
  tpm.outlet_id,
  o.company_id,
  tpm.device_id,
  tpm.operation,
  tpm.department_id,
  d.name AS department_name,
  tpm.printer_id,
  op.name AS printer_name,
  op.connection_type,
  op.printer_identifier,
  op.ip_address,
  op.port,
  op.paper_size,
  tpm.created_at,
  tpm.updated_at
FROM public.takeaway_printer_mappings tpm
JOIN public.outlets o ON o.id = tpm.outlet_id
JOIN public.outlet_printers op ON op.id = tpm.printer_id
LEFT JOIN public.departments d ON d.id = tpm.department_id;

ALTER VIEW public.takeaway_printer_mappings_view SET (security_invoker = on);
GRANT SELECT ON public.takeaway_printer_mappings_view TO authenticated;

-- ============================================================
-- 4. RLS
-- ============================================================
ALTER TABLE public.takeaway_printer_mappings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view takeaway printer mappings from their outlet"
  ON public.takeaway_printer_mappings FOR SELECT TO authenticated
  USING (
    outlet_id IN (
      SELECT u.outlet_id
      FROM public.users u
      WHERE u.id = auth.uid()
    )
  );

CREATE POLICY "Super users can manage company takeaway printer mappings"
  ON public.takeaway_printer_mappings FOR ALL TO authenticated
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

CREATE POLICY "Managers can manage takeaway printer mappings"
  ON public.takeaway_printer_mappings FOR ALL TO authenticated
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
-- 5. Grants
-- ============================================================
GRANT ALL ON public.takeaway_printer_mappings TO authenticated;
