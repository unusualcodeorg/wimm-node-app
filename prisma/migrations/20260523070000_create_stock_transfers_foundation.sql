-- Migration: Stock transfers foundation
-- Created: 2026-05-23
-- Description:
--   - inventory_stock_transfers  (transfer header)
--   - inventory_stock_transfer_lines  (one row per item)
--   - post_stock_transfer RPC:
--       creates transfer_out movement from source location
--       creates transfer_in  movement at destination location
--       updates both stock balances

-- ─────────────────────────────────────────────────────────────────────────────
-- Status enum
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'stock_transfer_status'
  ) THEN
    CREATE TYPE public.stock_transfer_status AS ENUM ('draft', 'posted', 'cancelled');
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- inventory_stock_transfers
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.inventory_stock_transfers (
  id                      UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id              BIGINT        NOT NULL REFERENCES public.companies(id)                     ON DELETE CASCADE,
  outlet_id               UUID          NOT NULL REFERENCES public.outlets(id)                       ON DELETE CASCADE,
  from_stock_location_id  UUID          NOT NULL REFERENCES public.inventory_stock_locations(id)     ON DELETE RESTRICT,
  to_stock_location_id    UUID          NOT NULL REFERENCES public.inventory_stock_locations(id)     ON DELETE RESTRICT,
  transfer_date           DATE          NOT NULL DEFAULT CURRENT_DATE,
  status                  public.stock_transfer_status NOT NULL DEFAULT 'draft',
  reference               TEXT,
  notes                   TEXT,
  posted_at               TIMESTAMPTZ,
  posted_by               UUID          REFERENCES public.users(id) ON DELETE SET NULL,
  created_by              UUID          REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT stock_transfers_locations_differ CHECK (from_stock_location_id <> to_stock_location_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_transfers_company_outlet_date
  ON public.inventory_stock_transfers(company_id, outlet_id, transfer_date DESC);

CREATE INDEX IF NOT EXISTS idx_stock_transfers_status
  ON public.inventory_stock_transfers(company_id, status);

-- ─────────────────────────────────────────────────────────────────────────────
-- inventory_stock_transfer_lines
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.inventory_stock_transfer_lines (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  stock_transfer_id   UUID          NOT NULL REFERENCES public.inventory_stock_transfers(id) ON DELETE CASCADE,
  inventory_item_id   UUID          NOT NULL REFERENCES public.inventory_items(id)           ON DELETE RESTRICT,
  quantity            NUMERIC(14, 4) NOT NULL CHECK (quantity > 0),
  unit_cost           NUMERIC(14, 4),
  created_by          UUID          REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (stock_transfer_id, inventory_item_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_transfer_lines_transfer
  ON public.inventory_stock_transfer_lines(stock_transfer_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.inventory_stock_transfers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view stock transfers in their company" ON public.inventory_stock_transfers;
CREATE POLICY "Users can view stock transfers in their company"
  ON public.inventory_stock_transfers FOR SELECT TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert stock transfers in their company" ON public.inventory_stock_transfers;
CREATE POLICY "Users can insert stock transfers in their company"
  ON public.inventory_stock_transfers FOR INSERT TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update stock transfers in their company" ON public.inventory_stock_transfers;
CREATE POLICY "Users can update stock transfers in their company"
  ON public.inventory_stock_transfers FOR UPDATE TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

GRANT SELECT, INSERT, UPDATE ON public.inventory_stock_transfers TO authenticated;

ALTER TABLE public.inventory_stock_transfer_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view stock transfer lines in their company" ON public.inventory_stock_transfer_lines;
CREATE POLICY "Users can view stock transfer lines in their company"
  ON public.inventory_stock_transfer_lines FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_transfers t
      WHERE t.id = stock_transfer_id
        AND t.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can insert stock transfer lines in their company" ON public.inventory_stock_transfer_lines;
CREATE POLICY "Users can insert stock transfer lines in their company"
  ON public.inventory_stock_transfer_lines FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_transfers t
      WHERE t.id = stock_transfer_id
        AND t.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can update stock transfer lines in their company" ON public.inventory_stock_transfer_lines;
CREATE POLICY "Users can update stock transfer lines in their company"
  ON public.inventory_stock_transfer_lines FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_transfers t
      WHERE t.id = stock_transfer_id
        AND t.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can delete stock transfer lines in their company" ON public.inventory_stock_transfer_lines;
CREATE POLICY "Users can delete stock transfer lines in their company"
  ON public.inventory_stock_transfer_lines FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_transfers t
      WHERE t.id = stock_transfer_id
        AND t.company_id = public.get_auth_user_company_id()
        AND t.status = 'draft'
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_stock_transfer_lines TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- post_stock_transfer RPC
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Idempotency-guarded via financial_event_logs.
-- 2. For each line: transfer_out from source, transfer_in to destination.
-- 3. Derives unit_cost from the source balance (weighted average).
-- 4. Allows negative source balance rather than blocking the transfer.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_stock_transfer(p_transfer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_transfer   public.inventory_stock_transfers;
  v_line       public.inventory_stock_transfer_lines;
  v_from_bal   public.inventory_stock_balances;
  v_to_bal     public.inventory_stock_balances;
  v_unit_cost  NUMERIC(14, 4);
  v_total_cost NUMERIC(14, 2);
  v_lines_processed INTEGER := 0;
  v_user_id    UUID;
BEGIN
  v_user_id := auth.uid();

  SELECT * INTO v_transfer
  FROM public.inventory_stock_transfers
  WHERE id = p_transfer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Transfer not found');
  END IF;

  IF v_transfer.status <> 'draft' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only draft transfers can be posted');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.inventory_stock_transfer_lines
    WHERE stock_transfer_id = p_transfer_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot post a transfer with no lines');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.financial_event_logs
    WHERE source_module  = 'inventory'
      AND event_type     = 'STOCK_TRANSFER_POSTED'
      AND reference_type = 'stock_transfer'
      AND reference_id   = p_transfer_id
      AND status         = 'processed'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Transfer has already been posted');
  END IF;

  BEGIN
    FOR v_line IN
      SELECT * FROM public.inventory_stock_transfer_lines
      WHERE stock_transfer_id = p_transfer_id
    LOOP
      -- Source balance (for unit cost)
      SELECT * INTO v_from_bal
      FROM public.inventory_stock_balances
      WHERE company_id        = v_transfer.company_id
        AND outlet_id         = v_transfer.outlet_id
        AND stock_location_id = v_transfer.from_stock_location_id
        AND inventory_item_id = v_line.inventory_item_id
      FOR UPDATE;

      v_unit_cost  := COALESCE(v_from_bal.average_cost, v_line.unit_cost, 0);
      v_total_cost := ROUND(v_line.quantity * v_unit_cost, 2);

      -- Transfer-out movement
      INSERT INTO public.inventory_stock_movements (
        company_id, outlet_id, stock_location_id, inventory_item_id,
        movement_type, reference_type, reference_id,
        quantity, unit_cost, total_cost, movement_date, created_by
      ) VALUES (
        v_transfer.company_id,
        v_transfer.outlet_id,
        v_transfer.from_stock_location_id,
        v_line.inventory_item_id,
        'transfer_out',
        'stock_transfer',
        p_transfer_id::TEXT,
        v_line.quantity,
        v_unit_cost,
        v_total_cost,
        NOW(),
        v_user_id
      );

      -- Decrement source balance
      IF FOUND THEN
        UPDATE public.inventory_stock_balances
        SET
          quantity_on_hand = quantity_on_hand - v_line.quantity,
          total_value      = GREATEST(total_value - v_total_cost, 0),
          updated_at       = NOW()
        WHERE id = v_from_bal.id;
      ELSE
        INSERT INTO public.inventory_stock_balances (
          company_id, outlet_id, stock_location_id, inventory_item_id,
          quantity_on_hand, average_cost, total_value, created_by
        ) VALUES (
          v_transfer.company_id,
          v_transfer.outlet_id,
          v_transfer.from_stock_location_id,
          v_line.inventory_item_id,
          -v_line.quantity, 0, 0,
          v_user_id
        );
      END IF;

      -- Transfer-in movement
      INSERT INTO public.inventory_stock_movements (
        company_id, outlet_id, stock_location_id, inventory_item_id,
        movement_type, reference_type, reference_id,
        quantity, unit_cost, total_cost, movement_date, created_by
      ) VALUES (
        v_transfer.company_id,
        v_transfer.outlet_id,
        v_transfer.to_stock_location_id,
        v_line.inventory_item_id,
        'transfer_in',
        'stock_transfer',
        p_transfer_id::TEXT,
        v_line.quantity,
        v_unit_cost,
        v_total_cost,
        NOW(),
        v_user_id
      );

      -- Increment destination balance
      SELECT * INTO v_to_bal
      FROM public.inventory_stock_balances
      WHERE company_id        = v_transfer.company_id
        AND outlet_id         = v_transfer.outlet_id
        AND stock_location_id = v_transfer.to_stock_location_id
        AND inventory_item_id = v_line.inventory_item_id
      FOR UPDATE;

      IF FOUND THEN
        DECLARE
          v_new_qty       NUMERIC(14, 4);
          v_new_avg_cost  NUMERIC(14, 4);
        BEGIN
          v_new_qty      := v_to_bal.quantity_on_hand + v_line.quantity;
          v_new_avg_cost := CASE
            WHEN v_new_qty > 0 THEN
              ((v_to_bal.quantity_on_hand * v_to_bal.average_cost) +
               (v_line.quantity * v_unit_cost))
              / v_new_qty
            ELSE v_unit_cost
          END;

          UPDATE public.inventory_stock_balances
          SET
            quantity_on_hand = v_new_qty,
            average_cost     = v_new_avg_cost,
            total_value      = v_new_qty * v_new_avg_cost,
            updated_at       = NOW()
          WHERE id = v_to_bal.id;
        END;
      ELSE
        INSERT INTO public.inventory_stock_balances (
          company_id, outlet_id, stock_location_id, inventory_item_id,
          quantity_on_hand, average_cost, total_value, created_by
        ) VALUES (
          v_transfer.company_id,
          v_transfer.outlet_id,
          v_transfer.to_stock_location_id,
          v_line.inventory_item_id,
          v_line.quantity,
          v_unit_cost,
          v_total_cost,
          v_user_id
        );
      END IF;

      v_lines_processed := v_lines_processed + 1;
    END LOOP;

    -- Mark transfer as posted
    UPDATE public.inventory_stock_transfers
    SET
      status    = 'posted',
      posted_at = NOW(),
      posted_by = v_user_id,
      updated_at = NOW()
    WHERE id = p_transfer_id;

    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id, idempotency_key, status, payload
    ) VALUES (
      v_transfer.company_id,
      v_transfer.outlet_id,
      'inventory',
      'STOCK_TRANSFER_POSTED',
      'stock_transfer',
      p_transfer_id,
      format('stock_transfer_post_%s', p_transfer_id),
      'processed',
      jsonb_build_object(
        'transfer_id',      p_transfer_id,
        'from_location_id', v_transfer.from_stock_location_id,
        'to_location_id',   v_transfer.to_stock_location_id,
        'lines_processed',  v_lines_processed
      )
    );

    RETURN jsonb_build_object(
      'success',          true,
      'transfer_id',      p_transfer_id,
      'lines_processed',  v_lines_processed
    );

  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id,
      idempotency_key, status, error_message
    ) VALUES (
      v_transfer.company_id,
      v_transfer.outlet_id,
      'inventory', 'STOCK_TRANSFER_POSTED',
      'stock_transfer', p_transfer_id,
      format('stock_transfer_post_err_%s', gen_random_uuid()),
      'failed', SQLERRM
    );

    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_stock_transfer(UUID) TO authenticated;
