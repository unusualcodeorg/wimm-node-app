-- Migration: Create inventory dashboard views
-- Created: 2026-05-23
-- Description:
--   - Creates outlet-aware inventory dashboard views for current stock position,
--     daily stock flow, procurement activity, low-stock alerts, location value,
--     and recent activity.

-- ============================================================
-- 1. Overview snapshot view
-- ============================================================
CREATE OR REPLACE VIEW public.inventory_dashboard_overview_view
WITH (security_invoker = true) AS
WITH outlet_scope AS (
  SELECT
    o.company_id,
    o.id AS outlet_id
  FROM public.outlets o
),
item_counts AS (
  SELECT
    ii.company_id,
    COUNT(*)::INTEGER AS total_items,
    COUNT(*) FILTER (WHERE ii.is_active)::INTEGER AS active_items
  FROM public.inventory_items ii
  GROUP BY ii.company_id
),
supplier_counts AS (
  SELECT
    s.company_id,
    COUNT(*) FILTER (WHERE s.is_active)::INTEGER AS active_suppliers
  FROM public.inventory_suppliers s
  GROUP BY s.company_id
),
recipe_counts AS (
  SELECT
    os.company_id,
    os.outlet_id,
    COUNT(ir.id) FILTER (
      WHERE ir.is_active
        AND (ir.outlet_id IS NULL OR ir.outlet_id = os.outlet_id)
    )::INTEGER AS active_recipes
  FROM outlet_scope os
  LEFT JOIN public.inventory_recipes ir
    ON ir.company_id = os.company_id
  GROUP BY
    os.company_id,
    os.outlet_id
),
location_counts AS (
  SELECT
    isl.company_id,
    isl.outlet_id,
    COUNT(*) FILTER (WHERE isl.is_active)::INTEGER AS stock_location_count
  FROM public.inventory_stock_locations isl
  GROUP BY
    isl.company_id,
    isl.outlet_id
),
balance_totals AS (
  SELECT
    isb.company_id,
    isb.outlet_id,
    COALESCE(SUM(isb.quantity_on_hand), 0::NUMERIC) AS total_quantity_on_hand,
    COALESCE(SUM(isb.total_value), 0::NUMERIC) AS total_stock_value
  FROM public.inventory_stock_balances isb
  GROUP BY
    isb.company_id,
    isb.outlet_id
),
low_stock_counts AS (
  SELECT
    isb.company_id,
    isb.outlet_id,
    COUNT(*) FILTER (
      WHERE ii.is_active
        AND ii.reorder_level > 0
        AND isb.quantity_on_hand <= ii.reorder_level
    )::INTEGER AS low_stock_item_count
  FROM public.inventory_stock_balances isb
  INNER JOIN public.inventory_items ii
    ON ii.company_id = isb.company_id
    AND ii.id = isb.inventory_item_id
  GROUP BY
    isb.company_id,
    isb.outlet_id
),
invoice_totals AS (
  SELECT
    si.company_id,
    si.outlet_id,
    COUNT(*) FILTER (WHERE si.status <> 'voided')::INTEGER AS purchase_invoice_count,
    COALESCE(SUM(
      CASE
        WHEN si.status <> 'voided'
          THEN si.total_amount
        ELSE 0::NUMERIC
      END
    ), 0::NUMERIC) AS total_purchase_value,
    COALESCE(SUM(
      CASE
        WHEN si.status IN (
          'posted',
          'partially_paid',
          'paid'
        )
          THEN GREATEST(si.total_amount - si.amount_paid, 0::NUMERIC)
        ELSE 0::NUMERIC
      END
    ), 0::NUMERIC) AS outstanding_payables
  FROM public.supplier_invoices si
  GROUP BY
    si.company_id,
    si.outlet_id
)
SELECT
  os.company_id,
  os.outlet_id,
  COALESCE(ic.total_items, 0) AS total_items,
  COALESCE(ic.active_items, 0) AS active_items,
  COALESCE(lc.stock_location_count, 0) AS stock_location_count,
  COALESCE(ls.low_stock_item_count, 0) AS low_stock_item_count,
  COALESCE(bt.total_quantity_on_hand, 0::NUMERIC) AS total_quantity_on_hand,
  COALESCE(bt.total_stock_value, 0::NUMERIC) AS total_stock_value,
  COALESCE(it.purchase_invoice_count, 0) AS purchase_invoice_count,
  COALESCE(it.total_purchase_value, 0::NUMERIC) AS total_purchase_value,
  COALESCE(it.outstanding_payables, 0::NUMERIC) AS outstanding_payables,
  COALESCE(sc.active_suppliers, 0) AS active_suppliers,
  COALESCE(rc.active_recipes, 0) AS active_recipes
