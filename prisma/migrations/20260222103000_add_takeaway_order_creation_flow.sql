-- Migration: Add takeaway/cash order creation flow without table assignment
-- Created: 2026-02-22
-- Description:
--   - Allows orders without table_id for TAKEAWAY/CASH
--   - Enforces DINE vs TAKEAWAY/CASH table rules
--   - Updates order validation trigger for table-less modes
--   - Updates orders_view to include table-less orders
--   - Adds create_takeaway_order(outlet_id) RPC with outlet-business-type mode mapping

-- ============================================================
-- 1. Allow table-less orders and enforce mode/table consistency
-- ============================================================
ALTER TABLE public.orders
ALTER COLUMN table_id DROP NOT NULL;

ALTER TABLE public.orders
DROP CONSTRAINT IF EXISTS orders_mode_table_rule;

ALTER TABLE public.orders
ADD CONSTRAINT orders_mode_table_rule CHECK (
  (mode = 'DINE'::public.order_mode AND table_id IS NOT NULL)
  OR (mode IN ('TAKEAWAY'::public.order_mode, 'CASH'::public.order_mode) AND table_id IS NULL)
);

-- ============================================================
-- 2. Update order validation/default trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_order_defaults_and_validate()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_table_outlet_id UUID;
  v_effective_outlet_id UUID;
  v_outlet_day DATE;
  v_order_company_id BIGINT;
  v_client_company_id BIGINT;
BEGIN
  IF NEW.mode = 'DINE'::public.order_mode THEN
    IF NEW.table_id IS NULL THEN
      RAISE EXCEPTION 'DINE orders require a table';
    END IF;

    SELECT os.outlet_id
    INTO v_table_outlet_id
    FROM public.outlet_tables ot
    JOIN public.outlet_sections os ON os.id = ot.section_id
    WHERE ot.id = NEW.table_id
    LIMIT 1;

    IF v_table_outlet_id IS NULL THEN
      RAISE EXCEPTION 'Invalid table_id % for order', NEW.table_id;
    END IF;

    NEW.outlet_id := v_table_outlet_id;
  ELSE
    NEW.table_id := NULL;

    IF NEW.outlet_id IS NULL THEN
      SELECT u.outlet_id
      INTO v_effective_outlet_id
      FROM public.users u
      WHERE u.id = auth.uid()
      LIMIT 1;

      NEW.outlet_id := v_effective_outlet_id;
    END IF;

    IF NEW.outlet_id IS NULL THEN
      RAISE EXCEPTION 'TAKEAWAY/CASH orders require outlet context';
    END IF;
  END IF;

  IF NEW.date IS NULL THEN
    v_outlet_day := public.get_outlet_business_date(NEW.outlet_id);
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
    WHERE o.id = NEW.outlet_id;

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
-- 3. Include table-less orders in orders_view
-- ============================================================
CREATE OR REPLACE VIEW public.orders_view AS
WITH order_totals AS (
  SELECT
    oi.order_id,
    COALESCE(
      SUM(oi.amount) FILTER (WHERE oi.status <> 'CANCELLED'::public.order_item_status),
      0::NUMERIC
    )::NUMERIC(12, 2) AS total_amount,
    COUNT(*) FILTER (WHERE oi.status <> 'CANCELLED'::public.order_item_status) AS item_count,
    COUNT(*) FILTER (WHERE oi.status = 'PENDING'::public.order_item_status) AS pending_item_count
  FROM public.order_items oi
  GROUP BY oi.order_id
),
discount_totals AS (
  SELECT
    d.order_id,
    COALESCE(SUM(d.amount), 0)::NUMERIC(12, 2) AS discount_amount,
    COUNT(*) AS discount_count,
    MAX(d.created_at) AS last_discount_at
  FROM public.discounts d
  GROUP BY d.order_id
),
settlement_totals AS (
  SELECT
    os.order_id,
    COALESCE(SUM(os.amount), 0)::NUMERIC(12, 2) AS settlement_total,
    COUNT(*) AS settlement_count,
    ARRAY_REMOVE(ARRAY_AGG(DISTINCT pm.name), NULL) AS settlement_methods,
    MAX(os.created_at) AS last_settlement_at
  FROM public.order_settlements os
  JOIN public.payment_methods pm ON pm.id = os.payment_method_id
  GROUP BY os.order_id
)
SELECT
  o.id AS order_id,
  o.bill_number,
  o.table_id,
  COALESCE(
    ot.name,
    CASE
      WHEN o.mode = 'TAKEAWAY'::public.order_mode THEN 'TAKEAWAY'
      WHEN o.mode = 'CASH'::public.order_mode THEN 'CASH'
      ELSE 'N/A'
    END
  ) AS table_name,
  os.id AS section_id,
  COALESCE(
    os.name,
    CASE
      WHEN o.mode = 'CASH'::public.order_mode THEN 'CASH'
      ELSE 'TAKEAWAY'
    END
  ) AS section_name,
  o.outlet_id,
  outl.name AS outlet_name,
  outl.company_id,
  o.date,
  o.status_id,
  pm.name AS status_name,
  o.waiter_id,
  TRIM(CONCAT(COALESCE(w.first_name, ''), ' ', COALESCE(w.last_name, ''))) AS waiter_name,
  o.client_id,
  CASE
    WHEN c.id IS NULL THEN NULL
    ELSE TRIM(CONCAT(COALESCE(c.first_name, ''), ' ', COALESCE(c.last_name, '')))
  END AS client_name,
  o.mode,
  COALESCE(dt.discount_amount, 0::NUMERIC)::NUMERIC(12, 2) AS discount_amount,
  COALESCE(otals.total_amount, 0::NUMERIC)::NUMERIC(12, 2) AS total_amount,
  GREATEST(
    COALESCE(otals.total_amount, 0::NUMERIC) - COALESCE(dt.discount_amount, 0::NUMERIC),
    0::NUMERIC
  )::NUMERIC(12, 2) AS net_amount,
  COALESCE(otals.item_count, 0) AS item_count,
  COALESCE(otals.pending_item_count, 0) AS pending_item_count,
  (COALESCE(otals.pending_item_count, 0) > 0) AS has_pending_items,
  o.created_by,
  o.created_at,
  o.updated_at,
  TRIM(CONCAT(COALESCE(cu.first_name, ''), ' ', COALESCE(cu.last_name, ''))) AS creator_name,
  cu.email AS creator_email,
  COALESCE(dt.discount_count, 0) AS discount_count,
  dt.last_discount_at,
  COALESCE(st.settlement_total, 0::NUMERIC)::NUMERIC(12, 2) AS settlement_total,
  COALESCE(st.settlement_count, 0) AS settlement_count,
  COALESCE(st.settlement_methods, ARRAY[]::TEXT[]) AS settlement_methods,
  st.last_settlement_at,
  GREATEST(
    (
      COALESCE(otals.total_amount, 0::NUMERIC) - COALESCE(dt.discount_amount, 0::NUMERIC)
    ) - COALESCE(st.settlement_total, 0::NUMERIC),
    0::NUMERIC
  )::NUMERIC(12, 2) AS balance_amount,
  (
    COALESCE(st.settlement_total, 0::NUMERIC) >=
    GREATEST(
      COALESCE(otals.total_amount, 0::NUMERIC) - COALESCE(dt.discount_amount, 0::NUMERIC),
      0::NUMERIC
    )
  ) AS is_fully_settled
