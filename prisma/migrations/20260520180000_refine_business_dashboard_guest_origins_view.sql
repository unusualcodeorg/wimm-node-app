-- ============================================================
-- Migration: Refine business dashboard guest origins view
-- Created: 2026-05-20
-- Description:
--   - Adds metric_date grain to guest-origin reporting
--   - Allows accounting dashboard period filters to work correctly

DROP VIEW IF EXISTS public.business_dashboard_guest_origins_view;

CREATE VIEW public.business_dashboard_guest_origins_view
WITH (security_invoker = true) AS
SELECT
  o.company_id,
  ap.outlet_id,
  ab.check_in AS metric_date,
  COALESCE(ab.guest_country_id, c.country_id)::TEXT AS country_id,
  co.name AS country_name,
  co.iso_code AS country_iso_code,
  COUNT(DISTINCT ab.id)::INT AS bookings_count,
  ROUND(COALESCE(SUM(ab.total_amount), 0), 2) AS total_revenue,
  ROUND(COALESCE(SUM(ab.amount_paid), 0), 2) AS total_paid
FROM public.accommodation_bookings ab
JOIN public.accommodation_properties ap
  ON ap.id = ab.property_id
JOIN public.outlets o
  ON o.id = ap.outlet_id
LEFT JOIN public.clients c
  ON c.id = ab.client_id
LEFT JOIN public.countries co
  ON co.id = COALESCE(ab.guest_country_id, c.country_id)
WHERE ab.status NOT IN (
  'cancelled'::public.accommodation_booking_status,
  'no_show'::public.accommodation_booking_status
)
GROUP BY
  o.company_id,
  ap.outlet_id,
  ab.check_in,
  COALESCE(ab.guest_country_id, c.country_id)::TEXT,
  co.name,
  co.iso_code;

GRANT SELECT ON public.business_dashboard_guest_origins_view TO authenticated;
