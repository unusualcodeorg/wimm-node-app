-- Migration: Add CREDIT payment method and expand sales reporting views
-- Created: 2026-04-05
-- Description:
--   - Adds CREDIT payment method for client credit settlements
--   - Updates company_settlement to use CREDIT instead of PENDING
--   - Adds reporting views for orders, discounts, and credit/NC activity

-- ============================================================
-- 1. Add CREDIT payment method
-- ============================================================
INSERT INTO public.payment_methods (id, name)
SELECT COALESCE((SELECT MAX(pm.id) + 1 FROM public.payment_methods pm), 10), 'CREDIT'
WHERE NOT EXISTS (
  SELECT 1
  FROM public.payment_methods pm
  WHERE pm.name = 'CREDIT'
);

-- ============================================================
-- 2. Update company settlement RPC to use CREDIT payment method
-- ============================================================
CREATE OR REPLACE FUNCTION public.company_settlement(
  p_order_id UUID,
  p_client_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.order_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_order_company_id BIGINT;
  v_order_status_id INTEGER;
  v_open_status_id INTEGER;
  v_credit_status_id INTEGER;
  v_items_total NUMERIC(12, 2);
  v_discount_total NUMERIC(12, 2);
  v_net_total NUMERIC(12, 2);
  v_settlement_total NUMERIC(12, 2);
  v_pending_item_count INTEGER;
  v_client_company_id BIGINT;
  v_settlement_row public.order_settlements;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_client_id IS NULL THEN
    RAISE EXCEPTION 'Client is required for credit settlement';
  END IF;

  SELECT o.company_id
  INTO v_user_company_id
  FROM public.users u
  JOIN public.outlets o ON o.id = u.outlet_id
  WHERE u.id = v_user_id
  LIMIT 1;

  IF v_user_company_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve company for current user';
  END IF;

  SELECT pm.id
  INTO v_open_status_id
  FROM public.payment_methods pm
  WHERE pm.name = 'OPEN'
  LIMIT 1;

  IF v_open_status_id IS NULL THEN
    RAISE EXCEPTION 'OPEN payment method is not configured';
  END IF;

  SELECT pm.id
  INTO v_credit_status_id
  FROM public.payment_methods pm
  WHERE pm.name = 'CREDIT'
  LIMIT 1;

  IF v_credit_status_id IS NULL THEN
    RAISE EXCEPTION 'CREDIT payment method is not configured';
  END IF;

  SELECT c.company_id
  INTO v_client_company_id
  FROM public.clients c
  WHERE c.id = p_client_id
  LIMIT 1;

  IF v_client_company_id IS NULL THEN
    RAISE EXCEPTION 'Selected client does not exist';
  END IF;

  IF v_client_company_id <> v_user_company_id THEN
    RAISE EXCEPTION 'Selected client is not accessible for the current user';
  END IF;

  SELECT
    outl.company_id,
    ord.status_id
  INTO
    v_order_company_id,
    v_order_status_id
  FROM public.orders ord
  JOIN public.outlets outl ON outl.id = ord.outlet_id
  WHERE ord.id = p_order_id
  FOR UPDATE OF ord;

  IF v_order_company_id IS NULL THEN
    RAISE EXCEPTION 'Order % does not exist', p_order_id;
  END IF;

  IF v_user_company_id <> v_order_company_id THEN
    RAISE EXCEPTION 'Order is not accessible for the current user';
  END IF;

  IF v_order_status_id <> v_open_status_id THEN
    RAISE EXCEPTION 'Only OPEN orders can use credit settlement';
  END IF;

  SELECT
    COALESCE(
      SUM(oi.amount) FILTER (WHERE oi.status <> 'CANCELLED'::public.order_item_status),
      0::NUMERIC
    )::NUMERIC(12, 2),
    COUNT(*) FILTER (WHERE oi.status = 'PENDING'::public.order_item_status)
  INTO
    v_items_total,
    v_pending_item_count
  FROM public.order_items oi
  WHERE oi.order_id = p_order_id;

  IF v_pending_item_count > 0 THEN
    RAISE EXCEPTION 'Order has unconfirmed items. Confirm the order before settlement';
  END IF;

  IF v_items_total <= 0 THEN
    RAISE EXCEPTION 'Cannot settle an empty order';
  END IF;

  SELECT COALESCE(SUM(d.amount), 0)::NUMERIC(12, 2)
  INTO v_discount_total
  FROM public.discounts d
  WHERE d.order_id = p_order_id;

  v_net_total := GREATEST(v_items_total - COALESCE(v_discount_total, 0), 0)::NUMERIC(12, 2);
  IF v_net_total <= 0 THEN
    RAISE EXCEPTION 'Order total after discounts must be greater than zero';
  END IF;

  SELECT COALESCE(SUM(os.amount), 0)::NUMERIC(12, 2)
  INTO v_settlement_total
  FROM public.order_settlements os
  WHERE os.order_id = p_order_id;

  IF v_settlement_total > 0 THEN
    RAISE EXCEPTION 'Order already has settlements';
  END IF;

  INSERT INTO public.order_settlements (
    order_id,
    amount,
    payment_method_id,
    notes,
    created_by
  )
  VALUES (
    p_order_id,
    v_net_total,
    v_credit_status_id,
    NULLIF(TRIM(COALESCE(p_notes, '')), ''),
    v_user_id
  )
  RETURNING *
  INTO v_settlement_row;

  UPDATE public.orders
  SET
    status_id = v_credit_status_id,
    client_id = p_client_id,
    updated_at = now()
  WHERE id = p_order_id;

  RETURN v_settlement_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.company_settlement(UUID, UUID, TEXT) TO authenticated;

-- ============================================================
-- 3. Daily orders reporting view
-- ============================================================
CREATE OR REPLACE VIEW public.sales_orders_view AS
SELECT
  ov.order_id,
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
  ov.status_id,
  ov.status_name,
  ov.client_id,
  ov.client_name,
  ov.waiter_id,
  ov.waiter_name,
  ov.item_count,
  ov.pending_item_count,
  ov.discount_amount::NUMERIC(12, 2) AS discount_amount,
  ov.total_amount::NUMERIC(12, 2) AS total_amount,
  ov.net_amount::NUMERIC(12, 2) AS net_amount,
  ov.settlement_total::NUMERIC(12, 2) AS settlement_total,
  ov.settlement_count,
  ov.balance_amount::NUMERIC(12, 2) AS balance_amount,
  ov.is_fully_settled,
  jsonb_build_object(
    'id', cu.id,
    'first_name', cu.first_name,
    'last_name', cu.last_name,
    'outlet_id', cu.outlet_id
  ) AS created_by,
  ov.created_at,
  ov.updated_at
FROM public.orders_view ov
LEFT JOIN public.users cu ON cu.id = ov.created_by;

ALTER VIEW public.sales_orders_view SET (security_invoker = on);
GRANT SELECT ON public.sales_orders_view TO authenticated;

-- ============================================================
-- 4. Discounts reporting view
-- ============================================================
CREATE OR REPLACE VIEW public.sales_discounts_view AS
SELECT
  d.id,
  d.order_id,
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
  d.amount::NUMERIC(12, 2) AS amount,
  d.notes,
  jsonb_build_object(
    'id', au.id,
    'first_name', au.first_name,
    'last_name', au.last_name,
    'outlet_id', au.outlet_id
  ) AS added_by,
  d.created_at,
  d.updated_at
FROM public.discounts d
JOIN public.orders_view ov ON ov.order_id = d.order_id
LEFT JOIN public.users au ON au.id = d.added_by;

ALTER VIEW public.sales_discounts_view SET (security_invoker = on);
GRANT SELECT ON public.sales_discounts_view TO authenticated;

-- ============================================================
-- 5. Credit and NC settlements reporting view
-- ============================================================
CREATE OR REPLACE VIEW public.sales_creditor_settlements_view AS
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
  c.email AS client_email,
  c.contact AS client_contact,
  os.amount::NUMERIC(12, 2) AS amount,
  os.payment_method_id,
  pm.name AS payment_method_name,
  os.notes,
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
LEFT JOIN public.clients c ON c.id = ov.client_id
LEFT JOIN public.users cu ON cu.id = os.created_by
WHERE pm.name IN ('CREDIT', 'NC');

ALTER VIEW public.sales_creditor_settlements_view SET (security_invoker = on);
GRANT SELECT ON public.sales_creditor_settlements_view TO authenticated;
