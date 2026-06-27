-- Migration: Add accounting journal posting to supplier invoice workflow
-- Created: 2026-05-22
-- Description:
--   Replaces post_supplier_invoice with a version that also posts:
--     Dr Inventory Asset (1200) = invoice total_amount
--     Cr Accounts Payable (2000) = invoice total_amount
--   Journal entry is linked to the invoice via reference_type/reference_id.
--   If inventory or AP accounts are not found the stock update still
--   commits, but the financial_event_log records the accounting failure.

CREATE OR REPLACE FUNCTION public.post_supplier_invoice(p_invoice_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invoice              public.supplier_invoices;
  v_supplier             public.inventory_suppliers;
  v_line                 public.supplier_invoice_lines;
  v_balance              public.inventory_stock_balances;
  v_unit_cost_stock      NUMERIC(14, 4);
  v_pre_tax_total        NUMERIC(14, 2);
  v_new_qty              NUMERIC(14, 4);
  v_new_avg_cost         NUMERIC(14, 4);
  v_new_total_value      NUMERIC(14, 2);
  v_inventory_account_id UUID;
  v_ap_account_id        UUID;
  v_journal_entry_id     UUID;
  v_user_id              UUID;
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

  -- Must have at least one line
  IF NOT EXISTS (
    SELECT 1 FROM public.supplier_invoice_lines
    WHERE supplier_invoice_id = p_invoice_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot post an invoice with no line items');
  END IF;

  -- Load supplier for memo
  SELECT * INTO v_supplier
  FROM public.inventory_suppliers
  WHERE id = v_invoice.supplier_id;

  BEGIN
    -- ── Stock movements + balance updates ──────────────────────────────────

    FOR v_line IN
      SELECT * FROM public.supplier_invoice_lines
      WHERE supplier_invoice_id = p_invoice_id
    LOOP
      v_unit_cost_stock := v_line.unit_cost / v_line.conversion_rate;
      v_pre_tax_total   := v_line.quantity_purchased * v_line.unit_cost;

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

      SELECT * INTO v_balance
      FROM public.inventory_stock_balances
      WHERE company_id        = v_invoice.company_id
        AND outlet_id         = v_invoice.outlet_id
        AND stock_location_id = v_invoice.stock_location_id
        AND inventory_item_id = v_line.inventory_item_id
      FOR UPDATE;

      IF FOUND THEN
        v_new_qty      := v_balance.quantity_on_hand + v_line.quantity_in_stock_unit;
        v_new_avg_cost := CASE
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

    -- ── Accounting journal entry ─────────────────────────────────────────
    -- Dr Inventory Asset (1200) = total_amount
    -- Cr Accounts Payable (2000) = total_amount
    --
    -- Tax is absorbed into inventory cost for now.
    -- VAT recovery can be split via tax account mappings in a later phase.

    SELECT id INTO v_inventory_account_id
    FROM public.accounts
    WHERE company_id = v_invoice.company_id
      AND code       = '1200'
      AND is_active  = true
    LIMIT 1;

    SELECT id INTO v_ap_account_id
    FROM public.accounts
    WHERE company_id = v_invoice.company_id
      AND code       = '2000'
      AND is_active  = true
    LIMIT 1;

    IF v_inventory_account_id IS NOT NULL AND v_ap_account_id IS NOT NULL THEN

      INSERT INTO public.journal_entries (
        company_id, outlet_id, posting_scope,
        reference_type, reference_id,
        source_module, entry_date, memo, status, created_by
      ) VALUES (
        v_invoice.company_id,
        v_invoice.outlet_id,
        'outlet'::public.journal_posting_scope,
        'supplier_invoice',
        p_invoice_id,
        'inventory'::public.journal_source_module,
        v_invoice.invoice_date,
        format(
          'Supplier invoice posted — %s (inv# %s)',
          COALESCE(v_supplier.name, 'Unknown supplier'),
          COALESCE(v_invoice.invoice_number, 'no number')
        ),
        'draft'::public.journal_entry_status,
        v_user_id
      )
      RETURNING id INTO v_journal_entry_id;

      -- Dr Inventory Asset
      INSERT INTO public.journal_entry_lines (
        company_id, journal_entry_id, account_id, outlet_id,
        debit, credit, description, created_by
      ) VALUES (
        v_invoice.company_id,
        v_journal_entry_id,
        v_inventory_account_id,
        v_invoice.outlet_id,
        ROUND(v_invoice.total_amount, 2),
        0,
        format('Inventory receipt from %s', COALESCE(v_supplier.name, 'supplier')),
        v_user_id
      );

      -- Cr Accounts Payable
      INSERT INTO public.journal_entry_lines (
        company_id, journal_entry_id, account_id, outlet_id,
        debit, credit, description, created_by
      ) VALUES (
        v_invoice.company_id,
        v_journal_entry_id,
        v_ap_account_id,
        v_invoice.outlet_id,
        0,
        ROUND(v_invoice.total_amount, 2),
        format('Payable to %s', COALESCE(v_supplier.name, 'supplier')),
        v_user_id
      );

      -- Stamp journal as posted
      UPDATE public.journal_entries
      SET status = 'posted'::public.journal_entry_status
      WHERE id = v_journal_entry_id;

    END IF;
    -- If accounts not found we still commit stock; the event log below
    -- will capture whether accounting succeeded.

    -- ── Stamp invoice as posted ──────────────────────────────────────────
    UPDATE public.supplier_invoices
    SET
      status     = 'posted',
      posted_at  = NOW(),
      posted_by  = v_user_id,
      updated_at = NOW()
    WHERE id = p_invoice_id;

    -- ── Event log — success ──────────────────────────────────────────────
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_id, journal_entry_id, status, payload
    ) VALUES (
      v_invoice.company_id,
      v_invoice.outlet_id,
      'inventory',
      'SUPPLIER_INVOICE_POSTED',
      p_invoice_id,
      v_journal_entry_id,
      'processed',
      jsonb_build_object(
        'invoice_id',         p_invoice_id,
        'supplier_id',        v_invoice.supplier_id,
        'stock_location_id',  v_invoice.stock_location_id,
        'total_amount',       v_invoice.total_amount,
        'journal_entry_id',   v_journal_entry_id,
        'accounting_posted',  v_journal_entry_id IS NOT NULL
      )
    );

    RETURN jsonb_build_object(
      'success',           true,
      'invoice_id',        p_invoice_id,
      'journal_entry_id',  v_journal_entry_id
    );

  EXCEPTION WHEN OTHERS THEN
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
