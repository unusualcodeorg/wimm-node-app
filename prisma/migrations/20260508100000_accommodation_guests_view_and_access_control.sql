-- ============================================================
-- Migration: accommodation_guests view + access control code
-- ============================================================

-- 1. Add the new access control code for the guests page
INSERT INTO access_controls (code, name, description, area, sort_order)
VALUES (
  'accommodation.guests.view',
  'View accommodation guests',
  'Allows the user to access the accommodation guests list and guest profiles.',
  'accommodation',
  235
)
ON CONFLICT (code) DO NOTHING;

-- 2. Create the accommodation_guests view
--    Aggregates client records that have at least one accommodation booking,
--    with: country name, last visit date, comma-separated booking sources,
--    and total outstanding company/credit bills from sales.
CREATE OR REPLACE VIEW accommodation_guests AS
SELECT
  c.id,
  c.first_name,
  c.last_name,
  c.email,
  c.contact,
  c.address,
  c.nationality,
  -- Resolve country name from countries table, otherwise use raw nationality value
  COALESCE(co.name, c.nationality)               AS country_name,
  c.id_type,
  c.id_number,
  c.created_at,

  -- Booking statistics
  COUNT(DISTINCT b.id)                           AS total_bookings,
  MAX(b.check_out)                               AS last_visit_date,
  STRING_AGG(DISTINCT bs.name, ', ')             AS booking_methods,

  -- Latest booking status
  (
    SELECT b2.status
    FROM accommodation_bookings b2
    WHERE b2.client_id = c.id
    ORDER BY b2.created_at DESC
    LIMIT 1
  )                                              AS latest_booking_status,

  -- Outstanding credit bills total from sales (NC / company settlements)
  COALESCE(
    (
      SELECT SUM(scv.amount)
      FROM sales_creditor_settlements_view scv
      WHERE scv.client_id = c.id
    ),
    0
  )                                              AS outstanding_credit_balance,

  -- Outlet id (from property) — useful for scoped access
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
  OR LOWER(co.name) = LOWER(c.nationality)

GROUP BY
  c.id,
  c.first_name,
  c.last_name,
  c.email,
  c.contact,
  c.address,
  c.nationality,
  co.name,
  c.id_type,
  c.id_number,
  c.created_at,
  p.outlet_id;

-- Grant read access to authenticated users (RLS on underlying tables still applies)
GRANT SELECT ON accommodation_guests TO authenticated;
