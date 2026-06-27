-- Migration: Create inventory stock movements view
-- Created: 2026-06-09
-- Description:
--   - Adds a read-optimized stock movements view
--   - Resolves order bill numbers without renderer-side follow-up queries
--   - Avoids querying public.orders with a non-existent company_id column

CREATE OR REPLACE VIEW public.inventory_stock_movements_view
WITH (security_invoker = true) AS
SELECT
  ism.id,
  ism.company_id,
  ism.outlet_id,
  ism.stock_location_id,
  ism.inventory_item_id,
  ism.movement_type,
  ism.reference_type,
  ism.reference_id,
  CASE
    WHEN ism.reference_type = 'order' THEN ov.bill_number
    ELSE NULL::INTEGER
  END AS order_bill_number,
  ism.quantity,
  ism.unit_cost,
  ism.total_cost,
  ism.movement_date,
  ism.created_by,
  ism.created_at
FROM public.inventory_stock_movements ism
LEFT JOIN public.orders_view ov
  ON ism.reference_type = 'order'
 AND ov.order_id::TEXT = ism.reference_id
 AND ov.outlet_id = ism.outlet_id
 AND ov.company_id = ism.company_id;

COMMENT ON VIEW public.inventory_stock_movements_view IS
  'Read-optimized inventory stock movement history with order bill number enrichment.';

GRANT SELECT ON public.inventory_stock_movements_view TO authenticated;
