-- Migration: Add item_cancellations_report_view
-- Created: 2026-06-11
-- Description:
--   Adds a reporting view that joins item_cancellations with orders,
--   menu_items, and users so the sales report can display per-day
--   cancelled item details. RLS on item_cancellations already exists
--   from 20260214164000; this migration only adds the view.

CREATE OR REPLACE VIEW public.item_cancellations_report_view WITH (security_invoker = true) AS
SELECT
  ic.id,
  ic.order_id,
  o.bill_number,
  o.date           AS sale_date,
  o.outlet_id,
  ot.company_id,
  mi.name          AS item_name,
  mi.base_price    AS unit_price,
  ic.reason,
  ic.created_at,
  jsonb_build_object(
    'id',         u.id,
    'first_name', u.first_name,
    'last_name',  u.last_name
  ) AS cancelled_by
FROM public.item_cancellations ic
JOIN public.orders     o  ON o.id  = ic.order_id
JOIN public.outlets    ot ON ot.id = o.outlet_id
JOIN public.menu_items mi ON mi.id = ic.menu_item_id
LEFT JOIN public.users u  ON u.id  = ic.cancelled_by;
