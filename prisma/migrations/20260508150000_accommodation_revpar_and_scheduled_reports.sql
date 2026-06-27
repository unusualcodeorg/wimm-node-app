-- ============================================================
-- Migration: Accommodation RevPAR reporting + scheduled reports
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

INSERT INTO public.access_controls (code, name, description, area, sort_order)
VALUES (
  'accommodation.reports.revpar',
  'View RevPAR report',
  'Allows the user to view the Revenue Per Available Room (RevPAR) report and trends.',
  'accommodation',
  260
)
ON CONFLICT (code) DO NOTHING;

DROP VIEW IF EXISTS public.accommodation_booking_daily_revenue;

CREATE VIEW public.accommodation_booking_daily_revenue
WITH (security_invoker = true) AS
WITH booking_rooms AS (
  SELECT
    abr.booking_id,
    string_agg(ar.room_number, ', ' ORDER BY ar.room_number) AS room_names
  FROM public.accommodation_booking_rooms abr
  JOIN public.accommodation_rooms ar
    ON ar.id = abr.room_id
  GROUP BY abr.booking_id
),
expanded_bookings AS (
  SELECT
    b.id AS booking_id,
    b.property_id,
    p.outlet_id,
    p.name AS property_name,
    p.currency,
    b.check_in::DATE AS check_in,
    b.check_out::DATE AS check_out,
    GREATEST((b.check_out::DATE - b.check_in::DATE), 1) AS nights,
    b.status,
    COALESCE(b.total_amount, 0)::NUMERIC AS total_amount,
    COALESCE(b.amount_paid, 0)::NUMERIC AS amount_paid,
    COALESCE(bs.name, 'Direct / Walk-in') AS source_name,
    c.first_name AS client_first_name,
    c.last_name AS client_last_name,
    COALESCE(br.room_names, 'Unassigned') AS room_names,
    gs::DATE AS stay_date
  FROM public.accommodation_bookings b
  JOIN public.accommodation_properties p
    ON p.id = b.property_id
  LEFT JOIN public.accommodation_booking_sources bs
    ON bs.id = b.source_id
  LEFT JOIN public.clients c
    ON c.id = b.client_id
  LEFT JOIN booking_rooms br
    ON br.booking_id = b.id
  CROSS JOIN LATERAL generate_series(
    b.check_in::DATE,
    GREATEST((b.check_out::DATE - INTERVAL '1 day')::DATE, b.check_in::DATE),
    '1 day'
  ) gs
  WHERE b.status NOT IN ('cancelled', 'no_show')
)
SELECT
  eb.booking_id,
  eb.property_id,
  eb.outlet_id,
  eb.property_name,
  eb.currency,
  eb.stay_date,
  eb.check_in,
  eb.check_out,
  eb.nights,
  eb.status,
  eb.total_amount,
  eb.amount_paid,
  GREATEST(eb.total_amount - eb.amount_paid, 0) AS balance_due,
  eb.source_name,
  eb.client_first_name,
  eb.client_last_name,
  eb.room_names,
  ROUND(eb.total_amount / eb.nights::NUMERIC, 2) AS daily_revenue
FROM expanded_bookings eb;

GRANT SELECT ON public.accommodation_booking_daily_revenue TO authenticated;

DROP VIEW IF EXISTS public.accommodation_revpar_report;

CREATE VIEW public.accommodation_revpar_report
WITH (security_invoker = true) AS
WITH room_inventory AS (
  SELECT
    p.id AS property_id,
    p.outlet_id,
    p.name AS property_name,
    p.currency,
    COUNT(r.id)::INT AS total_rooms_available
  FROM public.accommodation_properties p
  LEFT JOIN public.accommodation_rooms r
    ON r.property_id = p.id
   AND r.is_active = TRUE
  GROUP BY p.id, p.outlet_id, p.name, p.currency
),
date_bounds AS (
  SELECT
    p.id AS property_id,
    COALESCE(MIN(b.check_in)::DATE, CURRENT_DATE) AS start_date,
    GREATEST(
      COALESCE(
        MAX(GREATEST((b.check_out::DATE - INTERVAL '1 day')::DATE, b.check_in::DATE)),
        CURRENT_DATE
      ),
      (CURRENT_DATE + INTERVAL '90 days')::DATE
    ) AS end_date
  FROM public.accommodation_properties p
  LEFT JOIN public.accommodation_bookings b
    ON b.property_id = p.id
   AND b.status NOT IN ('cancelled', 'no_show')
  GROUP BY p.id
),
calendar AS (
  SELECT
    ri.property_id,
    ri.outlet_id,
    ri.property_name,
    ri.currency,
    ri.total_rooms_available,
    gs::DATE AS report_date
  FROM room_inventory ri
  JOIN date_bounds db
    ON db.property_id = ri.property_id
  CROSS JOIN LATERAL generate_series(
    db.start_date,
    db.end_date,
    '1 day'
  ) gs
),
daily_revenue AS (
  SELECT
    property_id,
    stay_date AS report_date,
    ROUND(SUM(daily_revenue), 2) AS total_room_revenue
  FROM public.accommodation_booking_daily_revenue
  GROUP BY property_id, stay_date
),
daily_occupancy AS (
  SELECT
    b.property_id,
    gs::DATE AS report_date,
    COUNT(DISTINCT abr.room_id)::INT AS rooms_occupied
  FROM public.accommodation_bookings b
  JOIN public.accommodation_booking_rooms abr
    ON abr.booking_id = b.id
  CROSS JOIN LATERAL generate_series(
    b.check_in::DATE,
    GREATEST((b.check_out::DATE - INTERVAL '1 day')::DATE, b.check_in::DATE),
    '1 day'
  ) gs
  WHERE b.status NOT IN ('cancelled', 'no_show')
  GROUP BY b.property_id, gs::DATE
)
SELECT
  c.property_id,
  c.outlet_id,
  c.property_name,
  c.currency,
  c.report_date,
  c.total_rooms_available,
  COALESCE(o.rooms_occupied, 0) AS rooms_occupied,
  COALESCE(r.total_room_revenue, 0)::NUMERIC(12, 2) AS total_room_revenue,
  CASE
    WHEN c.total_rooms_available > 0 THEN
      ROUND(
        COALESCE(o.rooms_occupied, 0)::NUMERIC /
        c.total_rooms_available::NUMERIC * 100,
        1
      )
    ELSE 0
  END AS occupancy_pct,
  CASE
    WHEN c.total_rooms_available > 0 THEN
      ROUND(
        COALESCE(r.total_room_revenue, 0) /
        c.total_rooms_available::NUMERIC,
        2
      )
    ELSE 0
  END AS revpar
FROM calendar c
LEFT JOIN daily_revenue r
  ON r.property_id = c.property_id
 AND r.report_date = c.report_date
LEFT JOIN daily_occupancy o
  ON o.property_id = c.property_id
 AND o.report_date = c.report_date;

GRANT SELECT ON public.accommodation_revpar_report TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'daily-accommodation-report-dispatch'
  ) THEN
    PERFORM cron.schedule(
      'daily-accommodation-report-dispatch',
      '0 7 * * *',
      $job$
      SELECT public.invoke_internal_edge_function(
        'daily-accommodation-reports',
        '{}'::jsonb
      );
      $job$
    );
  END IF;
END;
$$;
