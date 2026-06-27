-- Migration: Supplier payments foundation
-- Created: 2026-05-22
-- Description:
--   - Creates supplier_payments (payment header)
--   - Creates supplier_invoice_payments (links payment to one or more invoices)
--   - post_supplier_payment RPC:
--       updates invoice amount_paid + status,
--       posts Dr Accounts Payable / Cr Cash/Bank journal entry

-- ─────────────────────────────────────────────────────────────────────────────
-- supplier_payments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.supplier_payments (
  id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id        BIGINT        NOT NULL REFERENCES public.companies(id)          ON DELETE CASCADE,
  outlet_id         UUID          NOT NULL REFERENCES public.outlets(id)            ON DELETE CASCADE,
  supplier_id       UUID          NOT NULL REFERENCES public.inventory_suppliers(id) ON DELETE RESTRICT,
  payment_date      DATE          NOT NULL DEFAULT CURRENT_DATE,
  amount            NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  payment_method_id INTEGER       REFERENCES public.payment_methods(id)             ON DELETE SET NULL,
  reference         TEXT,
  notes             TEXT,
  journal_entry_id  UUID          REFERENCES public.journal_entries(id)             ON DELETE SET NULL,
  created_by        UUID          REFERENCES public.users(id)                        ON DELETE SET NULL DEFAULT auth.uid(),
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_supplier_payments_company_supplier
  ON public.supplier_payments(company_id, supplier_id, payment_date DESC);

CREATE INDEX IF NOT EXISTS idx_supplier_payments_outlet
  ON public.supplier_payments(company_id, outlet_id, payment_date DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- supplier_invoice_payments  (payment ↔ invoice allocation)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.supplier_invoice_payments (
  id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_payment_id   UUID          NOT NULL REFERENCES public.supplier_payments(id)  ON DELETE CASCADE,
  supplier_invoice_id   UUID          NOT NULL REFERENCES public.supplier_invoices(id)  ON DELETE RESTRICT,
  amount_applied        NUMERIC(14, 2) NOT NULL CHECK (amount_applied > 0),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (supplier_payment_id, supplier_invoice_id)
);

CREATE INDEX IF NOT EXISTS idx_supplier_invoice_payments_invoice
  ON public.supplier_invoice_payments(supplier_invoice_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — supplier_payments
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.supplier_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view supplier payments in their company" ON public.supplier_payments;
CREATE POLICY "Users can view supplier payments in their company"
  ON public.supplier_payments FOR SELECT TO authenticated
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can insert supplier payments in their company" ON public.supplier_payments;
CREATE POLICY "Users can insert supplier payments in their company"
  ON public.supplier_payments FOR INSERT TO authenticated
  WITH CHECK (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Users can update supplier payments in their company" ON public.supplier_payments;
CREATE POLICY "Users can update supplier payments in their company"
  ON public.supplier_payments FOR UPDATE TO authenticated
  USING (company_id = public.get_auth_user_company_id())
  WITH CHECK (company_id = public.get_auth_user_company_id());

GRANT SELECT, INSERT, UPDATE ON public.supplier_payments TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — supplier_invoice_payments
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.supplier_invoice_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view supplier invoice payment allocations in their company" ON public.supplier_invoice_payments;
CREATE POLICY "Users can view supplier invoice payment allocations in their company"
  ON public.supplier_invoice_payments FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.supplier_payments sp
      WHERE sp.id = supplier_payment_id
      AND sp.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Users can insert supplier invoice payment allocations in their company" ON public.supplier_invoice_payments;
CREATE POLICY "Users can insert supplier invoice payment allocations in their company"
  ON public.supplier_invoice_payments FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.supplier_payments sp
      WHERE sp.id = supplier_payment_id
      AND sp.company_id = public.get_auth_user_company_id()
    )
  );

GRANT SELECT, INSERT ON public.supplier_invoice_payments TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- record_supplier_payment RPC
-- ─────────────────────────────────────────────────────────────────────────────
-- Input: payment header + array of {invoice_id, amount_applied} allocations
-- On success:
--   1. Creates supplier_payment record
--   2. Creates supplier_invoice_payment allocations
--   3. Updates each invoice's amount_paid + status
--   4. Posts Dr Accounts Payable / Cr Cash/Bank journal entry
--   5. Logs financial event
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
  p_allocations       JSONB  -- [{invoice_id: UUID, amount_applied: numeric}]
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

  -- Validate total allocation does not exceed payment amount
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
    -- ── Create payment header ──────────────────────────────────────────────
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

    -- ── Process each allocation ────────────────────────────────────────────
    FOR v_alloc IN SELECT * FROM jsonb_array_elements(p_allocations)
    LOOP
      v_invoice_id     := (v_alloc->>'invoice_id')::UUID;
      v_amount_applied := (v_alloc->>'amount_applied')::NUMERIC(14, 2);

      -- Link allocation
      INSERT INTO public.supplier_invoice_payments (
        supplier_payment_id, supplier_invoice_id, amount_applied
      ) VALUES (v_payment_id, v_invoice_id, v_amount_applied);

      -- Update invoice paid amount and status
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

    -- ── Accounting: Dr Accounts Payable / Cr Cash/Bank ────────────────────
    SELECT id INTO v_ap_account_id
    FROM public.accounts
    WHERE company_id = p_company_id AND code = '2000' AND is_active = true
    LIMIT 1;

    -- Try to resolve cash account from payment method mapping first
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

    -- Fallback to Cash on Hand (1000) if no mapping
    IF v_cash_account_id IS NULL THEN
      SELECT id INTO v_cash_account_id
      FROM public.accounts
      WHERE company_id = p_company_id AND code = '1000' AND is_active = true
      LIMIT 1;
    END IF;

    IF v_ap_account_id IS NOT NULL AND v_cash_account_id IS NOT NULL THEN
      -- Payment method name for memo
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

      -- Dr Accounts Payable
      INSERT INTO public.journal_entry_lines (
        company_id, journal_entry_id, account_id, outlet_id,
        debit, credit, description, created_by
      ) VALUES (
        p_company_id, v_journal_entry_id, v_ap_account_id, p_outlet_id,
        ROUND(p_amount, 2), 0,
        'Supplier payable cleared',
        v_user_id
      );

      -- Cr Cash/Bank
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

      -- Update payment with journal reference
      UPDATE public.supplier_payments
      SET journal_entry_id = v_journal_entry_id
      WHERE id = v_payment_id;
    END IF;

    -- ── Event log ────────────────────────────────────────────────────────
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_id, journal_entry_id, status, payload
    ) VALUES (
      p_company_id, p_outlet_id,
      'inventory',
      'SUPPLIER_PAYMENT_RECORDED',
      v_payment_id,
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
      reference_id, status, error_message
    ) VALUES (
      p_company_id, p_outlet_id,
      'inventory',
      'SUPPLIER_PAYMENT_RECORDED',
      NULL,
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
