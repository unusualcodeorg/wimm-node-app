-- Migration: Add business day transition helpers
-- Created: 2026-04-05
-- Description:
--   - Allows system-generated cancelled settlements with zero amount
--   - Adds compatibility helpers for reading/updating outlet business day
--   - Adds an atomic business-day transition function for edge-function use

-- ============================================================
-- 1. Allow zero-amount settlements for system auto-cancel flow
-- ============================================================
ALTER TABLE public.order_settlements
DROP CONSTRAINT IF EXISTS order_settlements_amount_check;

ALTER TABLE public.order_settlements
ADD CONSTRAINT order_settlements_amount_check
CHECK (amount >= 0);

-- ============================================================
-- 2. Helper: set outlet business date across schema variants
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_outlet_business_date(
  p_outlet_id UUID,
  p_business_date DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_day_opened_at BOOLEAN;
  v_has_day_open BOOLEAN;
  v_day_open_data_type TEXT;
BEGIN
  IF p_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Outlet id is required';
  END IF;

  IF p_business_date IS NULL THEN
    RAISE EXCEPTION 'Business date is required';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'outlets'
      AND c.column_name = 'day_opened_at'
  )
  INTO v_has_day_opened_at;

  IF v_has_day_opened_at THEN
    EXECUTE
      'UPDATE public.outlets SET day_opened_at = $1, updated_at = now() WHERE id = $2'
      USING p_business_date, p_outlet_id;
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'outlets'
      AND c.column_name = 'day_open'
  )
  INTO v_has_day_open;

  IF v_has_day_open THEN
    SELECT c.data_type
    INTO v_day_open_data_type
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'outlets'
      AND c.column_name = 'day_open'
    LIMIT 1;

    IF v_day_open_data_type IN ('date', 'timestamp without time zone', 'timestamp with time zone') THEN
      EXECUTE
        'UPDATE public.outlets SET day_open = $1, updated_at = now() WHERE id = $2'
        USING p_business_date, p_outlet_id;
      RETURN;
    END IF;
  END IF;

  RAISE EXCEPTION 'No compatible outlet business date column found';
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_outlet_business_date(UUID, DATE) TO authenticated;

-- ============================================================
-- 3. Atomic business-day transition helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.transition_outlet_business_day(
  p_outlet_id UUID,
  p_user_id UUID,
  p_target_date DATE
)
RETURNS TABLE (
  previous_business_day DATE,
  next_business_day DATE,
  auto_cancelled_empty_order_count INTEGER,
  blocked_order_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_business_day DATE;
  v_open_status_id INTEGER;
  v_cancelled_status_id INTEGER;
  v_empty_order_ids UUID[];
  v_empty_order_count INTEGER := 0;
  v_blocked_order_count INTEGER := 0;
  v_outlet_company_id BIGINT;
  v_user_outlet_id UUID;
BEGIN
  IF p_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Outlet id is required';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User id is required';
  END IF;

  IF p_target_date IS NULL THEN
    RAISE EXCEPTION 'Target business date is required';
  END IF;

  SELECT o.company_id
  INTO v_outlet_company_id
  FROM public.outlets o
  WHERE o.id = p_outlet_id
  FOR UPDATE;

  IF v_outlet_company_id IS NULL THEN
    RAISE EXCEPTION 'Outlet % does not exist', p_outlet_id;
  END IF;

  SELECT u.outlet_id
  INTO v_user_outlet_id
  FROM public.users u
  WHERE u.id = p_user_id
  LIMIT 1;

  IF v_user_outlet_id IS NULL THEN
    RAISE EXCEPTION 'User % is not linked to any outlet', p_user_id;
  END IF;

  IF v_user_outlet_id <> p_outlet_id THEN
    RAISE EXCEPTION 'User is not allowed to open a new day for this outlet';
  END IF;

  v_current_business_day := public.get_outlet_business_date(p_outlet_id);

  IF p_target_date <= v_current_business_day THEN
    RAISE EXCEPTION 'Select a date that is after the current business day';
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
  INTO v_cancelled_status_id
  FROM public.payment_methods pm
  WHERE pm.name = 'CANCELLED'
  LIMIT 1;

  IF v_cancelled_status_id IS NULL THEN
    RAISE EXCEPTION 'CANCELLED payment method is not configured';
  END IF;

  WITH open_orders AS (
    SELECT ord.id
    FROM public.orders ord
    WHERE ord.outlet_id = p_outlet_id
      AND ord.date = v_current_business_day
      AND ord.status_id = v_open_status_id
    FOR UPDATE OF ord
  ),
  item_counts AS (
    SELECT
      oo.id AS order_id,
      COALESCE(oi.item_count, 0) AS item_count
    FROM open_orders oo
    LEFT JOIN (
      SELECT
        order_id,
        COUNT(*)::INTEGER AS item_count
      FROM public.order_items
      WHERE order_id IN (SELECT id FROM open_orders)
      GROUP BY order_id
    ) oi ON oi.order_id = oo.id
  )
  SELECT
    COALESCE(COUNT(*) FILTER (WHERE item_count > 0), 0)::INTEGER,
    COALESCE(
      ARRAY_AGG(order_id) FILTER (WHERE item_count = 0),
      ARRAY[]::UUID[]
    )
  INTO
    v_blocked_order_count,
    v_empty_order_ids
  FROM item_counts;

  IF v_blocked_order_count > 0 THEN
    RAISE EXCEPTION 'You have running orders, kindly settle them before opening a new day';
  END IF;

  v_empty_order_count := COALESCE(array_length(v_empty_order_ids, 1), 0);

  IF v_empty_order_count > 0 THEN
    INSERT INTO public.order_settlements (
      order_id,
      amount,
      payment_method_id,
      notes,
      created_by
    )
    SELECT
      empty_order_id,
      0::NUMERIC(12, 2),
      v_cancelled_status_id,
      'Automatically settled by system since order has no items',
      p_user_id
    FROM unnest(v_empty_order_ids) AS empty_order_id;

    UPDATE public.orders ord
    SET
      status_id = v_cancelled_status_id,
      updated_at = now()
    WHERE ord.id = ANY(v_empty_order_ids);
  END IF;

  PERFORM public.set_outlet_business_date(p_outlet_id, p_target_date);

  RETURN QUERY
  SELECT
    v_current_business_day,
    p_target_date,
    v_empty_order_count,
    v_blocked_order_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.transition_outlet_business_day(UUID, UUID, DATE) TO authenticated;
