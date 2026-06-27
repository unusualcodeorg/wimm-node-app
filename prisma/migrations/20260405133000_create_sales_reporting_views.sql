-- Migration: Create sales reporting views
-- Created: 2026-04-05
-- Description:
--   Adds reporting views for sales, settlements, payment methods, and
--   department-wise analysis so the Sales page can render outlet open-day
--   reports without doing heavy aggregation in the renderer.

-- ============================================================
-- 1. Detailed sales items view
-- ============================================================
CREATE OR REPLACE VIEW public.sales_items_view AS
WITH order_item_totals AS (
  SELECT
    oi.order_id,
    COALESCE(
      SUM(oi.amount) FILTER (WHERE oi.status <> 'CANCELLED'::public.order_item_status),
      0::NUMERIC
    )::NUMERIC(12, 2) AS gross_total
  FROM public.order_items oi
  GROUP BY oi.order_id
)
SELECT
  oi.id,
  mi.name AS item_name,
  oi.order_id,
  ov.bill_number,
  ov.date AS sale_date,
  oi.menu_item_id,
  oi.quantity::NUMERIC(10, 2) AS quantity,
  oi.unit_price::NUMERIC(12, 2) AS unit_price,
  oi.amount::NUMERIC(12, 2) AS total_amount,
  COALESCE(
    CASE
      WHEN oit.gross_total > 0
        THEN ROUND((ov.discount_amount * (oi.amount / oit.gross_total))::NUMERIC, 2)
      ELSE 0::NUMERIC
    END,
    0::NUMERIC
  )::NUMERIC(12, 2) AS allocated_discount,
  GREATEST(
    oi.amount - COALESCE(
      CASE
        WHEN oit.gross_total > 0
          THEN ROUND((ov.discount_amount * (oi.amount / oit.gross_total))::NUMERIC, 2)
        ELSE 0::NUMERIC
      END,
      0::NUMERIC
    ),
    0::NUMERIC
  )::NUMERIC(12, 2) AS net_amount,
  ov.outlet_id,
  ov.company_id,
  ov.outlet_name,
  ov.table_id,
  ov.table_name,
  ov.section_id,
  ov.section_name,
  ov.mode,
  oi.notes,
  oi.status,
  oi.kot_id,
  jsonb_build_object(
    'id', au.id,
    'first_name', au.first_name,
    'last_name', au.last_name
  ) AS added_by,
  mi.department_id,
  d.name AS department_name,
  mi.category_id,
  mc.name AS category_name,
  ov.waiter_id,
  ov.waiter_name,
  ov.client_id,
  ov.client_name,
  oi.created_at,
  oi.updated_at
FROM public.order_items oi
JOIN public.orders_view ov ON ov.order_id = oi.order_id
JOIN public.menu_items mi ON mi.id = oi.menu_item_id
LEFT JOIN public.menu_categories mc ON mc.id = mi.category_id
LEFT JOIN public.departments d ON d.id = mi.department_id
LEFT JOIN public.users au ON au.id = oi.added_by
LEFT JOIN order_item_totals oit ON oit.order_id = oi.order_id;

ALTER VIEW public.sales_items_view SET (security_invoker = on);
GRANT SELECT ON public.sales_items_view TO authenticated;

-- ============================================================
-- 2. Detailed settlement view
-- ============================================================
CREATE OR REPLACE VIEW public.order_settlements_view AS
SELECT
  os.id,
  os.order_id,
  ov.bill_number,
  ov.date AS sale_date,
  ov.outlet_id,
  ov.company_id,
  ov.outlet_name,
  ov.table_id,
  ov.table_name,
  ov.section_id,
  ov.section_name,
  ov.mode,
  ov.client_id,
  ov.client_name,
  ov.waiter_id,
  ov.waiter_name,
  os.amount::NUMERIC(12, 2) AS amount,
  os.payment_method_id,
  pm.name AS payment_method_name,
  os.notes,
  ov.total_amount::NUMERIC(12, 2) AS order_total_amount,
  ov.discount_amount::NUMERIC(12, 2) AS order_discount_amount,
  ov.net_amount::NUMERIC(12, 2) AS order_net_amount,
  ov.balance_amount::NUMERIC(12, 2) AS order_balance_amount,
  jsonb_build_object(
    'id', cu.id,
    'first_name', cu.first_name,
    'last_name', cu.last_name,
    'outlet_id', cu.outlet_id
  ) AS created_by,
  os.created_at,
  os.created_at AS updated_at
FROM public.order_settlements os
JOIN public.orders_view ov ON ov.order_id = os.order_id
JOIN public.payment_methods pm ON pm.id = os.payment_method_id
LEFT JOIN public.users cu ON cu.id = os.created_by;