FROM outlet_scope os
LEFT JOIN item_counts ic
  ON ic.company_id = os.company_id
LEFT JOIN supplier_counts sc
  ON sc.company_id = os.company_id
LEFT JOIN recipe_counts rc
  ON rc.company_id = os.company_id
  AND rc.outlet_id = os.outlet_id
LEFT JOIN location_counts lc
  ON lc.company_id = os.company_id
  AND lc.outlet_id = os.outlet_id
LEFT JOIN balance_totals bt
  ON bt.company_id = os.company_id
  AND bt.outlet_id = os.outlet_id
LEFT JOIN low_stock_counts ls
  ON ls.company_id = os.company_id
  AND ls.outlet_id = os.outlet_id
LEFT JOIN invoice_totals it
  ON it.company_id = os.company_id
  AND it.outlet_id = os.outlet_id;

COMMENT ON VIEW public.inventory_dashboard_overview_view IS
  'Current outlet-level inventory dashboard overview including stock position, supplier exposure, and purchasing snapshot.';

GRANT SELECT ON public.inventory_dashboard_overview_view TO authenticated;

-- ============================================================
-- 2. Daily stock movement view
-- ============================================================
CREATE OR REPLACE VIEW public.inventory_dashboard_movement_daily_view
WITH (security_invoker = true) AS
SELECT
  ism.company_id,
  ism.outlet_id,
  ism.movement_date::DATE AS metric_date,
  COUNT(*)::INTEGER AS movement_count,
  COALESCE(SUM(
    CASE
      WHEN ism.movement_type IN (
        'purchase_receipt'::public.inventory_stock_movement_type,
        'transfer_in'::public.inventory_stock_movement_type,
        'adjustment_increase'::public.inventory_stock_movement_type
      )
        THEN ism.quantity
      WHEN ism.movement_type = 'stock_count_correction'::public.inventory_stock_movement_type
        AND ism.quantity > 0
        THEN ism.quantity
      ELSE 0::NUMERIC
    END
  ), 0::NUMERIC) AS quantity_in,
  COALESCE(SUM(
    CASE
      WHEN ism.movement_type IN (
        'sale_consumption'::public.inventory_stock_movement_type,
        'transfer_out'::public.inventory_stock_movement_type,
        'adjustment_decrease'::public.inventory_stock_movement_type,
        'wastage'::public.inventory_stock_movement_type,
        'return_to_supplier'::public.inventory_stock_movement_type
      )
        THEN ABS(ism.quantity)
      WHEN ism.movement_type = 'stock_count_correction'::public.inventory_stock_movement_type
        AND ism.quantity < 0
        THEN ABS(ism.quantity)
      ELSE 0::NUMERIC
    END
  ), 0::NUMERIC) AS quantity_out,
  COALESCE(SUM(
    CASE
      WHEN ism.movement_type IN (
        'purchase_receipt'::public.inventory_stock_movement_type,
        'transfer_in'::public.inventory_stock_movement_type,
        'adjustment_increase'::public.inventory_stock_movement_type
      )
        THEN COALESCE(ism.total_cost, 0::NUMERIC)
      WHEN ism.movement_type = 'stock_count_correction'::public.inventory_stock_movement_type
        AND COALESCE(ism.total_cost, 0::NUMERIC) > 0
        THEN COALESCE(ism.total_cost, 0::NUMERIC)
      ELSE 0::NUMERIC
    END
  ), 0::NUMERIC) AS movement_value_in,
  COALESCE(SUM(
    CASE
      WHEN ism.movement_type IN (
        'sale_consumption'::public.inventory_stock_movement_type,
        'transfer_out'::public.inventory_stock_movement_type,
        'adjustment_decrease'::public.inventory_stock_movement_type,
        'wastage'::public.inventory_stock_movement_type,
        'return_to_supplier'::public.inventory_stock_movement_type
      )
        THEN ABS(COALESCE(ism.total_cost, 0::NUMERIC))
      WHEN ism.movement_type = 'stock_count_correction'::public.inventory_stock_movement_type
        AND COALESCE(ism.total_cost, 0::NUMERIC) < 0
        THEN ABS(COALESCE(ism.total_cost, 0::NUMERIC))
      ELSE 0::NUMERIC
    END
  ), 0::NUMERIC) AS movement_value_out,
  COUNT(*) FILTER (WHERE ism.movement_type = 'purchase_receipt'::public.inventory_stock_movement_type)::INTEGER AS purchase_receipt_count,
  COUNT(*) FILTER (WHERE ism.movement_type = 'sale_consumption'::public.inventory_stock_movement_type)::INTEGER AS sale_consumption_count,
  COUNT(*) FILTER (WHERE ism.movement_type = 'wastage'::public.inventory_stock_movement_type)::INTEGER AS wastage_count,
  COUNT(*) FILTER (
    WHERE ism.movement_type IN (
      'adjustment_increase'::public.inventory_stock_movement_type,
      'adjustment_decrease'::public.inventory_stock_movement_type,
      'stock_count_correction'::public.inventory_stock_movement_type
    )
  )::INTEGER AS adjustment_count
