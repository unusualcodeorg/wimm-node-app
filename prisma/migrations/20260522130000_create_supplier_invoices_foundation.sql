-- Migration: Create supplier invoices foundation
-- Created: 2026-05-22
-- Description:
--   - Creates supplier_invoices (header) and supplier_invoice_lines (line items)
--   - Draft/posted lifecycle — posted invoices are immutable
--   - post_supplier_invoice RPC: converts purchase qty to stock qty, creates purchase_receipt
--     stock movements, updates weighted-average stock balances, and logs the financial event
--   - RLS policies and grants

-- ─────────────────────────────────────────────────────────────────────────────
-- supplier_invoices
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.supplier_invoices (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        BIGINT      NOT NULL REFERENCES public.companies(id)                   ON DELETE CASCADE,
  outlet_id         UUID        NOT NULL REFERENCES public.outlets(id)                     ON DELETE CASCADE,
  supplier_id       UUID        NOT NULL REFERENCES public.inventory_suppliers(id)         ON DELETE RESTRICT,
  stock_location_id UUID        NOT NULL REFERENCES public.inventory_stock_locations(id)   ON DELETE RESTRICT,
  invoice_number    TEXT,
  invoice_date      DATE        NOT NULL DEFAULT CURRENT_DATE,
  due_date          DATE,
  subtotal          NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  tax_amount        NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  total_amount      NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  amount_paid       NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  status            TEXT        NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'posted', 'partially_paid', 'paid', 'voided')),
  notes             TEXT,
  posted_at         TIMESTAMPTZ,
  posted_by         UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  created_by        UUID        REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT supplier_invoices_invoice_number_not_blank CHECK (
    invoice_number IS NULL OR length(btrim(invoice_number)) > 0
  )
);

CREATE INDEX IF NOT EXISTS idx_supplier_invoices_company_outlet
  ON public.supplier_invoices(company_id, outlet_id, status, invoice_date DESC);

CREATE INDEX IF NOT EXISTS idx_supplier_invoices_supplier
  ON public.supplier_invoices(company_id, supplier_id, status);

CREATE INDEX IF NOT EXISTS idx_supplier_invoices_location
  ON public.supplier_invoices(company_id, outlet_id, stock_location_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- supplier_invoice_lines
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.supplier_invoice_lines (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_invoice_id   UUID          NOT NULL REFERENCES public.supplier_invoices(id) ON DELETE CASCADE,
  inventory_item_id     UUID          NOT NULL REFERENCES public.inventory_items(id)   ON DELETE RESTRICT,
  description           TEXT,
  quantity_purchased    NUMERIC(14, 4) NOT NULL CHECK (quantity_purchased > 0),
  purchase_unit_id      UUID          REFERENCES public.inventory_units(id)            ON DELETE RESTRICT,
  conversion_rate       NUMERIC(14, 6) NOT NULL DEFAULT 1 CHECK (conversion_rate > 0),
  quantity_in_stock_unit NUMERIC(14, 4) NOT NULL CHECK (quantity_in_stock_unit > 0),
  -- unit_cost is cost per PURCHASE unit (what appears on the supplier invoice)
  unit_cost             NUMERIC(14, 4) NOT NULL CHECK (unit_cost >= 0),
  tax_rate              NUMERIC(5, 2)  NOT NULL DEFAULT 0 CHECK (tax_rate >= 0),
  tax_amount            NUMERIC(14, 2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  -- line_total = (quantity_purchased * unit_cost) + tax_amount
  line_total            NUMERIC(14, 2) NOT NULL CHECK (line_total >= 0),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_supplier_invoice_lines_invoice
  ON public.supplier_invoice_lines(supplier_invoice_id);

CREATE INDEX IF NOT EXISTS idx_supplier_invoice_lines_item
  ON public.supplier_invoice_lines(inventory_item_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — supplier_invoices
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.supplier_invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view supplier invoices in their company" ON public.supplier_invoices;
CREATE POLICY "Users can view supplier invoices in their company"
  ON public.supplier_invoices FOR SELECT TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert supplier invoices in their company" ON public.supplier_invoices;
CREATE POLICY "Users can insert supplier invoices in their company"
  ON public.supplier_invoices FOR INSERT TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update draft supplier invoices in their company" ON public.supplier_invoices;
CREATE POLICY "Users can update draft supplier invoices in their company"
  ON public.supplier_invoices FOR UPDATE TO authenticated
  USING (company_id = public.get_auth_user_company_id() AND status = 'draft')
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can delete draft supplier invoices in their company" ON public.supplier_invoices;
CREATE POLICY "Users can delete draft supplier invoices in their company"
  ON public.supplier_invoices FOR DELETE TO authenticated
  USING (company_id = public.get_auth_user_company_id() AND status = 'draft');

GRANT SELECT, INSERT, UPDATE, DELETE ON public.supplier_invoices TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — supplier_invoice_lines
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.supplier_invoice_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view supplier invoice lines in their company" ON public.supplier_invoice_lines;
CREATE POLICY "Users can view supplier invoice lines in their company"
  ON public.supplier_invoice_lines FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.supplier_invoices si
      WHERE si.id = supplier_invoice_id
      AND si.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can insert supplier invoice lines in their company" ON public.supplier_invoice_lines;
CREATE POLICY "Users can insert supplier invoice lines in their company"
  ON public.supplier_invoice_lines FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.supplier_invoices si
      WHERE si.id = supplier_invoice_id
      AND si.company_id = public.get_auth_user_company_id()
      AND si.status = 'draft'
    )
  );

DROP POLICY IF EXISTS "Users can update supplier invoice lines in their company" ON public.supplier_invoice_lines;
CREATE POLICY "Users can update supplier invoice lines in their company"
  ON public.supplier_invoice_lines FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.supplier_invoices si
      WHERE si.id = supplier_invoice_id
      AND si.company_id = public.get_auth_user_company_id()
      AND si.status = 'draft'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.supplier_invoices si
      WHERE si.id = supplier_invoice_id
      AND si.company_id = public.get_auth_user_company_id()
      AND si.status = 'draft'
    )
  );

