-- Migration: Stock adjustments and wastage foundation
-- Created: 2026-05-23
-- Description:
--   - inventory_stock_adjustments  (adjustment header)
--   - inventory_stock_adjustment_lines  (one row per item)
--   - post_stock_adjustment RPC:
--       creates appropriate movement type per line sign/adjustment_type
--       updates stock balances
--       posts Dr Wastage Expense / Cr Inventory Asset when wastage

-- ─────────────────────────────────────────────────────────────────────────────
-- Enums
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'stock_adjustment_status'
  ) THEN
    CREATE TYPE public.stock_adjustment_status AS ENUM ('draft', 'posted', 'cancelled');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'stock_adjustment_type'
  ) THEN
    CREATE TYPE public.stock_adjustment_type AS ENUM (
      'variance',
      'wastage',
      'correction',
      'stock_count'
    );
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- inventory_stock_adjustments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.inventory_stock_adjustments (
  id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          BIGINT        NOT NULL REFERENCES public.companies(id)                 ON DELETE CASCADE,
  outlet_id           UUID          NOT NULL REFERENCES public.outlets(id)                   ON DELETE CASCADE,
  stock_location_id   UUID          NOT NULL REFERENCES public.inventory_stock_locations(id) ON DELETE RESTRICT,
  adjustment_date     DATE          NOT NULL DEFAULT CURRENT_DATE,
  adjustment_type     public.stock_adjustment_type NOT NULL DEFAULT 'correction',
  status              public.stock_adjustment_status NOT NULL DEFAULT 'draft',
  reference           TEXT,
  notes               TEXT,
  journal_entry_id    UUID          REFERENCES public.journal_entries(id) ON DELETE SET NULL,
  posted_at           TIMESTAMPTZ,
  posted_by           UUID          REFERENCES public.users(id) ON DELETE SET NULL,
  created_by          UUID          REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_adjustments_company_outlet_date
  ON public.inventory_stock_adjustments(company_id, outlet_id, adjustment_date DESC);

CREATE INDEX IF NOT EXISTS idx_stock_adjustments_status_type
  ON public.inventory_stock_adjustments(company_id, status, adjustment_type);

-- ─────────────────────────────────────────────────────────────────────────────
-- inventory_stock_adjustment_lines
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.inventory_stock_adjustment_lines (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  stock_adjustment_id   UUID          NOT NULL REFERENCES public.inventory_stock_adjustments(id) ON DELETE CASCADE,
  inventory_item_id     UUID          NOT NULL REFERENCES public.inventory_items(id)              ON DELETE RESTRICT,
  quantity_adjusted     NUMERIC(14, 4) NOT NULL CHECK (quantity_adjusted <> 0),
  unit_cost             NUMERIC(14, 4),
  reason                TEXT,
  created_by            UUID          REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (stock_adjustment_id, inventory_item_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_adjustment_lines_adjustment
  ON public.inventory_stock_adjustment_lines(stock_adjustment_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — inventory_stock_adjustments
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.inventory_stock_adjustments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view stock adjustments in their company" ON public.inventory_stock_adjustments;
CREATE POLICY "Users can view stock adjustments in their company"
  ON public.inventory_stock_adjustments FOR SELECT TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert stock adjustments in their company" ON public.inventory_stock_adjustments;
CREATE POLICY "Users can insert stock adjustments in their company"
  ON public.inventory_stock_adjustments FOR INSERT TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update stock adjustments in their company" ON public.inventory_stock_adjustments;
CREATE POLICY "Users can update stock adjustments in their company"
  ON public.inventory_stock_adjustments FOR UPDATE TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

GRANT SELECT, INSERT, UPDATE ON public.inventory_stock_adjustments TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — inventory_stock_adjustment_lines
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.inventory_stock_adjustment_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view stock adjustment lines in their company" ON public.inventory_stock_adjustment_lines;
CREATE POLICY "Users can view stock adjustment lines in their company"
  ON public.inventory_stock_adjustment_lines FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_adjustments a
      WHERE a.id = stock_adjustment_id
        AND a.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can insert stock adjustment lines in their company" ON public.inventory_stock_adjustment_lines;
CREATE POLICY "Users can insert stock adjustment lines in their company"
  ON public.inventory_stock_adjustment_lines FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_adjustments a
      WHERE a.id = stock_adjustment_id
        AND a.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can update stock adjustment lines in their company" ON public.inventory_stock_adjustment_lines;
CREATE POLICY "Users can update stock adjustment lines in their company"
  ON public.inventory_stock_adjustment_lines FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_adjustments a
      WHERE a.id = stock_adjustment_id
        AND a.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can delete stock adjustment lines in their company" ON public.inventory_stock_adjustment_lines;
CREATE POLICY "Users can delete stock adjustment lines in their company"
  ON public.inventory_stock_adjustment_lines FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.inventory_stock_adjustments a
      WHERE a.id = stock_adjustment_id
        AND a.company_id = public.get_auth_user_company_id()
        AND a.status = 'draft'
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.inventory_stock_adjustment_lines TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- post_stock_adjustment RPC
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Idempotency-guarded via financial_event_logs.
-- 2. Per line: movement_type determined by adjustment_type + quantity sign:
--    wastage → wastage (negative only)
--    other negative → adjustment_decrease
--    other positive → adjustment_increase
-- 3. Updates stock balances (allows negative).
-- 4. Posts Dr Wastage Expense / Cr Inventory Asset for wastage adjustments
--    when wastage account (5100) exists.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_stock_adjustment(p_adjustment_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_adj              public.inventory_stock_adjustments;
  v_line             public.inventory_stock_adjustment_lines;
  v_balance          public.inventory_stock_balances;
  v_movement_type    public.inventory_stock_movement_type;
  v_abs_qty          NUMERIC(14, 4);
  v_unit_cost        NUMERIC(14, 4);
  v_line_value       NUMERIC(14, 2);
  v_total_wastage    NUMERIC(14, 2) := 0;
  v_wastage_acct     UUID;
  v_inventory_acct   UUID;
  v_journal_id       UUID;
  v_lines_processed  INTEGER := 0;
  v_user_id          UUID;
BEGIN
  v_user_id := auth.uid();

  SELECT * INTO v_adj
  FROM public.inventory_stock_adjustments
  WHERE id = p_adjustment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Adjustment not found');
  END IF;

  IF v_adj.status <> 'draft' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only draft adjustments can be posted');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.inventory_stock_adjustment_lines
    WHERE stock_adjustment_id = p_adjustment_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot post an adjustment with no lines');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.financial_event_logs
    WHERE source_module  = 'inventory'
      AND event_type     = 'STOCK_ADJUSTMENT_POSTED'
      AND reference_type = 'stock_adjustment'
      AND reference_id   = p_adjustment_id
      AND status         = 'processed'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Adjustment has already been posted');
  END IF;

  BEGIN
    FOR v_line IN
      SELECT * FROM public.inventory_stock_adjustment_lines
      WHERE stock_adjustment_id = p_adjustment_id
    LOOP
      v_abs_qty := ABS(v_line.quantity_adjusted);

      -- Determine movement type
      v_movement_type := CASE
        WHEN v_adj.adjustment_type = 'wastage'
          THEN 'wastage'::public.inventory_stock_movement_type
        WHEN v_adj.adjustment_type = 'stock_count'
          THEN 'stock_count_correction'::public.inventory_stock_movement_type
        WHEN v_line.quantity_adjusted > 0
          THEN 'adjustment_increase'::public.inventory_stock_movement_type
        ELSE 'adjustment_decrease'::public.inventory_stock_movement_type
      END;

      -- Lock balance for cost derivation
      SELECT * INTO v_balance
      FROM public.inventory_stock_balances
      WHERE company_id        = v_adj.company_id
        AND outlet_id         = v_adj.outlet_id
        AND stock_location_id = v_adj.stock_location_id
        AND inventory_item_id = v_line.inventory_item_id
      FOR UPDATE;

      v_unit_cost  := COALESCE(v_line.unit_cost, v_balance.average_cost, 0);
      v_line_value := ROUND(v_abs_qty * v_unit_cost, 2);

      -- Track wastage value for accounting
      IF v_adj.adjustment_type = 'wastage' OR v_movement_type = 'wastage' THEN
        v_total_wastage := v_total_wastage + v_line_value;
      END IF;

      -- Create stock movement (quantity is always absolute and positive in movement table)
      INSERT INTO public.inventory_stock_movements (
        company_id, outlet_id, stock_location_id, inventory_item_id,
        movement_type, reference_type, reference_id,
        quantity, unit_cost, total_cost, movement_date, created_by
      ) VALUES (
        v_adj.company_id,
        v_adj.outlet_id,
        v_adj.stock_location_id,
        v_line.inventory_item_id,
        v_movement_type,
        'stock_adjustment',
        p_adjustment_id::TEXT,
        v_abs_qty,
        v_unit_cost,
        v_line_value,
        NOW(),
        v_user_id
      );

      -- Update balance
      IF FOUND THEN
        UPDATE public.inventory_stock_balances
        SET
          quantity_on_hand = quantity_on_hand + v_line.quantity_adjusted,
          total_value      = GREATEST(
            total_value + (v_line.quantity_adjusted * v_unit_cost),
            0
          ),
          updated_at       = NOW()
        WHERE id = v_balance.id;
      ELSE
        INSERT INTO public.inventory_stock_balances (
          company_id, outlet_id, stock_location_id, inventory_item_id,
          quantity_on_hand, average_cost, total_value, created_by
        ) VALUES (
          v_adj.company_id,
          v_adj.outlet_id,
          v_adj.stock_location_id,
          v_line.inventory_item_id,
          v_line.quantity_adjusted,
          v_unit_cost,
          GREATEST(v_line.quantity_adjusted * v_unit_cost, 0),
          v_user_id
        );
      END IF;

      v_lines_processed := v_lines_processed + 1;
    END LOOP;

    -- Accounting: Dr Wastage Expense (5100) / Cr Inventory Asset (1200) for wastage
    IF v_total_wastage > 0 THEN
      SELECT id INTO v_wastage_acct
      FROM public.accounts
      WHERE company_id = v_adj.company_id AND code = '5100' AND is_active = true
      LIMIT 1;

      SELECT id INTO v_inventory_acct
      FROM public.accounts
      WHERE company_id = v_adj.company_id AND code = '1200' AND is_active = true
      LIMIT 1;

      IF v_wastage_acct IS NOT NULL AND v_inventory_acct IS NOT NULL THEN
        INSERT INTO public.journal_entries (
          company_id, outlet_id, posting_scope,
          reference_type, reference_id,
          source_module, entry_date, memo, status, created_by
        ) VALUES (
          v_adj.company_id, v_adj.outlet_id,
          'outlet'::public.journal_posting_scope,
          'stock_adjustment',
          p_adjustment_id,
          'inventory'::public.journal_source_module,
          v_adj.adjustment_date,
          format('Wastage adjustment %s', COALESCE(v_adj.reference, p_adjustment_id::TEXT)),
          'draft'::public.journal_entry_status,
          v_user_id
        )
        RETURNING id INTO v_journal_id;

        INSERT INTO public.journal_entry_lines (
          company_id, journal_entry_id, account_id, outlet_id,
          debit, credit, description, created_by
        ) VALUES (
          v_adj.company_id, v_journal_id, v_wastage_acct, v_adj.outlet_id,
          ROUND(v_total_wastage, 2), 0,
          'Wastage / spoilage expense',
          v_user_id
        );

        INSERT INTO public.journal_entry_lines (
          company_id, journal_entry_id, account_id, outlet_id,
          debit, credit, description, created_by
        ) VALUES (
          v_adj.company_id, v_journal_id, v_inventory_acct, v_adj.outlet_id,
          0, ROUND(v_total_wastage, 2),
          'Inventory asset written off',
          v_user_id
        );

        UPDATE public.journal_entries
        SET status = 'posted' WHERE id = v_journal_id;
      END IF;
    END IF;

    -- Mark adjustment as posted
    UPDATE public.inventory_stock_adjustments
    SET
      status           = 'posted',
      posted_at        = NOW(),
      posted_by        = v_user_id,
      journal_entry_id = v_journal_id,
      updated_at       = NOW()
    WHERE id = p_adjustment_id;

    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id, idempotency_key, status, payload
    ) VALUES (
      v_adj.company_id, v_adj.outlet_id,
      'inventory', 'STOCK_ADJUSTMENT_POSTED',
      'stock_adjustment', p_adjustment_id,
      format('stock_adjustment_post_%s', p_adjustment_id),
      'processed',
      jsonb_build_object(
        'adjustment_id',    p_adjustment_id,
        'adjustment_type',  v_adj.adjustment_type,
        'lines_processed',  v_lines_processed,
        'total_wastage',    v_total_wastage,
        'journal_entry_id', v_journal_id
      )
    );

    RETURN jsonb_build_object(
      'success',          true,
      'adjustment_id',    p_adjustment_id,
      'lines_processed',  v_lines_processed,
      'total_wastage',    v_total_wastage,
      'journal_entry_id', v_journal_id
    );

  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id,
      idempotency_key, status, error_message
    ) VALUES (
      v_adj.company_id, v_adj.outlet_id,
      'inventory', 'STOCK_ADJUSTMENT_POSTED',
      'stock_adjustment', p_adjustment_id,
      format('stock_adjustment_post_err_%s', gen_random_uuid()),
      'failed', SQLERRM
    );

    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_stock_adjustment(UUID) TO authenticated;
