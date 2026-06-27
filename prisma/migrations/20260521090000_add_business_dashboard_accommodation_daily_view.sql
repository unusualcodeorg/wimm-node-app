-- ============================================================
-- Migration: Add accommodation daily business dashboard view
-- Created: 2026-05-21
-- Description:
--   - Exposes company-aware accommodation performance metrics for the
--     accounting dashboard executive view

DROP VIEW IF EXISTS public.business_dashboard_accommodation_daily_view;

CREATE VIEW public.business_dashboard_accommodation_daily_view
WITH (security_invoker = true) AS
SELECT
  o.company_id,
  arr.outlet_id,
  arr.report_date AS metric_date,
  arr.property_id,
  arr.property_name,
  arr.currency,
  arr.total_rooms_available,
  arr.rooms_occupied,
  arr.total_room_revenue,
  arr.occupancy_pct,
  arr.revpar
FROM public.accommodation_revpar_report arr
JOIN public.outlets o
  ON o.id = arr.outlet_id;

GRANT SELECT ON public.business_dashboard_accommodation_daily_view TO authenticated;
