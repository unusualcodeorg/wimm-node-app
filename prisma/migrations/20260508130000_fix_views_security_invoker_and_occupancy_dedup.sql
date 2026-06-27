-- ============================================================
-- Migration: Fix security_invoker on all accommodation views
--            + fix duplicate records in occupancy report view
--
-- All views are recreated with security_invoker = true so that
-- PostgreSQL row-level security policies on underlying tables
-- apply to the authenticated caller rather than the view owner.
--
-- The occupancy view is also fixed: the date_series CTE now
-- selects DISTINCT (property_id, booking_id, stay_date) rows
-- before aggregation, eliminating potential duplicates that
-- arise when a booking record is visited more than once by
-- the lateral join.
-- ============================================================

-- ── 1. Occupancy report (fixed: security_invoker + dedup) ────
DROP VIEW IF EXISTS public.accommodation_occupancy_report;

CREATE VIEW public.accommodation_occupancy_report
WITH (security_invoker = true) AS
WITH date_series AS (
  -- One distinct row per (property, booking, night) — DISTINCT
  -- guards against edge-case duplicates in the source table.
  SELECT DISTINCT
    b.property_id,
    b.id          AS booking_id,
    gs::DATE      AS stay_date
  FROM accommodation_bookings b
  CROSS JOIN LATERAL generate_series(
    b.check_in::DATE,
    (b.check_out::DATE - INTERVAL '1 day')::DATE,
    '1 day'
  ) gs
  WHERE b.status NOT IN ('cancelled', 'no_show')
),
room_counts AS (
  SELECT property_id, COUNT(*) AS total_rooms
  FROM accommodation_rooms
  WHERE is_active = TRUE
  GROUP BY property_id
)
SELECT
  ds.property_id,
  p.outlet_id,
  p.name                                                          AS property_name,
  p.currency,
  ds.stay_date,
  COALESCE(rc.total_rooms, 0)::BIGINT                             AS total_rooms,
  COUNT(DISTINCT ds.booking_id)                                   AS rooms_occupied,
  ROUND(
    COUNT(DISTINCT ds.booking_id)::NUMERIC /
    NULLIF(COALESCE(rc.total_rooms, 0), 0) * 100, 1
  )                                                               AS occupancy_pct
FROM date_series ds
JOIN  accommodation_properties p  ON p.id  = ds.property_id
LEFT JOIN room_counts rc           ON rc.property_id = ds.property_id
GROUP BY
  ds.property_id, p.outlet_id, p.name, p.currency,
  ds.stay_date, rc.total_rooms;

GRANT SELECT ON public.accommodation_occupancy_report TO authenticated;

-- ── 2. Revenue report (security_invoker only) ────────────────
DROP VIEW IF EXISTS public.accommodation_revenue_report;

CREATE VIEW public.accommodation_revenue_report
WITH (security_invoker = true) AS
SELECT
  b.id                                                   AS booking_id,
  b.property_id,
  p.outlet_id,
  p.name                                                 AS property_name,
  p.currency,
  b.check_in,
  b.check_out,
  (b.check_out::DATE - b.check_in::DATE)                 AS nights,
  b.status,
  b.total_amount,
  b.amount_paid,
  GREATEST(b.total_amount - b.amount_paid, 0)            AS balance_due,
  b.adults,
  b.children,
  bs.name                                                AS source_name,
  c.first_name                                           AS client_first_name,
  c.last_name                                            AS client_last_name,
  c.email                                                AS client_email,
  c.nationality                                          AS client_nationality,
  b.created_at
FROM accommodation_bookings b
JOIN  accommodation_properties p         ON p.id  = b.property_id
LEFT JOIN accommodation_booking_sources bs ON bs.id = b.source_id
LEFT JOIN clients c                        ON c.id  = b.client_id
WHERE b.status NOT IN ('cancelled', 'no_show');

GRANT SELECT ON public.accommodation_revenue_report TO authenticated;

-- ── 3. Booking source report (security_invoker only) ─────────
DROP VIEW IF EXISTS public.accommodation_booking_source_report;