DROP POLICY IF EXISTS "Users can delete supplier invoice lines in their company" ON public.supplier_invoice_lines;
CREATE POLICY "Users can delete supplier invoice lines in their company"
  ON public.supplier_invoice_lines FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.supplier_invoices si
      WHERE si.id = supplier_invoice_id
      AND si.company_id = public.get_auth_user_company_id()
      AND si.status = 'draft'
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.supplier_invoice_lines TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- post_supplier_invoice RPC
-- ─────────────────────────────────────────────────────────────────────────────
-- On posting:
--   1. Validates invoice is in draft status
--   2. Checks idempotency via financial_event_logs
--   3. For each line: creates a purchase_receipt stock movement
--   4. For each line: upserts stock balance using weighted-average costing
--   5. Updates invoice status to 'posted'
--   6. Logs the event in financial_event_logs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_supplier_invoice(p_invoice_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invoice          public.supplier_invoices;
  v_line             public.supplier_invoice_lines;
  v_balance          public.inventory_stock_balances;
  v_unit_cost_stock  NUMERIC(14, 4);
  v_pre_tax_total    NUMERIC(14, 2);
  v_new_qty          NUMERIC(14, 4);
  v_new_avg_cost     NUMERIC(14, 4);
  v_new_total_value  NUMERIC(14, 2);
  v_user_id          UUID;
BEGIN
  v_user_id := auth.uid();

  -- Lock and load invoice
  SELECT * INTO v_invoice
  FROM public.supplier_invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice not found');
  END IF;

  IF v_invoice.status <> 'draft' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only draft invoices can be posted');
  END IF;

  -- Idempotency guard
  IF EXISTS (
    SELECT 1 FROM public.financial_event_logs
    WHERE source_module = 'inventory'
      AND event_type    = 'SUPPLIER_INVOICE_POSTED'
      AND reference_id  = p_invoice_id
      AND status        = 'processed'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice has already been posted');
  END IF;

  -- Validate at least one line exists
  IF NOT EXISTS (
    SELECT 1 FROM public.supplier_invoice_lines
    WHERE supplier_invoice_id = p_invoice_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot post an invoice with no line items');
  END IF;

  BEGIN
    -- Process each invoice line
    FOR v_line IN
      SELECT * FROM public.supplier_invoice_lines
      WHERE supplier_invoice_id = p_invoice_id
    LOOP
      -- unit_cost is per purchase unit; convert to per stock unit for internal tracking
      v_unit_cost_stock := v_line.unit_cost / v_line.conversion_rate;
      -- pre-tax total for this line (inventory asset value)
      v_pre_tax_total   := v_line.quantity_purchased * v_line.unit_cost;

      -- Stock movement: purchase_receipt (positive quantity)
      INSERT INTO public.inventory_stock_movements (
        company_id, outlet_id, stock_location_id, inventory_item_id,
        movement_type, reference_type, reference_id,
        quantity, unit_cost, total_cost, movement_date, created_by
      ) VALUES (
        v_invoice.company_id,
        v_invoice.outlet_id,
        v_invoice.stock_location_id,
        v_line.inventory_item_id,
        'purchase_receipt',
        'supplier_invoice',
        p_invoice_id::TEXT,
        v_line.quantity_in_stock_unit,
        v_unit_cost_stock,
        v_pre_tax_total,
        NOW(),
        v_user_id
      );

      -- Upsert stock balance with weighted-average cost recalculation
      SELECT * INTO v_balance
      FROM public.inventory_stock_balances
      WHERE company_id        = v_invoice.company_id
        AND outlet_id         = v_invoice.outlet_id
        AND stock_location_id = v_invoice.stock_location_id
        AND inventory_item_id = v_line.inventory_item_id
      FOR UPDATE;

      IF FOUND THEN
        v_new_qty       := v_balance.quantity_on_hand + v_line.quantity_in_stock_unit;
        v_new_avg_cost  := CASE
          WHEN v_new_qty > 0 THEN
            ((v_balance.quantity_on_hand * v_balance.average_cost) +
             (v_line.quantity_in_stock_unit * v_unit_cost_stock))
            / v_new_qty
          ELSE 0
        END;
        v_new_total_value := v_new_qty * v_new_avg_cost;

        UPDATE public.inventory_stock_balances
        SET
          quantity_on_hand = v_new_qty,
          average_cost     = v_new_avg_cost,
          total_value      = v_new_total_value,
          updated_at       = NOW()
        WHERE id = v_balance.id;
      ELSE
        -- No prior balance — create with this line's cost
        INSERT INTO public.inventory_stock_balances (
          company_id, outlet_id, stock_location_id, inventory_item_id,
          quantity_on_hand, average_cost, total_value, created_by
        ) VALUES (
          v_invoice.company_id,
          v_invoice.outlet_id,
          v_invoice.stock_location_id,
          v_line.inventory_item_id,
          v_line.quantity_in_stock_unit,
          v_unit_cost_stock,
          v_line.quantity_in_stock_unit * v_unit_cost_stock,
          v_user_id
        );
      END IF;
    END LOOP;

    -- Stamp the invoice as posted
    UPDATE public.supplier_invoices
    SET
      status     = 'posted',
      posted_at  = NOW(),
      posted_by  = v_user_id,
      updated_at = NOW()
    WHERE id = p_invoice_id;

    -- Idempotency log — success
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_id, status, payload
    ) VALUES (
      v_invoice.company_id,
      v_invoice.outlet_id,
      'inventory',
      'SUPPLIER_INVOICE_POSTED',
      p_invoice_id,
      'processed',
      jsonb_build_object(
        'invoice_id',         p_invoice_id,
        'supplier_id',        v_invoice.supplier_id,
        'stock_location_id',  v_invoice.stock_location_id,
        'total_amount',       v_invoice.total_amount
      )
    );

    RETURN jsonb_build_object('success', true, 'invoice_id', p_invoice_id);

  EXCEPTION WHEN OTHERS THEN
    -- Idempotency log — failure
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_id, status, error_message
    ) VALUES (
      v_invoice.company_id,
      v_invoice.outlet_id,
      'inventory',
      'SUPPLIER_INVOICE_POSTED',
      p_invoice_id,
      'failed',
      SQLERRM
    );

    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_supplier_invoice(UUID) TO authenticated;
