-- Migration: Make discounts single-record per order and add remove RPC
-- Created: 2026-02-14
-- Description:
--   - Enforces one discount record per order
--   - Updates add_order_discount to replace existing discount
--   - Adds remove_order_discount RPC

-- ============================================================
-- 1. Keep only the most recent discount record per order
-- ============================================================
WITH ranked_discounts AS (
  SELECT
    d.id,
    ROW_NUMBER() OVER (
      PARTITION BY d.order_id
      ORDER BY d.updated_at DESC, d.created_at DESC, d.id DESC
    ) AS row_num
  FROM public.discounts d
)
DELETE FROM public.discounts d
USING ranked_discounts r
WHERE d.id = r.id
  AND r.row_num > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_discounts_order_unique
  ON public.discounts(order_id);

-- ============================================================
-- 2. Replace add_order_discount with upsert (single record/order)
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

  IF v_discount_amount >= v_order_total THEN
    RAISE EXCEPTION 'Discount amount must be less than order total';
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
  ON CONFLICT (order_id)
  DO UPDATE
    SET amount = EXCLUDED.amount,
        added_by = EXCLUDED.added_by,
        notes = EXCLUDED.notes,
        updated_at = now()
  RETURNING *
  INTO v_discount_row;

  RETURN v_discount_row;
END;
$$;

-- ============================================================
-- 3. RPC: remove existing order discount
-- ============================================================
CREATE OR REPLACE FUNCTION public.remove_order_discount(
  p_order_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_order_company_id BIGINT;
  v_deleted_count INTEGER;
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

  SELECT outl.company_id
  INTO v_order_company_id
  FROM public.orders ord
  JOIN public.outlets outl ON outl.id = ord.outlet_id
  WHERE ord.id = p_order_id;

  IF v_order_company_id IS NULL THEN
    RAISE EXCEPTION 'Order % does not exist', p_order_id;
  END IF;

  IF v_user_company_id <> v_order_company_id THEN
    RAISE EXCEPTION 'Order is not accessible for the current user';
  END IF;

  DELETE FROM public.discounts d
  WHERE d.order_id = p_order_id;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  RETURN v_deleted_count > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_order_discount(UUID) TO authenticated;
