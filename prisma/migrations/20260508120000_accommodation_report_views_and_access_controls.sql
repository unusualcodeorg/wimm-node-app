-- ============================================================
-- Migration: Accommodation report access controls + DB views
-- ============================================================

-- ── 1. Access control codes ──────────────────────────────────

INSERT INTO access_controls (code, name, description, area, sort_order)
VALUES
  ('accommodation.reports.occupancy',
   'View occupancy report',
   'Allows the user to view the accommodation occupancy and room utilisation report.',
   'accommodation', 252),
  ('accommodation.reports.revenue',
   'View revenue report',
   'Allows the user to view booking revenue, collected amounts and outstanding balances.',
   'accommodation', 254),
  ('accommodation.reports.booking_source',
   'View booking source report',
   'Allows the user to view revenue and booking counts broken down by booking source.',
   'accommodation', 256),
  ('accommodation.reports.night_audit',
   'View night audit report',
   'Allows the user to view the daily night audit (check-ins, check-outs, revenue).',
   'accommodation', 258)
ON CONFLICT (code) DO NOTHING;

-- ── 2. Occupancy report view ─────────────────────────────────
--    One row per (property, calendar_date).
--    Requires a generate_series to expand date ranges.
CREATE OR REPLACE VIEW accommodation_occupancy_report AS
WITH date_series AS (
  -- Expand each booking into per-night rows
  SELECT
    b.property_id,
    b.id          AS booking_id,
    b.status,
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
  p.name              AS property_name,
  p.currency,
  ds.stay_date,
  rc.total_rooms,
  COUNT(DISTINCT ds.booking_id)                                       AS rooms_occupied,
  ROUND(
    COUNT(DISTINCT ds.booking_id)::NUMERIC /
    NULLIF(rc.total_rooms, 0) * 100, 1
  )                                                                   AS occupancy_pct
FROM date_series ds
JOIN accommodation_properties p  ON p.id = ds.property_id
LEFT JOIN room_counts rc         ON rc.property_id = ds.property_id
GROUP BY
  ds.property_id, p.outlet_id, p.name, p.currency,
  ds.stay_date, rc.total_rooms;

GRANT SELECT ON accommodation_occupancy_report TO authenticated;

-- ── 3. Revenue report view ───────────────────────────────────
--    One row per booking (non-cancelled), with payment totals.
CREATE OR REPLACE VIEW accommodation_revenue_report AS
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
JOIN accommodation_properties p  ON p.id  = b.property_id
LEFT JOIN accommodation_booking_sources bs ON bs.id = b.source_id
LEFT JOIN clients c               ON c.id  = b.client_id
WHERE b.status NOT IN ('cancelled', 'no_show');

GRANT SELECT ON accommodation_revenue_report TO authenticated;

-- ── 4. Booking source report view ────────────────────────────
--    Aggregated by property + source.
CREATE OR REPLACE VIEW accommodation_booking_source_report AS
SELECT
  b.property_id,
  p.outlet_id,
  p.name      AS property_name,
  p.currency,
  COALESCE(bs.name, 'Direct / Walk-in') AS source_name,
  COUNT(b.id)                           AS total_bookings,
  COUNT(b.id) FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                                        AS confirmed_bookings,
  COUNT(b.id) FILTER (WHERE b.status IN ('cancelled','no_show'))
                                        AS cancelled_bookings,
  COALESCE(
    SUM(b.total_amount) FILTER (WHERE b.status NOT IN ('cancelled','no_show')),
    0
  )                                     AS total_revenue,
  COALESCE(
    SUM(b.amount_paid) FILTER (WHERE b.status NOT IN ('cancelled','no_show')),
    0
  )                                     AS total_collected
FROM accommodation_bookings b
JOIN accommodation_properties p        ON p.id  = b.property_id
LEFT JOIN accommodation_booking_sources bs ON bs.id = b.source_id
GROUP BY b.property_id, p.outlet_id, p.name, p.currency, bs.name;

GRANT SELECT ON accommodation_booking_source_report TO authenticated;

-- ── 5. Night audit view ──────────────────────────────────────
--    One row per (property, audit_date) showing daily activity.
CREATE OR REPLACE VIEW accommodation_night_audit_report AS
SELECT
  b.property_id,
  p.outlet_id,
  p.name     AS property_name,
  p.currency,

  -- Check-ins on this date
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
  p.name     AS property_name,
  p.currency,
  b.check_out::DATE AS audit_date,
  'check_out'::TEXT AS event_type,
  COUNT(b.id)       AS booking_count,
  SUM(b.total_amount) FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                    AS revenue,
  SUM(b.amount_paid)  FILTER (WHERE b.status NOT IN ('cancelled','no_show'))
                    AS collected

FROM accommodation_bookings b
JOIN accommodation_properties p ON p.id = b.property_id
WHERE b.status NOT IN ('cancelled', 'no_show')
GROUP BY b.property_id, p.outlet_id, p.name, p.currency, b.check_out::DATE;

GRANT SELECT ON accommodation_night_audit_report TO authenticated;
