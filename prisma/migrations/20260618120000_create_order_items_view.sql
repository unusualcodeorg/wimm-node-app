-- View: order_items_view
-- Joins order_items with menu_items, departments, and categories so callers
-- get item_name and classification columns without chaining FK lookups.

CREATE OR REPLACE VIEW public.order_items_view AS
SELECT
  oi.id,
  oi.order_id,
  oi.menu_item_id,
  mi.name             AS item_name,
  mi.department_id,
  d.name              AS department_name,
  mi.category_id,
  mc.name             AS category_name,
  oi.quantity,
  oi.unit_price,
  oi.amount,
  oi.notes,
  oi.status,
  oi.kot_id,
  oi.added_by,
  oi.created_at,
  oi.updated_at
FROM public.order_items oi
JOIN      public.menu_items       mi ON mi.id  = oi.menu_item_id
LEFT JOIN public.departments       d  ON  d.id  = mi.department_id
LEFT JOIN public.menu_categories  mc  ON mc.id  = mi.category_id;

ALTER VIEW public.order_items_view SET (security_invoker = on);
GRANT SELECT ON public.order_items_view TO authenticated;