FROM public.inventory_stock_movements ism
GROUP BY
  ism.company_id,
  ism.outlet_id,
  ism.movement_date::DATE;

COMMENT ON VIEW public.inventory_dashboard_movement_daily_view IS
  'Daily outlet-level stock movement totals for inventory dashboard charts.';

GRANT SELECT ON public.inventory_dashboard_movement_daily_view TO authenticated;

-- ============================================================
-- 3. Daily purchasing view
-- ============================================================
CREATE OR REPLACE VIEW public.inventory_dashboard_purchase_daily_view
WITH (security_invoker = true) AS
WITH invoice_daily AS (
  SELECT
    si.company_id,
    si.outlet_id,
    si.invoice_date::DATE AS metric_date,
    COUNT(*) FILTER (WHERE si.status <> 'voided')::INTEGER AS invoice_count,
    COALESCE(SUM(
      CASE
        WHEN si.status <> 'voided'
          THEN si.total_amount
        ELSE 0::NUMERIC
      END
    ), 0::NUMERIC) AS purchase_value,
    COALESCE(SUM(
      CASE
        WHEN si.status IN (
          'posted',
          'partially_paid',
          'paid'
        )
          THEN GREATEST(si.total_amount - si.amount_paid, 0::NUMERIC)
        ELSE 0::NUMERIC
      END
    ), 0::NUMERIC) AS outstanding_value
  FROM public.supplier_invoices si
  GROUP BY
    si.company_id,
    si.outlet_id,
    si.invoice_date::DATE
),
payment_daily AS (
  SELECT
    sp.company_id,
    sp.outlet_id,
    sp.payment_date::DATE AS metric_date,
    COUNT(*)::INTEGER AS payment_count,
    COALESCE(SUM(sp.amount), 0::NUMERIC) AS amount_paid
  FROM public.supplier_payments sp
  GROUP BY
    sp.company_id,
    sp.outlet_id,
    sp.payment_date::DATE
)
SELECT
  COALESCE(id.company_id, pd.company_id) AS company_id,
  COALESCE(id.outlet_id, pd.outlet_id) AS outlet_id,
  COALESCE(id.metric_date, pd.metric_date) AS metric_date,
  COALESCE(id.invoice_count, 0) AS invoice_count,
  COALESCE(pd.payment_count, 0) AS payment_count,
  COALESCE(id.purchase_value, 0::NUMERIC) AS purchase_value,
  COALESCE(pd.amount_paid, 0::NUMERIC) AS amount_paid,
  COALESCE(id.outstanding_value, 0::NUMERIC) AS outstanding_value
FROM invoice_daily id
FULL OUTER JOIN payment_daily pd
  ON pd.company_id = id.company_id
  AND pd.outlet_id = id.outlet_id
  AND pd.metric_date = id.metric_date;

COMMENT ON VIEW public.inventory_dashboard_purchase_daily_view IS
  'Daily purchasing and supplier payment totals for inventory dashboard charts.';

GRANT SELECT ON public.inventory_dashboard_purchase_daily_view TO authenticated;

-- ============================================================
-- 4. Low stock alert view
-- ============================================================
CREATE OR REPLACE VIEW public.inventory_dashboard_low_stock_view
WITH (security_invoker = true) AS
SELECT
  isb.company_id,
  isb.outlet_id,
  isb.stock_location_id,
  isl.name AS stock_location_name,
  isb.inventory_item_id,
  ii.name AS item_name,
  ii.sku,
  ii.reorder_level,
  isb.quantity_on_hand,
  GREATEST(ii.reorder_level - isb.quantity_on_hand, 0::NUMERIC) AS deficit_quantity,
  isb.total_value
FROM public.inventory_stock_balances isb
INNER JOIN public.inventory_items ii
  ON ii.company_id = isb.company_id
  AND ii.id = isb.inventory_item_id
INNER JOIN public.inventory_stock_locations isl
  ON isl.company_id = isb.company_id
  AND isl.outlet_id = isb.outlet_id
  AND isl.id = isb.stock_location_id
WHERE ii.is_active
  AND ii.reorder_level > 0
  AND isb.quantity_on_hand <= ii.reorder_level;

