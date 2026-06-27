-- Migration: Add item cancellations table and order item action RPCs
-- Created: 2026-02-14
-- Description:
--   - Adds item_cancellations table for tracking confirmed-item cancellations
--   - Adds update_pending_order_item_notes RPC
--   - Adds remove_order_item RPC (pending delete, confirmed cancel with reason)

-- ============================================================
-- 1. Item cancellations table
-- ============================================================
CREATE TABLE public.item_cancellations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE RESTRICT,
  cancelled_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  reason TEXT NOT NULL CHECK (length(trim(reason)) > 0),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_item_cancellations_order_id ON public.item_cancellations(order_id);
CREATE INDEX idx_item_cancellations_menu_item_id ON public.item_cancellations(menu_item_id);
CREATE INDEX idx_item_cancellations_cancelled_by ON public.item_cancellations(cancelled_by);
CREATE INDEX idx_item_cancellations_created_at ON public.item_cancellations(created_at DESC);

ALTER TABLE public.item_cancellations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view item cancellations in their company"
  ON public.item_cancellations
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

CREATE POLICY "Users can create item cancellations in their company"
  ON public.item_cancellations
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

-- ============================================================
-- 2. RPC: update notes for pending items only
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_pending_order_item_notes(
  p_order_item_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS public.order_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_order_company_id BIGINT;
  v_current_status public.order_item_status;
  v_updated_row public.order_items;
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
    oi.status
  INTO
    v_order_company_id,
    v_current_status
  FROM public.order_items oi
  JOIN public.orders ord ON ord.id = oi.order_id
  JOIN public.outlets outl ON outl.id = ord.outlet_id
  WHERE oi.id = p_order_item_id
  FOR UPDATE OF oi;

  IF v_order_company_id IS NULL THEN
    RAISE EXCEPTION 'Order item % does not exist', p_order_item_id;
  END IF;

  IF v_user_company_id <> v_order_company_id THEN
    RAISE EXCEPTION 'Order item is not accessible for the current user';
  END IF;

  IF v_current_status <> 'PENDING'::public.order_item_status THEN
    RAISE EXCEPTION 'Only pending items can have notes updated';
  END IF;

  UPDATE public.order_items
  SET
    notes = NULLIF(TRIM(COALESCE(p_notes, '')), ''),
    updated_at = now()
  WHERE id = p_order_item_id
  RETURNING *
  INTO v_updated_row;

  RETURN v_updated_row;
END;
$$;

-- ============================================================
-- 3. RPC: remove pending item or cancel confirmed item
-- ============================================================
CREATE OR REPLACE FUNCTION public.remove_order_item(
  p_order_item_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS public.order_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_order_company_id BIGINT;
  v_order_id UUID;
  v_menu_item_id UUID;
  v_current_status public.order_item_status;
  v_result_row public.order_items;
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
    oi.order_id,
    oi.menu_item_id,
    oi.status
  INTO
    v_order_company_id,
    v_order_id,
    v_menu_item_id,
    v_current_status
  FROM public.order_items oi
  JOIN public.orders ord ON ord.id = oi.order_id
  JOIN public.outlets outl ON outl.id = ord.outlet_id
  WHERE oi.id = p_order_item_id
  FOR UPDATE OF oi;

  IF v_order_company_id IS NULL THEN
    RAISE EXCEPTION 'Order item % does not exist', p_order_item_id;
  END IF;

  IF v_user_company_id <> v_order_company_id THEN
    RAISE EXCEPTION 'Order item is not accessible for the current user';
  END IF;

  IF v_current_status = 'PENDING'::public.order_item_status THEN
    DELETE FROM public.order_items
    WHERE id = p_order_item_id
    RETURNING *
    INTO v_result_row;

    RETURN v_result_row;
  END IF;

  IF v_current_status = 'CONFIRMED'::public.order_item_status THEN
    IF NULLIF(TRIM(COALESCE(p_reason, '')), '') IS NULL THEN
      RAISE EXCEPTION 'Cancellation reason is required for confirmed items';
    END IF;

    INSERT INTO public.item_cancellations (
      menu_item_id,
      cancelled_by,
      reason,
      order_id
    )
    VALUES (
      v_menu_item_id,
      v_user_id,
      TRIM(p_reason),
      v_order_id
    );

    UPDATE public.order_items
    SET
      status = 'CANCELLED'::public.order_item_status,
      updated_at = now()
    WHERE id = p_order_item_id
    RETURNING *
    INTO v_result_row;

    RETURN v_result_row;
  END IF;

  RAISE EXCEPTION 'Order item is already cancelled';
END;
$$;

-- ============================================================
-- 4. Grants
-- ============================================================
GRANT SELECT, INSERT ON public.item_cancellations TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_pending_order_item_notes(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_order_item(UUID, TEXT) TO authenticated;
