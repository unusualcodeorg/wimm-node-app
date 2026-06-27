-- Migration: Add direct settlement RPC
-- Created: 2026-02-14
-- Description:
--   Adds direct_settlement(order_id, payment_method_id) to validate and
--   settle OPEN orders in a single payment method.

CREATE OR REPLACE FUNCTION public.direct_settlement(
  p_order_id UUID,
  p_payment_method_id INTEGER,
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
  v_payment_method_name TEXT;
  v_items_total NUMERIC(12, 2);
  v_discount_total NUMERIC(12, 2);
  v_net_total NUMERIC(12, 2);
  v_settlement_total NUMERIC(12, 2);
  v_balance_amount NUMERIC(12, 2);
  v_pending_item_count INTEGER;
  v_settlement_row public.order_settlements;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
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

  SELECT pm.name
  INTO v_payment_method_name
  FROM public.payment_methods pm
  WHERE pm.id = p_payment_method_id
  LIMIT 1;

  IF v_payment_method_name IS NULL THEN
    RAISE EXCEPTION 'Invalid payment method';
  END IF;

  IF v_payment_method_name NOT IN ('CASH', 'CARD', 'MOBILE MONEY', 'CHECK', 'EFT') THEN
    RAISE EXCEPTION 'Unsupported direct settlement payment method: %', v_payment_method_name;
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
    RAISE EXCEPTION 'Only OPEN orders can be settled directly';
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
    RAISE EXCEPTION 'Order already has settlements. Use split settlement for additional payments';
  END IF;

  v_balance_amount := GREATEST(v_net_total - v_settlement_total, 0)::NUMERIC(12, 2);

  IF v_balance_amount <= 0 THEN
    RAISE EXCEPTION 'Order is already fully settled';
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
    v_balance_amount,
    p_payment_method_id,
    NULLIF(TRIM(COALESCE(p_notes, '')), ''),
    v_user_id
  )
  RETURNING *
  INTO v_settlement_row;

  UPDATE public.orders
  SET
    status_id = p_payment_method_id,
    updated_at = now()
  WHERE id = p_order_id;

  RETURN v_settlement_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.direct_settlement(UUID, INTEGER, TEXT) TO authenticated;
