-- Migration: Fix order date column compatibility for outlets.day_open/day_opened_at
-- Created: 2026-02-13
-- Description:
--   Some environments expose outlet business day as `day_opened_at` while others
--   have `day_open`. This migration adds a compatibility helper and updates
--   order functions to avoid hard-coded column references.

-- ============================================================
-- 1. Helper: resolve outlet business date across schema variants
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_outlet_business_date(p_outlet_id UUID)
RETURNS DATE
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_business_date DATE;
  v_has_day_opened_at BOOLEAN;
  v_has_day_open BOOLEAN;
  v_day_open_data_type TEXT;
BEGIN
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
      'SELECT COALESCE(day_opened_at::date, CURRENT_DATE) FROM public.outlets WHERE id = $1'
      INTO v_business_date
      USING p_outlet_id;

    RETURN COALESCE(v_business_date, CURRENT_DATE);
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

    -- Only use day_open when it is date/time based.
    IF v_day_open_data_type IN ('date', 'timestamp without time zone', 'timestamp with time zone') THEN
      EXECUTE
        'SELECT COALESCE(day_open::date, CURRENT_DATE) FROM public.outlets WHERE id = $1'
        INTO v_business_date
        USING p_outlet_id;

      RETURN COALESCE(v_business_date, CURRENT_DATE);
    END IF;
  END IF;

  RETURN CURRENT_DATE;
END;
$$;

-- ============================================================
-- 2. Update trigger function for orders defaults/validation
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_order_defaults_and_validate()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_table_outlet_id UUID;
  v_outlet_day DATE;
  v_order_company_id BIGINT;
  v_client_company_id BIGINT;
BEGIN
  SELECT os.outlet_id
  INTO v_table_outlet_id
  FROM public.outlet_tables ot
  JOIN public.outlet_sections os ON os.id = ot.section_id
  WHERE ot.id = NEW.table_id
  LIMIT 1;

  IF v_table_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Invalid table_id % for order', NEW.table_id;
  END IF;

  -- Enforce outlet from the selected table to prevent mismatches.
  NEW.outlet_id := v_table_outlet_id;

  IF NEW.date IS NULL THEN
    v_outlet_day := public.get_outlet_business_date(v_table_outlet_id);
    NEW.date := COALESCE(v_outlet_day, CURRENT_DATE);
  END IF;

  IF NEW.waiter_id IS NULL THEN
    NEW.waiter_id := auth.uid();
  END IF;

  IF NEW.created_by IS NULL THEN
    NEW.created_by := auth.uid();
  END IF;

  IF NEW.client_id IS NOT NULL THEN
    SELECT o.company_id
    INTO v_order_company_id
    FROM public.outlets o
    WHERE o.id = v_table_outlet_id;

    SELECT c.company_id
    INTO v_client_company_id
    FROM public.clients c
    WHERE c.id = NEW.client_id;

    IF v_client_company_id IS NULL THEN
      RAISE EXCEPTION 'Invalid client_id % for order', NEW.client_id;
    END IF;

    IF v_order_company_id <> v_client_company_id THEN
      RAISE EXCEPTION 'Selected client does not belong to the order company';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. Update get_or_create_table_order RPC
-- ============================================================
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

    INSERT INTO public.outlet_order_counters (outlet_id, last_bill_number)
    VALUES (v_outlet_id, 1)
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
      p_table_id,
      v_outlet_id,
      COALESCE(v_outlet_day, CURRENT_DATE),
      v_open_status_id,
      v_user_id,
      p_mode,
      v_user_id
    )
    RETURNING id INTO v_order_id;
  END IF;

  RETURN QUERY
  SELECT ov.*
  FROM public.orders_view ov
  WHERE ov.order_id = v_order_id;
END;
$$;

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT EXECUTE ON FUNCTION public.get_outlet_business_date(UUID) TO authenticated;

