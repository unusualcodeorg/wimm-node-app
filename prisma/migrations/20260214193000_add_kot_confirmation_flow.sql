-- Migration: Add KOT confirmation flow for pending order items
-- Created: 2026-02-14
-- Description:
--   - Adds outlet-scoped KOT counters
--   - Adds confirm_order_kot RPC to confirm pending items and assign a KOT lot

-- ============================================================
-- 1. Supporting counter table for outlet-scoped KOT IDs
-- ============================================================
CREATE TABLE public.outlet_kot_counters (
  outlet_id UUID PRIMARY KEY REFERENCES public.outlets(id) ON DELETE CASCADE,
  last_kot_id INTEGER NOT NULL DEFAULT 0 CHECK (last_kot_id >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER update_outlet_kot_counters_updated_at
  BEFORE UPDATE ON public.outlet_kot_counters
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.outlet_kot_counters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view outlet KOT counters in their company"
  ON public.outlet_kot_counters
  FOR SELECT
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id
      FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  );

-- ============================================================
-- 2. RPC: confirm pending items for an order and assign KOT lot
-- ============================================================
CREATE OR REPLACE FUNCTION public.confirm_order_kot(
  p_order_id UUID
)
RETURNS TABLE(kot_id INTEGER, confirmed_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_order_company_id BIGINT;
  v_outlet_id UUID;
  v_kot_id INTEGER;
  v_confirmed_count INTEGER;
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

  SELECT
    outl.company_id,
    ord.outlet_id
  INTO
    v_order_company_id,
    v_outlet_id
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

  INSERT INTO public.outlet_kot_counters (outlet_id, last_kot_id)
  VALUES (v_outlet_id, 1)
  ON CONFLICT (outlet_id)
  DO UPDATE
    SET last_kot_id = public.outlet_kot_counters.last_kot_id + 1,
        updated_at = now()
  RETURNING last_kot_id INTO v_kot_id;

  UPDATE public.order_items
  SET
    status = 'CONFIRMED'::public.order_item_status,
    kot_id = v_kot_id,
    updated_at = now()
  WHERE order_id = p_order_id
    AND status = 'PENDING'::public.order_item_status;

  GET DIAGNOSTICS v_confirmed_count = ROW_COUNT;

  IF v_confirmed_count = 0 THEN
    RAISE EXCEPTION 'Order has no pending items to confirm';
  END IF;

  RETURN QUERY
  SELECT v_kot_id, v_confirmed_count;
END;
$$;

-- ============================================================
-- 3. Grants
-- ============================================================
GRANT SELECT ON public.outlet_kot_counters TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_order_kot(UUID) TO authenticated;
