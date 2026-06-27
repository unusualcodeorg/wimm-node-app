-- Migration: Fix orders outlet bill unique race condition
-- Created: 2026-06-24
-- Description: Wraps the order insertion in an exception block to handle counter desynchronization.

CREATE OR REPLACE FUNCTION public.get_or_create_table_order(
  p_table_id INTEGER,
  p_mode public.order_mode DEFAULT 'DINE'
)
RETURNS SETOF public.orders_view
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_outlet_id UUID;
  v_open_status_id INTEGER;
  v_order_id UUID;
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

  -- Lock selected table row to keep the get/create operation deterministic per table.
  SELECT os.outlet_id
  INTO v_outlet_id
  FROM public.outlet_tables ot
  JOIN public.outlet_sections os ON os.id = ot.section_id
  JOIN public.outlets o ON o.id = os.outlet_id
  WHERE ot.id = p_table_id
    AND o.company_id = v_user_company_id
  FOR UPDATE OF ot;

  IF v_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Table % is not accessible for the current user', p_table_id;
  END IF;

  SELECT pm.id
  INTO v_open_status_id
  FROM public.payment_methods pm
  WHERE pm.name = 'OPEN'
  LIMIT 1;

  IF v_open_status_id IS NULL THEN
    RAISE EXCEPTION 'OPEN payment method is not configured';
  END IF;

  SELECT ord.id
  INTO v_order_id
  FROM public.orders ord
  WHERE ord.table_id = p_table_id
    AND ord.status_id = v_open_status_id
  ORDER BY ord.created_at DESC
  LIMIT 1;

  IF v_order_id IS NULL THEN
    v_outlet_day := public.get_outlet_business_date(v_outlet_id);

    -- 1. Try normal atomic increment from counter
    INSERT INTO public.outlet_order_counters (outlet_id, last_bill_number)
    VALUES (v_outlet_id, 1)
    ON CONFLICT (outlet_id)
    DO UPDATE
      SET last_bill_number = public.outlet_order_counters.last_bill_number + 1,
          updated_at = now()
    RETURNING last_bill_number INTO v_next_bill_number;

    -- 2. Safely wrap insertion to catch duplicate sequence issues
    BEGIN
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
        p_table_id,
        v_outlet_id,
        COALESCE(v_outlet_day, CURRENT_DATE),
        v_open_status_id,
        v_user_id,
        p_mode,
        v_user_id
      )
      RETURNING id INTO v_order_id;

    EXCEPTION
      WHEN unique_violation THEN
        -- Lock the counter row for this outlet to serialize concurrent exception handlers
        PERFORM 1
        FROM public.outlet_order_counters
        WHERE outlet_id = v_outlet_id
        FOR UPDATE;

        -- Safely pull the absolute maximum and increment
        SELECT COALESCE(MAX(bill_number), 0) + 1
        INTO v_next_bill_number
        FROM public.orders
        WHERE outlet_id = v_outlet_id;

        -- Synchronize the counter table back to reality
        INSERT INTO public.outlet_order_counters (outlet_id, last_bill_number)
        VALUES (v_outlet_id, v_next_bill_number)
        ON CONFLICT (outlet_id)
        DO UPDATE
          SET last_bill_number = v_next_bill_number,
              updated_at = now();

        -- Retry order insertion with the guaranteed fresh bill number
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
          p_table_id,
          v_outlet_id,
          COALESCE(v_outlet_day, CURRENT_DATE),
          v_open_status_id,
          v_user_id,
          p_mode,
          v_user_id
        )
        RETURNING id INTO v_order_id;
    END;
  END IF;

  RETURN QUERY
  SELECT ov.*
  FROM public.orders_view ov
  WHERE ov.order_id = v_order_id;
END;
$$;
