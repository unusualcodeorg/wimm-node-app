-- Migration: Create outlet_sections and outlet_tables views
-- Created: 2026-02-11
-- Description: Creates views with joined data for sections and tables,
--   including outlet and company information for easier querying

-- ============================================================
-- 1. Create outlet_sections_view
-- ============================================================
CREATE OR REPLACE VIEW public.outlet_sections_view AS
SELECT
  os.id,
  os.name,
  os.outlet_id,
  os.is_hidden,
  os.created_at,
  os.updated_at,
  o.name AS outlet_name,
  o.company_id,
  COUNT(ot.id) AS table_count
FROM
  public.outlet_sections os
  LEFT JOIN public.outlets o ON os.outlet_id = o.id
  LEFT JOIN public.outlet_tables ot ON ot.section_id = os.id
GROUP BY
  os.id,
  os.name,
  os.outlet_id,
  os.is_hidden,
  os.created_at,
  os.updated_at,
  o.name,
  o.company_id;

-- Enable security invoker to respect RLS policies of underlying tables
ALTER VIEW public.outlet_sections_view SET (security_invoker = on);

-- Grant access to authenticated users
GRANT SELECT ON public.outlet_sections_view TO authenticated;

-- ============================================================
-- 2. Create outlet_tables_view
-- ============================================================
CREATE OR REPLACE VIEW public.outlet_tables_view AS
SELECT
  ot.id,
  ot.name,
  ot.section_id,
  ot.is_hidden,
  ot.created_at,
  ot.updated_at,
  os.name AS section_name,
  os.outlet_id,
  o.name AS outlet_name,
  o.company_id
FROM
  public.outlet_tables ot
  LEFT JOIN public.outlet_sections os ON ot.section_id = os.id
  LEFT JOIN public.outlets o ON os.outlet_id = o.id;

-- Enable security invoker to respect RLS policies of underlying tables
ALTER VIEW public.outlet_tables_view SET (security_invoker = on);

-- Grant access to authenticated users
GRANT SELECT ON public.outlet_tables_view TO authenticated;