COMMENT ON VIEW public.inventory_dashboard_low_stock_view IS
  'Current low-stock rows by outlet, location, and inventory item.';

GRANT SELECT ON public.inventory_dashboard_low_stock_view TO authenticated;

-- ============================================================
-- 5. Stock value by location view
-- ============================================================
CREATE OR REPLACE VIEW public.inventory_dashboard_location_value_view
WITH (security_invoker = true) AS
SELECT
  isb.company_id,
  isb.outlet_id,
  isb.stock_location_id,
  isl.name AS stock_location_name,
  COUNT(*)::INTEGER AS balance_row_count,
  COALESCE(SUM(isb.quantity_on_hand), 0::NUMERIC) AS total_quantity_on_hand,
  COALESCE(SUM(isb.total_value), 0::NUMERIC) AS total_stock_value
FROM public.inventory_stock_balances isb
INNER JOIN public.inventory_stock_locations isl
  ON isl.company_id = isb.company_id
  AND isl.outlet_id = isb.outlet_id
  AND isl.id = isb.stock_location_id
GROUP BY
  isb.company_id,
  isb.outlet_id,
  isb.stock_location_id,
  isl.name;

COMMENT ON VIEW public.inventory_dashboard_location_value_view IS
  'Current stock quantity and value summarized by inventory stock location.';

GRANT SELECT ON public.inventory_dashboard_location_value_view TO authenticated;

-- ============================================================
-- 6. Recent activity feed view
-- ============================================================
CREATE OR REPLACE VIEW public.inventory_dashboard_recent_activity_view
WITH (security_invoker = true) AS
SELECT
  ism.company_id,
  ism.outlet_id,
  'stock_movement'::TEXT AS activity_type,
  ism.id::TEXT AS activity_id,
  ism.created_at AS occurred_at,
  CONCAT(INITCAP(REPLACE(ism.movement_type::TEXT, '_', ' ')), ' • ', ii.name) AS headline,
  CONCAT(
    isl.name,
    CASE
      WHEN ism.reference_type IS NOT NULL
        THEN CONCAT(' • ', INITCAP(REPLACE(ism.reference_type, '_', ' ')))
      ELSE ''
    END,
    CASE
      WHEN ism.reference_id IS NOT NULL
        THEN CONCAT(' #', ism.reference_id)
      ELSE ''
    END
  ) AS detail,
  ism.reference_type,
  ism.reference_id::TEXT AS reference_id,
  ism.quantity,
  COALESCE(ism.total_cost, 0::NUMERIC) AS amount
FROM public.inventory_stock_movements ism
INNER JOIN public.inventory_items ii
  ON ii.company_id = ism.company_id
  AND ii.id = ism.inventory_item_id
INNER JOIN public.inventory_stock_locations isl
  ON isl.company_id = ism.company_id
  AND isl.outlet_id = ism.outlet_id
  AND isl.id = ism.stock_location_id

UNION ALL

SELECT
  si.company_id,
  si.outlet_id,
  'supplier_invoice'::TEXT AS activity_type,
  si.id::TEXT AS activity_id,
  si.created_at AS occurred_at,
  CONCAT('Supplier invoice • ', s.name) AS headline,
  CONCAT(
    COALESCE(NULLIF(si.invoice_number, ''), 'No invoice number'),
    ' • ',
    INITCAP(REPLACE(si.status::TEXT, '_', ' '))
  ) AS detail,
  'supplier_invoice'::TEXT AS reference_type,
  si.id::TEXT AS reference_id,
  NULL::NUMERIC AS quantity,
  si.total_amount AS amount
FROM public.supplier_invoices si
INNER JOIN public.inventory_suppliers s
  ON s.company_id = si.company_id
  AND s.id = si.supplier_id
WHERE si.status <> 'voided'

UNION ALL

SELECT
  sp.company_id,
  sp.outlet_id,
  'supplier_payment'::TEXT AS activity_type,
  sp.id::TEXT AS activity_id,
  sp.created_at AS occurred_at,
  CONCAT('Supplier payment • ', s.name) AS headline,
  COALESCE(NULLIF(sp.reference, ''), 'Payment recorded') AS detail,
  'supplier_payment'::TEXT AS reference_type,
  sp.id::TEXT AS reference_id,
  NULL::NUMERIC AS quantity,
  sp.amount AS amount
FROM public.supplier_payments sp
INNER JOIN public.inventory_suppliers s
  ON s.company_id = sp.company_id
  AND s.id = sp.supplier_id;

COMMENT ON VIEW public.inventory_dashboard_recent_activity_view IS
  'Unified recent inventory activity feed for movements, supplier invoices, and supplier payments.';

GRANT SELECT ON public.inventory_dashboard_recent_activity_view TO authenticated;