FROM public.orders o
LEFT JOIN public.outlet_tables ot ON ot.id = o.table_id
LEFT JOIN public.outlet_sections os ON os.id = ot.section_id
JOIN public.outlets outl ON outl.id = o.outlet_id
JOIN public.payment_methods pm ON pm.id = o.status_id
LEFT JOIN public.users w ON w.id = o.waiter_id
LEFT JOIN public.users cu ON cu.id = o.created_by
LEFT JOIN public.clients c ON c.id = o.client_id
LEFT JOIN order_totals otals ON otals.order_id = o.id
LEFT JOIN discount_totals dt ON dt.order_id = o.id
LEFT JOIN settlement_totals st ON st.order_id = o.id;

ALTER VIEW public.orders_view SET (security_invoker = on);

-- ============================================================
-- 4. Create takeaway order RPC
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_takeaway_order(
  p_outlet_id UUID DEFAULT NULL
)
RETURNS SETOF public.orders_view
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_target_outlet_id UUID;
  v_open_status_id INTEGER;
  v_order_id UUID;
  v_outlet_day DATE;
  v_next_bill_number INTEGER;
  v_outlet_business_type public.business_type;
  v_order_mode public.order_mode;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT o.company_id, u.outlet_id
  INTO v_user_company_id, v_target_outlet_id
  FROM public.users u
  JOIN public.outlets o ON o.id = u.outlet_id
  WHERE u.id = v_user_id
  LIMIT 1;

  IF v_user_company_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve company for current user';
  END IF;

  IF p_outlet_id IS NOT NULL THEN
    v_target_outlet_id := p_outlet_id;
  END IF;

  IF v_target_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve outlet for takeaway order';
  END IF;

  SELECT o.business_type
  INTO v_outlet_business_type
  FROM public.outlets o
  WHERE o.id = v_target_outlet_id
    AND o.company_id = v_user_company_id
  LIMIT 1;

  IF v_outlet_business_type IS NULL THEN
    RAISE EXCEPTION 'Outlet % is not accessible for the current user', v_target_outlet_id;
  END IF;

  SELECT pm.id
  INTO v_open_status_id
  FROM public.payment_methods pm
  WHERE pm.name = 'OPEN'
  LIMIT 1;

  IF v_open_status_id IS NULL THEN
    RAISE EXCEPTION 'OPEN payment method is not configured';
  END IF;

  v_outlet_day := public.get_outlet_business_date(v_target_outlet_id);

  INSERT INTO public.outlet_order_counters (outlet_id, last_bill_number)
  VALUES (v_target_outlet_id, 1)
  ON CONFLICT (outlet_id)
  DO UPDATE
    SET last_bill_number = public.outlet_order_counters.last_bill_number + 1,
        updated_at = now()
  RETURNING last_bill_number INTO v_next_bill_number;

  v_order_mode := CASE
    WHEN v_outlet_business_type = 'restaurant_bar'::public.business_type
      THEN 'TAKEAWAY'::public.order_mode
    ELSE 'CASH'::public.order_mode
  END;

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
    NULL,
    v_target_outlet_id,
    COALESCE(v_outlet_day, CURRENT_DATE),
    v_open_status_id,
    v_user_id,
    v_order_mode,
    v_user_id
  )
  RETURNING id INTO v_order_id;

  RETURN QUERY
  SELECT ov.*
  FROM public.orders_view ov
  WHERE ov.order_id = v_order_id;
END;
$$;

-- ============================================================
-- 5. Grants
-- ============================================================
GRANT EXECUTE ON FUNCTION public.create_takeaway_order(UUID) TO authenticated;