CREATE VIEW public.accommodation_booking_source_report
WITH (security_invoker = true) AS
SELECT
  b.property_id,
  p.outlet_id,
  p.name      AS property_name,
  p.currency,
  COALESCE(bs.name, 'Direct / Walk-in')                 AS source_name,
  COUNT(b.id)                                            AS total_bookings,
  COUNT(b.id) FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                                                         AS confirmed_bookings,
  COUNT(b.id) FILTER (WHERE b.status IN ('cancelled','no_show'))
                                                         AS cancelled_bookings,
  COALESCE(
    SUM(b.total_amount) FILTER (WHERE b.status NOT IN ('cancelled','no_show')),
    0
  )                                                      AS total_revenue,
  COALESCE(
    SUM(b.amount_paid) FILTER (WHERE b.status NOT IN ('cancelled','no_show')),
    0
  )                                                      AS total_collected
FROM accommodation_bookings b
JOIN  accommodation_properties p           ON p.id  = b.property_id
LEFT JOIN accommodation_booking_sources bs   ON bs.id = b.source_id
GROUP BY b.property_id, p.outlet_id, p.name, p.currency, bs.name;

GRANT SELECT ON public.accommodation_booking_source_report TO authenticated;

-- ── 4. Night audit report (security_invoker only) ────────────
DROP VIEW IF EXISTS public.accommodation_night_audit_report;

CREATE VIEW public.accommodation_night_audit_report
WITH (security_invoker = true) AS
SELECT
  b.property_id,
  p.outlet_id,
  p.name            AS property_name,
  p.currency,
  b.check_in::DATE  AS audit_date,
  'check_in'::TEXT  AS event_type,
  COUNT(b.id)       AS booking_count,
  SUM(b.total_amount) FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                    AS revenue,
  SUM(b.amount_paid)  FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                    AS collected
FROM accommodation_bookings b
JOIN accommodation_properties p ON p.id = b.property_id
WHERE b.status NOT IN ('cancelled', 'no_show')
GROUP BY b.property_id, p.outlet_id, p.name, p.currency, b.check_in::DATE

UNION ALL

SELECT
  b.property_id,
  p.outlet_id,
  p.name             AS property_name,
  p.currency,
  b.check_out::DATE  AS audit_date,
  'check_out'::TEXT  AS event_type,
  COUNT(b.id)        AS booking_count,
  SUM(b.total_amount) FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                     AS revenue,
  SUM(b.amount_paid)  FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                     AS collected
FROM accommodation_bookings b
JOIN accommodation_properties p ON p.id = b.property_id
WHERE b.status NOT IN ('cancelled', 'no_show')
GROUP BY b.property_id, p.outlet_id, p.name, p.currency, b.check_out::DATE;

GRANT SELECT ON public.accommodation_night_audit_report TO authenticated;

-- ── 5. Accommodation guests (security_invoker only) ──────────
DROP VIEW IF EXISTS public.accommodation_guests;

CREATE VIEW public.accommodation_guests
WITH (security_invoker = true) AS
SELECT
  c.id,
  c.first_name,
  c.last_name,
  c.email,
  c.contact,
  c.address,
  c.nationality,
  COALESCE(co.name, c.nationality)          AS country_name,
  c.id_type,
  c.id_number,
  c.created_at,
  COUNT(DISTINCT b.id)                      AS total_bookings,
  MAX(b.check_out)                          AS last_visit_date,
  STRING_AGG(DISTINCT bs.name, ', ')        AS booking_methods,
  (
    SELECT b2.status
    FROM accommodation_bookings b2
    WHERE b2.client_id = c.id
    ORDER BY b2.created_at DESC
    LIMIT 1
  )                                         AS latest_booking_status,

  -- CREDIT only — NC orders are not-chargeable (free) and carry no debt
  COALESCE(
    (
      SELECT SUM(scv.amount)
      FROM sales_creditor_settlements_view scv
      WHERE scv.client_id = c.id
        AND scv.payment_method_name = 'CREDIT'
    ),
    0
  )                                         AS outstanding_credit_balance,

  p.outlet_id

FROM clients c
INNER JOIN accommodation_bookings b
  ON b.client_id = c.id
LEFT JOIN accommodation_booking_sources bs
  ON bs.id = b.source_id
LEFT JOIN accommodation_properties p
  ON p.id = b.property_id
LEFT JOIN countries co
  ON LOWER(co.iso_code) = LOWER(c.nationality)
  OR LOWER(co.name)     = LOWER(c.nationality)

GROUP BY
  c.id, c.first_name, c.last_name, c.email, c.contact, c.address,
  c.nationality, co.name, c.id_type, c.id_number, c.created_at, p.outlet_id;

GRANT SELECT ON public.accommodation_guests TO authenticated;
