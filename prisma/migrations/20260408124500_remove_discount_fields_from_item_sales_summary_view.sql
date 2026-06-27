-- Migration: Remove discount fields from item sales summary reporting
-- Created: 2026-04-08
-- Description:
--   Simplifies the item sales summary view so it only reflects item
--   quantities and gross sales totals without bill-level discount allocation.

DROP VIEW IF EXISTS public.item_sales_summary_view;

CREATE VIEW public.item_sales_summary_view AS
SELECT
  md5(
    CONCAT_WS(
      '::',
      siv.sale_date::TEXT,
      siv.outlet_id::TEXT,
      siv.menu_item_id::TEXT,
      siv.unit_price::TEXT
    )
  ) AS id,
  siv.sale_date,
  siv.outlet_id,
  siv.company_id,
  siv.outlet_name,
  siv.menu_item_id,
  siv.item_name,
  siv.department_id,
  COALESCE(NULLIF(TRIM(siv.department_name), ''), 'Unassigned') AS department_name,
  siv.category_id,
  COALESCE(NULLIF(TRIM(siv.category_name), ''), 'Unassigned') AS category_name,
  siv.unit_price::NUMERIC(12, 2) AS unit_price,
  COUNT(DISTINCT siv.order_id) AS order_count,
  COALESCE(SUM(siv.quantity), 0::NUMERIC)::NUMERIC(12, 2) AS quantity_sold,
  COALESCE(SUM(siv.total_amount), 0::NUMERIC)::NUMERIC(12, 2) AS gross_amount
FROM public.sales_items_view siv
JOIN public.sales_orders_view sov ON sov.order_id = siv.order_id
WHERE sov.settlement_count > 0
  AND siv.status <> 'CANCELLED'::public.order_item_status
GROUP BY
  siv.sale_date,
  siv.outlet_id,
  siv.company_id,
  siv.outlet_name,
  siv.menu_item_id,
  siv.item_name,
  siv.department_id,
  COALESCE(NULLIF(TRIM(siv.department_name), ''), 'Unassigned'),
  siv.category_id,
  COALESCE(NULLIF(TRIM(siv.category_name), ''), 'Unassigned'),
  siv.unit_price;

ALTER VIEW public.item_sales_summary_view SET (security_invoker = on);
GRANT SELECT ON public.item_sales_summary_view TO authenticated;
