-- Migration: Add item shift and order shift RPCs
-- Created: 2026-03-03
-- Description:
--   - Adds shift_confirmed_order_item_to_table RPC
--   - Adds shift_order_to_table RPC

-- ============================================================
-- 1. RPC: Shift confirmed item to another table order
-- ============================================================
CREATE OR REPLACE FUNCTION public.shift_confirmed_order_item_to_table(
  p_order_item_id UUID,
  p_target_table_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_open_status_id INTEGER;
  v_order_company_id BIGINT;
  v_source_order_id UUID;
  v_source_outlet_id UUID;
  v_source_table_id INTEGER;
  v_source_table_name TEXT;
  v_source_waiter_id UUID;
  v_source_mode public.order_mode;
  v_source_status_id INTEGER;
  v_source_business_type public.business_type;
  v_target_outlet_id UUID;
  v_target_order_id UUID;
  v_target_order_mode public.order_mode;
  v_item_status public.order_item_status;
  v_existing_notes TEXT;
  v_shift_note TEXT;
  v_new_notes TEXT;
  v_outlet_day DATE;
  v_next_bill_number INTEGER;
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

  SELECT
    outl.company_id,
    oi.status,
    oi.order_id,
    oi.notes,
    ord.outlet_id,
    ord.table_id,
    st.name,
    ord.waiter_id,
    ord.mode,
    ord.status_id,
    outl.business_type
  INTO
    v_order_company_id,
    v_item_status,
    v_source_order_id,
    v_existing_notes,
    v_source_outlet_id,
    v_source_table_id,
    v_source_table_name,
    v_source_waiter_id,
    v_source_mode,
    v_source_status_id,
    v_source_business_type
  FROM public.order_items oi
  JOIN public.orders ord ON ord.id = oi.order_id
  JOIN public.outlets outl ON outl.id = ord.outlet_id
  LEFT JOIN public.outlet_tables st ON st.id = ord.table_id
  WHERE oi.id = p_order_item_id
  FOR UPDATE OF oi, ord;

  IF v_order_company_id IS NULL THEN
    RAISE EXCEPTION 'Order item % does not exist', p_order_item_id;
  END IF;

  IF v_order_company_id <> v_user_company_id THEN
    RAISE EXCEPTION 'Order item is not accessible for the current user';
  END IF;

  IF v_source_business_type <> 'restaurant_bar'::public.business_type THEN
    RAISE EXCEPTION 'Item shifting is only supported for restaurant outlets';
  END IF;

  IF v_source_mode <> 'DINE'::public.order_mode THEN
    RAISE EXCEPTION 'Only dining order items can be shifted';
  END IF;

  IF v_source_status_id <> v_open_status_id THEN
    RAISE EXCEPTION 'Only OPEN orders can have items shifted';
  END IF;

  IF v_item_status <> 'CONFIRMED'::public.order_item_status THEN
    RAISE EXCEPTION 'Only confirmed items can be shifted';
  END IF;

  IF p_target_table_id = v_source_table_id THEN
    RAISE EXCEPTION 'Select a different target table';
  END IF;

  SELECT os.outlet_id
  INTO v_target_outlet_id
  FROM public.outlet_tables ot
  JOIN public.outlet_sections os ON os.id = ot.section_id
  WHERE ot.id = p_target_table_id
  FOR UPDATE OF ot;

  IF v_target_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Target table % does not exist', p_target_table_id;
  END IF;

  IF v_target_outlet_id <> v_source_outlet_id THEN
    RAISE EXCEPTION 'Items can only be shifted within the same outlet';
  END IF;

  SELECT ord.id, ord.mode
  INTO v_target_order_id, v_target_order_mode
  FROM public.orders ord
  WHERE ord.table_id = p_target_table_id
    AND ord.status_id = v_open_status_id
  ORDER BY ord.created_at DESC
  LIMIT 1;

  IF v_target_order_id IS NULL THEN
    v_outlet_day := public.get_outlet_business_date(v_source_outlet_id);

    INSERT INTO public.outlet_order_counters (outlet_id, last_bill_number)
    VALUES (v_source_outlet_id, 1)
    ON CONFLICT (outlet_id)
    DO UPDATE
      SET last_bill_number = public.outlet_order_counters.last_bill_number + 1,
          updated_at = now()
    RETURNING last_bill_number INTO v_next_bill_number;

    INSERT INTO public.orders (
      bill_number,
      table_id,
      outlet_id,
      date,
      status_id,
      waiter_id,
      mode,
      created_by
    )
    VALUES (
      v_next_bill_number,
      p_target_table_id,
      v_source_outlet_id,
      COALESCE(v_outlet_day, CURRENT_DATE),
      v_open_status_id,
      v_source_waiter_id,
      'DINE'::public.order_mode,
      v_user_id
    )
    RETURNING id INTO v_target_order_id;
  ELSIF v_target_order_mode <> 'DINE'::public.order_mode THEN
    RAISE EXCEPTION 'Target table running order is not a dining order';
  END IF;

  v_shift_note := FORMAT(
    'This item has been shifted from Table %s',
    COALESCE(v_source_table_name, v_source_table_id::TEXT)
  );

  v_new_notes := CASE
    WHEN NULLIF(TRIM(COALESCE(v_existing_notes, '')), '') IS NULL
      THEN v_shift_note
    ELSE TRIM(v_existing_notes) || E'\n' || v_shift_note
  END;

  UPDATE public.order_items
  SET
    order_id = v_target_order_id,
    notes = v_new_notes,
    updated_at = now()
  WHERE id = p_order_item_id;

  RETURN TRUE;
END;
$$;

-- ============================================================
-- 2. RPC: Shift whole open dining order to another empty table
-- ============================================================
CREATE OR REPLACE FUNCTION public.shift_order_to_table(
  p_order_id UUID,
  p_target_table_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_open_status_id INTEGER;
  v_order_company_id BIGINT;
  v_source_table_id INTEGER;
  v_source_outlet_id UUID;
  v_source_mode public.order_mode;
  v_source_status_id INTEGER;
  v_source_business_type public.business_type;
  v_target_outlet_id UUID;
  v_conflicting_order_id UUID;
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

  SELECT
    outl.company_id,
    ord.table_id,
    ord.outlet_id,
    ord.mode,
    ord.status_id,
    outl.business_type
  INTO
    v_order_company_id,
    v_source_table_id,
    v_source_outlet_id,
    v_source_mode,
    v_source_status_id,
    v_source_business_type
  FROM public.orders ord
  JOIN public.outlets outl ON outl.id = ord.outlet_id
  WHERE ord.id = p_order_id
  FOR UPDATE OF ord;

  IF v_order_company_id IS NULL THEN
    RAISE EXCEPTION 'Order % does not exist', p_order_id;
  END IF;

  IF v_order_company_id <> v_user_company_id THEN
    RAISE EXCEPTION 'Order is not accessible for the current user';
  END IF;

  IF v_source_business_type <> 'restaurant_bar'::public.business_type THEN
    RAISE EXCEPTION 'Order shifting is only supported for restaurant outlets';
  END IF;

  IF v_source_mode <> 'DINE'::public.order_mode THEN
    RAISE EXCEPTION 'Only dining orders can be shifted';
  END IF;

  IF v_source_status_id <> v_open_status_id THEN
    RAISE EXCEPTION 'Only OPEN orders can be shifted';
  END IF;

  IF v_source_table_id IS NULL THEN
    RAISE EXCEPTION 'Selected order is not linked to a table';
  END IF;

  IF p_target_table_id = v_source_table_id THEN
    RAISE EXCEPTION 'Select a different target table';
  END IF;

  SELECT os.outlet_id
  INTO v_target_outlet_id
  FROM public.outlet_tables ot
  JOIN public.outlet_sections os ON os.id = ot.section_id
  WHERE ot.id = p_target_table_id
  FOR UPDATE OF ot;

  IF v_target_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Target table % does not exist', p_target_table_id;
  END IF;

  IF v_target_outlet_id <> v_source_outlet_id THEN
    RAISE EXCEPTION 'Order can only be shifted within the same outlet';
  END IF;

  SELECT ord.id
  INTO v_conflicting_order_id
  FROM public.orders ord
  WHERE ord.table_id = p_target_table_id
    AND ord.status_id = v_open_status_id
    AND ord.id <> p_order_id
  LIMIT 1;

  IF v_conflicting_order_id IS NOT NULL THEN
    RAISE EXCEPTION 'Selected table already has a running order';
  END IF;

  UPDATE public.orders
  SET
    table_id = p_target_table_id,
    updated_at = now()
  WHERE id = p_order_id;

  RETURN TRUE;
END;
$$;

-- ============================================================
-- 3. Grants
-- ============================================================
GRANT EXECUTE ON FUNCTION public.shift_confirmed_order_item_to_table(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.shift_order_to_table(UUID, INTEGER) TO authenticated;
