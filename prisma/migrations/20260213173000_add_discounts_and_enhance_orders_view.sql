-- Migration: Add discounts table and enhance orders_view
-- Created: 2026-02-13
-- Description:
--   - Removes discount_amount from orders table (after view replacement)
--   - Adds discounts table to track discounts by order/bill
--   - Adds add_order_discount RPC for amount/percentage validation
--   - Enhances orders_view with discount, creator, waiter, and settlement details

-- ============================================================
-- 1. Discounts table
-- ============================================================
CREATE TABLE public.discounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  added_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_discounts_order_id ON public.discounts(order_id);
CREATE INDEX idx_discounts_added_by ON public.discounts(added_by);
CREATE INDEX idx_discounts_created_at ON public.discounts(created_at DESC);

CREATE TRIGGER update_discounts_updated_at
  BEFORE UPDATE ON public.discounts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 2. Discounts RPC (amount or percentage)
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_order_discount(
  p_order_id UUID,
  p_discount_value NUMERIC,
  p_discount_type TEXT DEFAULT 'AMOUNT',
  p_notes TEXT DEFAULT NULL
)
RETURNS public.discounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_order_company_id BIGINT;
  v_order_total NUMERIC(12, 2);
  v_existing_discount NUMERIC(12, 2);
  v_discount_amount NUMERIC(12, 2);
  v_discount_type TEXT;
  v_discount_row public.discounts;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_discount_value IS NULL OR p_discount_value <= 0 THEN
    RAISE EXCEPTION 'Discount value must be greater than zero';
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

  SELECT
    outl.company_id,
    COALESCE(
      SUM(oi.amount) FILTER (WHERE oi.status <> 'CANCELLED'::public.order_item_status),
      0::NUMERIC
    )::NUMERIC(12, 2)
  INTO
    v_order_company_id,
    v_order_total
  FROM public.orders ord
  JOIN public.outlets outl ON outl.id = ord.outlet_id
  LEFT JOIN public.order_items oi ON oi.order_id = ord.id
  WHERE ord.id = p_order_id
  GROUP BY outl.company_id;

  IF v_order_company_id IS NULL THEN
    RAISE EXCEPTION 'Order % does not exist', p_order_id;
  END IF;

  IF v_user_company_id <> v_order_company_id THEN
    RAISE EXCEPTION 'Order is not accessible for the current user';
  END IF;

  IF v_order_total <= 0 THEN
    RAISE EXCEPTION 'Cannot apply discount to an empty order';
  END IF;

  SELECT COALESCE(SUM(d.amount), 0)::NUMERIC(12, 2)
  INTO v_existing_discount
  FROM public.discounts d
  WHERE d.order_id = p_order_id;

  v_discount_type := UPPER(TRIM(COALESCE(p_discount_type, 'AMOUNT')));

  IF v_discount_type = 'AMOUNT' THEN
    v_discount_amount := ROUND(p_discount_value, 2);
  ELSIF v_discount_type = 'PERCENTAGE' THEN
    IF p_discount_value >= 100 THEN
      RAISE EXCEPTION 'Discount percentage must be less than 100';
    END IF;
    v_discount_amount := ROUND((v_order_total * (p_discount_value / 100.0))::NUMERIC, 2);
  ELSE
    RAISE EXCEPTION 'Unsupported discount type: %. Use AMOUNT or PERCENTAGE', p_discount_type;
  END IF;

  IF v_discount_amount <= 0 THEN
    RAISE EXCEPTION 'Computed discount amount must be greater than zero';
  END IF;

  -- Discount amount must be less than the order items sum.
  IF v_discount_amount >= v_order_total THEN
    RAISE EXCEPTION 'Discount amount must be less than order total';
  END IF;

  -- Prevent cumulative discounts from meeting/exceeding order total.
  IF (v_existing_discount + v_discount_amount) >= v_order_total THEN
    RAISE EXCEPTION 'Total discounts must remain less than order total';
  END IF;

  INSERT INTO public.discounts (
    order_id,
    amount,
    added_by,
    notes
  )
  VALUES (
    p_order_id,
    v_discount_amount,
    v_user_id,
    NULLIF(TRIM(COALESCE(p_notes, '')), '')
  )
  RETURNING *
  INTO v_discount_row;

  RETURN v_discount_row;
END;
$$;

-- ============================================================
-- 3. Enhanced orders view
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
  ot.name AS table_name,
  os.id AS section_id,
  os.name AS section_name,
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
JOIN public.outlet_tables ot ON ot.id = o.table_id
JOIN public.outlet_sections os ON os.id = ot.section_id
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
-- 4. Remove discount_amount from orders table
-- ============================================================
ALTER TABLE public.orders
DROP COLUMN IF EXISTS discount_amount;

-- ============================================================
-- 5. RLS for discounts
-- ============================================================
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view discounts in their company"
  ON public.discounts
  FOR SELECT
  TO authenticated
  USING (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Users can create discounts in their company"
  ON public.discounts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Users can update discounts in their company"
  ON public.discounts
  FOR UPDATE
  TO authenticated
  USING (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  )
  WITH CHECK (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

-- ============================================================
-- 6. Grants
-- ============================================================
GRANT SELECT, INSERT, UPDATE ON public.discounts TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_order_discount(UUID, NUMERIC, TEXT, TEXT) TO authenticated;
