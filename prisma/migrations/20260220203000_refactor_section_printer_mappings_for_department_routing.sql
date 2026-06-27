-- Migration: Refactor section printer mappings for department-based KOT routing
-- Created: 2026-02-20
-- Description:
--   - Adds department_id to section_printer_mappings
--   - Enforces KOT mappings per department and BILL/RECEIPT mappings per section
--   - Backfills existing section-level KOT mappings into department-level mappings
--   - Updates view payload for renderer to include department data

-- ============================================================
-- 1. Add department_id to section printer mappings
-- ============================================================
ALTER TABLE public.section_printer_mappings
ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES public.departments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_section_printer_mappings_department_id
  ON public.section_printer_mappings(department_id);

-- ============================================================
-- 2. Drop legacy uniqueness before KOT backfill
-- ============================================================
ALTER TABLE public.section_printer_mappings
DROP CONSTRAINT IF EXISTS section_printer_mapping_unique_operation;

-- ============================================================
-- 3. Backfill legacy KOT rows (section-level) to department-level rows
-- ============================================================
INSERT INTO public.section_printer_mappings (
  outlet_id,
  section_id,
  printer_id,
  operation,
  department_id,
  created_by,
  created_at,
  updated_at
)
SELECT
  spm.outlet_id,
  spm.section_id,
  spm.printer_id,
  'KOT'::public.printer_operation,
  d.id AS department_id,
  spm.created_by,
  now(),
  now()
FROM public.section_printer_mappings spm
JOIN public.departments d
  ON d.outlet_id = spm.outlet_id
 AND d.status = 'active'
WHERE spm.operation = 'KOT'
  AND spm.department_id IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.section_printer_mappings existing
    WHERE existing.section_id = spm.section_id
      AND existing.operation = 'KOT'
      AND existing.department_id = d.id
  );

DELETE FROM public.section_printer_mappings
WHERE operation = 'KOT'
  AND department_id IS NULL;

-- ============================================================
-- 4. Replace uniqueness/check rules to support department mappings
-- ============================================================
ALTER TABLE public.section_printer_mappings
DROP CONSTRAINT IF EXISTS section_printer_mapping_department_rule;

ALTER TABLE public.section_printer_mappings
ADD CONSTRAINT section_printer_mapping_department_rule CHECK (
  (operation = 'KOT' AND department_id IS NOT NULL)
  OR (operation IN ('BILL', 'RECEIPT') AND department_id IS NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_section_printer_mappings_unique_section_department_kot
  ON public.section_printer_mappings(section_id, department_id)
  WHERE operation = 'KOT';

CREATE UNIQUE INDEX IF NOT EXISTS idx_section_printer_mappings_unique_section_bill
  ON public.section_printer_mappings(section_id)
  WHERE operation = 'BILL';

CREATE UNIQUE INDEX IF NOT EXISTS idx_section_printer_mappings_unique_section_receipt
  ON public.section_printer_mappings(section_id)
  WHERE operation = 'RECEIPT';

-- ============================================================
-- 5. Update outlet consistency trigger for department mappings
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_section_printer_mapping_outlet_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_section_outlet_id UUID;
  v_printer_outlet_id UUID;
  v_department_outlet_id UUID;
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

  IF NEW.department_id IS NOT NULL THEN
    SELECT d.outlet_id INTO v_department_outlet_id
    FROM public.departments d
    WHERE d.id = NEW.department_id;

    IF v_department_outlet_id IS NULL THEN
      RAISE EXCEPTION 'Invalid department reference in section printer mapping';
    END IF;

    IF NEW.outlet_id <> v_department_outlet_id THEN
      RAISE EXCEPTION 'Section printer mapping department outlet mismatch';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 6. Update view for frontend querying
-- ============================================================
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
  spm.updated_at,
  spm.department_id,
  d.name AS department_name
FROM public.section_printer_mappings spm
JOIN public.outlet_sections os ON os.id = spm.section_id
JOIN public.outlets o ON o.id = spm.outlet_id
JOIN public.outlet_printers op ON op.id = spm.printer_id
LEFT JOIN public.departments d ON d.id = spm.department_id;

ALTER VIEW public.section_printer_mappings_view SET (security_invoker = on);
GRANT SELECT ON public.section_printer_mappings_view TO authenticated;