ALTER VIEW public.order_settlements_view SET (security_invoker = on);
GRANT SELECT ON public.order_settlements_view TO authenticated;

-- ============================================================
-- 3. Daily sales summary view
-- ============================================================
CREATE OR REPLACE VIEW public.sales_summary_view AS
SELECT
  ov.date AS sale_date,
  ov.outlet_id,
  ov.company_id,
  ov.outlet_name,
  COUNT(*) FILTER (WHERE ov.settlement_count > 0) AS settled_order_count,
  COALESCE(SUM(ov.settlement_count), 0) AS settlement_count,
  COALESCE(SUM(ov.total_amount), 0)::NUMERIC(12, 2) AS gross_sale,
  COALESCE(SUM(ov.discount_amount), 0)::NUMERIC(12, 2) AS total_discount,
  COALESCE(SUM(ov.net_amount), 0)::NUMERIC(12, 2) AS total_sale,
  COALESCE(SUM(ov.settlement_total), 0)::NUMERIC(12, 2) AS total_settlement_amount,
  CASE
    WHEN COUNT(*) FILTER (WHERE ov.settlement_count > 0) > 0
      THEN ROUND(
        (
          COALESCE(SUM(ov.net_amount), 0) /
          COUNT(*) FILTER (WHERE ov.settlement_count > 0)
        )::NUMERIC,
        2
      )
    ELSE 0::NUMERIC
  END::NUMERIC(12, 2) AS average_bill_amount
FROM public.orders_view ov
WHERE ov.settlement_count > 0
GROUP BY ov.date, ov.outlet_id, ov.company_id, ov.outlet_name;

ALTER VIEW public.sales_summary_view SET (security_invoker = on);
GRANT SELECT ON public.sales_summary_view TO authenticated;

-- ============================================================
-- 4. Payment method breakdown view
-- ============================================================
CREATE OR REPLACE VIEW public.payment_method_sales_summary_view AS
SELECT
  osv.sale_date,
  osv.outlet_id,
  osv.company_id,
  osv.outlet_name,
  osv.payment_method_id,
  osv.payment_method_name,
  COUNT(*) AS settlement_count,
  COUNT(DISTINCT osv.order_id) AS settled_order_count,
  COALESCE(SUM(osv.amount), 0)::NUMERIC(12, 2) AS total_amount
FROM public.order_settlements_view osv
GROUP BY
  osv.sale_date,
  osv.outlet_id,
  osv.company_id,
  osv.outlet_name,
  osv.payment_method_id,
  osv.payment_method_name;

ALTER VIEW public.payment_method_sales_summary_view SET (security_invoker = on);
GRANT SELECT ON public.payment_method_sales_summary_view TO authenticated;

-- ============================================================
-- 5. Department-wise sales summary view
-- ============================================================
CREATE OR REPLACE VIEW public.department_sales_summary_view AS
SELECT
  siv.sale_date,
  siv.outlet_id,
  siv.company_id,
  siv.outlet_name,
  siv.department_id,
  COALESCE(NULLIF(TRIM(siv.department_name), ''), 'Unassigned') AS department_name,
  COUNT(*) FILTER (WHERE siv.status <> 'CANCELLED'::public.order_item_status) AS item_count,
  COALESCE(
    SUM(siv.quantity) FILTER (WHERE siv.status <> 'CANCELLED'::public.order_item_status),
    0::NUMERIC
  )::NUMERIC(12, 2) AS quantity_sold,
  COALESCE(
    SUM(siv.total_amount) FILTER (WHERE siv.status <> 'CANCELLED'::public.order_item_status),
    0::NUMERIC
  )::NUMERIC(12, 2) AS gross_sale,
  COALESCE(
    SUM(siv.allocated_discount) FILTER (WHERE siv.status <> 'CANCELLED'::public.order_item_status),
    0::NUMERIC
  )::NUMERIC(12, 2) AS total_discount,
  COALESCE(
    SUM(siv.net_amount) FILTER (WHERE siv.status <> 'CANCELLED'::public.order_item_status),
    0::NUMERIC
  )::NUMERIC(12, 2) AS total_sale
FROM public.sales_items_view siv
JOIN public.orders_view ov ON ov.order_id = siv.order_id
WHERE ov.settlement_count > 0
GROUP BY
  siv.sale_date,
  siv.outlet_id,
  siv.company_id,
  siv.outlet_name,
  siv.department_id,
  COALESCE(NULLIF(TRIM(siv.department_name), ''), 'Unassigned');

ALTER VIEW public.department_sales_summary_view SET (security_invoker = on);
GRANT SELECT ON public.department_sales_summary_view TO authenticated;
