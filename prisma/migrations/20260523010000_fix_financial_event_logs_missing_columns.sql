-- Migration: Fix missing reference_type and idempotency_key in financial_event_logs INSERTs
-- Both post_supplier_invoice and record_supplier_payment omitted these NOT NULL columns,
-- causing constraint violations when creating or posting invoices/payments.

-- ─────────────────────────────────────────────────────────────────────────────
-- post_supplier_invoice (replaces version in 20260522140000)
-- ─────────────────────────────────────────────────────────────────────────────
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

  IF EXISTS (
    SELECT 1 FROM public.financial_event_logs
    WHERE source_module  = 'inventory'
      AND event_type     = 'SUPPLIER_INVOICE_POSTED'
      AND reference_type = 'supplier_invoice'
      AND reference_id   = p_invoice_id
      AND status         = 'processed'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invoice has already been posted');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.supplier_invoice_lines
    WHERE supplier_invoice_id = p_invoice_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot post an invoice with no line items');
  END IF;

  SELECT * INTO v_supplier
  FROM public.inventory_suppliers
  WHERE id = v_invoice.supplier_id;

  BEGIN
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

      UPDATE public.journal_entries
      SET status = 'posted'::public.journal_entry_status
      WHERE id = v_journal_entry_id;

    END IF;

    UPDATE public.supplier_invoices
    SET
      status     = 'posted',
      posted_at  = NOW(),
      posted_by  = v_user_id,
      updated_at = NOW()
    WHERE id = p_invoice_id;

    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id,
      idempotency_key,
      journal_entry_id, status, payload
    ) VALUES (
      v_invoice.company_id,
      v_invoice.outlet_id,
      'inventory',
      'SUPPLIER_INVOICE_POSTED',
      'supplier_invoice',
      p_invoice_id,
      format('supplier_invoice_post_%s', p_invoice_id),
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
      reference_type, reference_id,
      idempotency_key,
      status, error_message
    ) VALUES (
      v_invoice.company_id,
      v_invoice.outlet_id,
      'inventory',
      'SUPPLIER_INVOICE_POSTED',
      'supplier_invoice',
      p_invoice_id,
      format('supplier_invoice_post_err_%s', gen_random_uuid()),
      'failed',
      SQLERRM
    );

    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_supplier_invoice(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- record_supplier_payment (replaces version in 20260522143000)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.record_supplier_payment(
  p_company_id        BIGINT,
  p_outlet_id         UUID,
  p_supplier_id       UUID,
  p_payment_date      DATE,
  p_amount            NUMERIC(14, 2),
  p_payment_method_id INTEGER,
  p_reference         TEXT,
  p_notes             TEXT,
  p_allocations       JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_payment_id        UUID;
  v_ap_account_id     UUID;
  v_cash_account_id   UUID;
  v_journal_entry_id  UUID;
  v_alloc             JSONB;
  v_invoice_id        UUID;
  v_amount_applied    NUMERIC(14, 2);
  v_invoice           public.supplier_invoices;
  v_new_amount_paid   NUMERIC(14, 2);
  v_new_status        TEXT;
  v_pm_name           TEXT;
  v_user_id           UUID;
  v_pm_id             INTEGER;
BEGIN
  v_user_id := auth.uid();

  IF (
    SELECT COALESCE(SUM((elem->>'amount_applied')::NUMERIC), 0)
    FROM jsonb_array_elements(p_allocations) AS elem
  ) > p_amount THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Total allocation cannot exceed payment amount'
    );
  END IF;

  BEGIN
    INSERT INTO public.supplier_payments (
      company_id, outlet_id, supplier_id,
      payment_date, amount, payment_method_id,
      reference, notes, created_by
    ) VALUES (
      p_company_id, p_outlet_id, p_supplier_id,
      p_payment_date, p_amount, p_payment_method_id,
      NULLIF(BTRIM(COALESCE(p_reference, '')), ''),
      NULLIF(BTRIM(COALESCE(p_notes, '')), ''),
      v_user_id
    )
    RETURNING id INTO v_payment_id;

    FOR v_alloc IN SELECT * FROM jsonb_array_elements(p_allocations)
    LOOP
      v_invoice_id     := (v_alloc->>'invoice_id')::UUID;
      v_amount_applied := (v_alloc->>'amount_applied')::NUMERIC(14, 2);

      INSERT INTO public.supplier_invoice_payments (
        supplier_payment_id, supplier_invoice_id, amount_applied
      ) VALUES (v_payment_id, v_invoice_id, v_amount_applied);

      SELECT * INTO v_invoice
      FROM public.supplier_invoices
      WHERE id = v_invoice_id AND company_id = p_company_id
      FOR UPDATE;

      IF FOUND THEN
        v_new_amount_paid := v_invoice.amount_paid + v_amount_applied;
        v_new_status := CASE
          WHEN v_new_amount_paid >= v_invoice.total_amount THEN 'paid'
          WHEN v_new_amount_paid > 0                       THEN 'partially_paid'
          ELSE v_invoice.status
        END;

        UPDATE public.supplier_invoices
        SET
          amount_paid = v_new_amount_paid,
          status      = v_new_status,
          updated_at  = NOW()
        WHERE id = v_invoice_id;
      END IF;
    END LOOP;

    SELECT id INTO v_ap_account_id
    FROM public.accounts
    WHERE company_id = p_company_id AND code = '2000' AND is_active = true
    LIMIT 1;

    v_pm_id := p_payment_method_id;
    IF v_pm_id IS NOT NULL THEN
      SELECT a.id INTO v_cash_account_id
      FROM public.payment_method_account_mappings pmam
      JOIN public.accounts a ON a.id = pmam.account_id
      WHERE pmam.payment_method_id = v_pm_id
        AND pmam.company_id        = p_company_id
        AND a.is_active            = true
      LIMIT 1;
    END IF;

    IF v_cash_account_id IS NULL THEN
      SELECT id INTO v_cash_account_id
      FROM public.accounts
      WHERE company_id = p_company_id AND code = '1000' AND is_active = true
      LIMIT 1;
    END IF;

    IF v_ap_account_id IS NOT NULL AND v_cash_account_id IS NOT NULL THEN
      SELECT name INTO v_pm_name
      FROM public.payment_methods
      WHERE id = v_pm_id
      LIMIT 1;

      INSERT INTO public.journal_entries (
        company_id, outlet_id, posting_scope,
        reference_type, reference_id,
        source_module, entry_date, memo, status, created_by
      ) VALUES (
        p_company_id, p_outlet_id,
        'outlet'::public.journal_posting_scope,
        'supplier_payment',
        v_payment_id,
        'inventory'::public.journal_source_module,
        p_payment_date,
        format(
          'Supplier payment — %s via %s',
          p_reference,
          COALESCE(v_pm_name, 'cash')
        ),
        'draft'::public.journal_entry_status,
        v_user_id
      )
      RETURNING id INTO v_journal_entry_id;

      INSERT INTO public.journal_entry_lines (
        company_id, journal_entry_id, account_id, outlet_id,
        debit, credit, description, created_by
      ) VALUES (
        p_company_id, v_journal_entry_id, v_ap_account_id, p_outlet_id,
        ROUND(p_amount, 2), 0,
        'Supplier payable cleared',
        v_user_id
      );

      INSERT INTO public.journal_entry_lines (
        company_id, journal_entry_id, account_id, outlet_id,
        debit, credit, description, created_by
      ) VALUES (
        p_company_id, v_journal_entry_id, v_cash_account_id, p_outlet_id,
        0, ROUND(p_amount, 2),
        format('Payment via %s', COALESCE(v_pm_name, 'cash')),
        v_user_id
      );

      UPDATE public.journal_entries
      SET status = 'posted'::public.journal_entry_status
      WHERE id = v_journal_entry_id;

      UPDATE public.supplier_payments
      SET journal_entry_id = v_journal_entry_id
      WHERE id = v_payment_id;
    END IF;

    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id,
      idempotency_key,
      journal_entry_id, status, payload
    ) VALUES (
      p_company_id, p_outlet_id,
      'inventory',
      'SUPPLIER_PAYMENT_RECORDED',
      'supplier_payment',
      v_payment_id,
      format('supplier_payment_%s', v_payment_id),
      v_journal_entry_id,
      'processed',
      jsonb_build_object(
        'payment_id',       v_payment_id,
        'supplier_id',      p_supplier_id,
        'amount',           p_amount,
        'allocations',      p_allocations,
        'journal_entry_id', v_journal_entry_id
      )
    );

    RETURN jsonb_build_object(
      'success',          true,
      'payment_id',       v_payment_id,
      'journal_entry_id', v_journal_entry_id
    );

  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id,
      idempotency_key,
      status, error_message
    ) VALUES (
      p_company_id, p_outlet_id,
      'inventory',
      'SUPPLIER_PAYMENT_RECORDED',
      'supplier_payment',
      COALESCE(v_payment_id, gen_random_uuid()),
      format('supplier_payment_err_%s', gen_random_uuid()),
      'failed',
      SQLERRM
    );

    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_supplier_payment(
  BIGINT, UUID, UUID, DATE, NUMERIC, INTEGER, TEXT, TEXT, JSONB
) TO authenticated;
