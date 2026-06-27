-- Migration: Create item sales summary reporting view
-- Created: 2026-04-08
-- Description:
--   Adds an aggregated item sales view so the items report can show
--   quantities and totals sold per day, outlet, item, and unit price.

-- ============================================================
-- 1. Item sales summary view
-- ============================================================
CREATE OR REPLACE VIEW public.item_sales_summary_view AS
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
  COALESCE(SUM(siv.total_amount), 0::NUMERIC)::NUMERIC(12, 2) AS gross_amount,
  COALESCE(SUM(siv.allocated_discount), 0::NUMERIC)::NUMERIC(12, 2) AS total_discount,
  COALESCE(SUM(siv.net_amount), 0::NUMERIC)::NUMERIC(12, 2) AS net_amount
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
