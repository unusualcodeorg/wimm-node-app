-- Migration: Add sales bill printing access control
-- Created: 2026-04-09
-- Description:
--   - Adds a dedicated access control for printing bills from the sales page

INSERT INTO public.access_controls (code, name, description, area, sort_order)
VALUES (
  'sales.bills.print',
  'Print bills',
  'Allows the user to print customer bills from the sales page.',
  'sales',
  185
)
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  area = EXCLUDED.area,
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();
