-- ============================================================
-- Migration: Fix accommodation_guests outstanding_credit_balance
--
-- NC (Not Chargeable) orders are FREE orders — they have zero
-- financial obligation. Only CREDIT settlements represent
-- actual money owed by a guest.
-- This recreates the view filtering to CREDIT only.
-- ============================================================

CREATE OR REPLACE VIEW accommodation_guests AS
SELECT
  c.id,
  c.first_name,
  c.last_name,
  c.email,
  c.contact,
  c.address,
  c.nationality,
  COALESCE(co.name, c.nationality) AS country_name,
  c.id_type,
  c.id_number,
  c.created_at,
  COUNT(DISTINCT b.id)             AS total_bookings,
  MAX(b.check_out)                 AS last_visit_date,
  STRING_AGG(DISTINCT bs.name, ', ') AS booking_methods,
  (
    SELECT b2.status
    FROM accommodation_bookings b2
    WHERE b2.client_id = c.id
    ORDER BY b2.created_at DESC
    LIMIT 1
  ) AS latest_booking_status,

  -- CREDIT only — NC orders are not-chargeable (free) and carry no debt
  COALESCE(
    (
      SELECT SUM(scv.amount)
      FROM sales_creditor_settlements_view scv
      WHERE scv.client_id = c.id
        AND scv.payment_method_name = 'CREDIT'
    ),
    0
  ) AS outstanding_credit_balance,

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
  c.id, c.first_name, c.last_name, c.email, c.contact, c.address,
  c.nationality, co.name, c.id_type, c.id_number, c.created_at, p.outlet_id;

GRANT SELECT ON accommodation_guests TO authenticated;
