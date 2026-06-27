-- ============================================================
-- Migration: Add accommodation payment accounting trigger
-- ============================================================

-- 1. Resolve the liability or receivable side for booking payments
CREATE OR REPLACE FUNCTION public.resolve_accommodation_payment_credit_account(
  p_company_id BIGINT,
  p_booking_status public.accommodation_booking_status,
  p_check_in DATE,
  p_check_out DATE,
  p_paid_at TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_check_in IS NOT NULL AND p_paid_at::DATE < p_check_in THEN
    RETURN public.get_company_account_id_by_code(p_company_id, '2120');
  END IF;

  IF p_check_out IS NOT NULL
     AND p_paid_at::DATE >= p_check_out
     AND p_booking_status = 'checked_out'::public.accommodation_booking_status THEN
    RETURN public.get_company_account_id_by_code(p_company_id, '1110');
  END IF;

  RETURN public.get_company_account_id_by_code(p_company_id, '2100');
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_accommodation_payment_credit_account(BIGINT, public.accommodation_booking_status, DATE, DATE, TIMESTAMPTZ) TO authenticated;

-- 2. Post accounting for one accommodation payment row
CREATE OR REPLACE FUNCTION public.post_accommodation_booking_payment_accounting(
  p_payment_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment RECORD;
  v_payment_method RECORD;
  v_event_log_id UUID;
  v_existing_event RECORD;
  v_debit_account_id UUID;
  v_credit_account_id UUID;
  v_journal_entry_id UUID;
BEGIN
  SELECT
    abp.id,
    abp.booking_id,
    abp.amount,
    abp.payment_method_id,
    abp.notes,
    abp.paid_at,
    abp.recorded_by,
    ab.id AS resolved_booking_id,
    ab.status AS booking_status,
    ab.check_in,
    ab.check_out,
    ab.total_amount,
    ab.amount_paid,
    ab.source,
    ab.external_id,
    ap.id AS property_id,
    ap.name AS property_name,
    ap.outlet_id,
    outl.company_id
  INTO v_payment
  FROM public.accommodation_booking_payments abp
  JOIN public.accommodation_bookings ab
    ON ab.id = abp.booking_id
  JOIN public.accommodation_properties ap
    ON ap.id = ab.property_id
  JOIN public.outlets outl
    ON outl.id = ap.outlet_id
  WHERE abp.id = p_payment_id
  LIMIT 1;

  IF v_payment.id IS NULL THEN
    RAISE EXCEPTION 'Accommodation payment % does not exist', p_payment_id;
  END IF;

  SELECT pm.id, pm.name, pm.type
  INTO v_payment_method
  FROM public.payment_methods pm
  WHERE pm.id = v_payment.payment_method_id
  LIMIT 1;

  IF v_payment_method.id IS NULL THEN
    RAISE EXCEPTION 'Accommodation payment % has an unknown payment method', p_payment_id;
  END IF;

  INSERT INTO public.financial_event_logs (
    company_id,
    outlet_id,
    event_type,
    source_module,
    reference_type,
    reference_id,
    idempotency_key,
    status,
    payload,
    created_by
  )
  VALUES (
    v_payment.company_id,
    v_payment.outlet_id,
    'booking_payment_received',
    'accommodation'::public.journal_source_module,
    'accommodation_booking_payment',
    v_payment.id,
    'accommodation:booking_payment:' || v_payment.id::text,
    'pending'::public.financial_event_status,
    jsonb_build_object(
      'booking_id', v_payment.booking_id,
      'payment_id', v_payment.id,
      'payment_method_id', v_payment.payment_method_id,
      'payment_method_name', v_payment_method.name,
      'booking_status', v_payment.booking_status,
      'amount', v_payment.amount,
      'property_id', v_payment.property_id,
      'property_name', v_payment.property_name
    ),
    v_payment.recorded_by
  )
  ON CONFLICT (company_id, idempotency_key) DO NOTHING
  RETURNING id
  INTO v_event_log_id;

  IF v_event_log_id IS NULL THEN
    SELECT *
    INTO v_existing_event
    FROM public.financial_event_logs fel
    WHERE fel.company_id = v_payment.company_id
      AND fel.idempotency_key = 'accommodation:booking_payment:' || v_payment.id::text
    LIMIT 1;

    IF v_existing_event.status = 'processed'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'processed',
        'journal_entry_id', v_existing_event.journal_entry_id,
        'event_log_id', v_existing_event.id,
        'payment_id', v_payment.id,
        'booking_id', v_payment.booking_id
      );
    END IF;

    IF v_existing_event.status = 'ignored'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'ignored',
        'journal_entry_id', v_existing_event.journal_entry_id,
        'event_log_id', v_existing_event.id,
        'payment_id', v_payment.id,
        'booking_id', v_payment.booking_id
      );
    END IF;

    v_event_log_id := v_existing_event.id;

    UPDATE public.financial_event_logs
    SET
      status = 'pending'::public.financial_event_status,
      error_message = NULL,
      processed_at = NULL,
      journal_entry_id = NULL,
      updated_at = NOW()
    WHERE id = v_event_log_id;
  END IF;

  IF v_payment_method.type = 'status'::public.payment_method_type THEN
    UPDATE public.financial_event_logs
    SET
      status = 'ignored'::public.financial_event_status,
      error_message = 'Operational payment method types do not create accommodation payment journals.',
      processed_at = NOW(),
      updated_at = NOW()
    WHERE id = v_event_log_id;

    RETURN jsonb_build_object(
      'status', 'ignored',
      'event_log_id', v_event_log_id,
      'payment_id', v_payment.id,
      'booking_id', v_payment.booking_id
    );
  END IF;

  v_debit_account_id := public.resolve_sales_settlement_debit_account(
    v_payment.company_id,
    v_payment.payment_method_id
  );

  IF v_debit_account_id IS NULL THEN
    RAISE EXCEPTION 'No debit account could be resolved for accommodation payment method % (%).',
      v_payment_method.name,
      v_payment.payment_method_id;
  END IF;

  v_credit_account_id := public.resolve_accommodation_payment_credit_account(
    v_payment.company_id,
    v_payment.booking_status,
    v_payment.check_in,
    v_payment.check_out,
    v_payment.paid_at
  );

  IF v_credit_account_id IS NULL THEN
    RAISE EXCEPTION
      'No credit account could be resolved for accommodation booking payment %.',
      v_payment.id;
  END IF;

  INSERT INTO public.journal_entries (
    company_id,
    outlet_id,
    posting_scope,
    reference_type,
    reference_id,
    source_module,
    entry_date,
    memo,
    status,
    created_by
  )
  VALUES (
    v_payment.company_id,
    v_payment.outlet_id,
    'outlet'::public.journal_posting_scope,
    'accommodation_booking_payment',
    v_payment.id,
    'accommodation'::public.journal_source_module,
    v_payment.paid_at::DATE,
    format(
      'Accommodation payment posting for booking %s at %s (payment %s, method %s, source %s).',
      v_payment.booking_id,
      v_payment.property_name,
      v_payment.id,
      v_payment_method.name,
      COALESCE(v_payment.source, 'direct')
    ),
    'draft'::public.journal_entry_status,
    v_payment.recorded_by
  )
  RETURNING id
  INTO v_journal_entry_id;

  INSERT INTO public.journal_entry_lines (
    company_id,
    journal_entry_id,
    account_id,
    outlet_id,
    debit,
    credit,
    description,
    created_by
  )
  VALUES (
    v_payment.company_id,
    v_journal_entry_id,
    v_debit_account_id,
    v_payment.outlet_id,
    ROUND(v_payment.amount, 2),
    0,
    format('Accommodation payment via %s', v_payment_method.name),
    v_payment.recorded_by
  );

  INSERT INTO public.journal_entry_lines (
    company_id,
    journal_entry_id,
    account_id,
    outlet_id,
    debit,
    credit,
    description,
    created_by
  )
  VALUES (
    v_payment.company_id,
    v_journal_entry_id,
    v_credit_account_id,
    v_payment.outlet_id,
    0,
    ROUND(v_payment.amount, 2),
    CASE
      WHEN v_payment.booking_status = 'checked_out'::public.accommodation_booking_status
           AND v_payment.check_out IS NOT NULL
           AND v_payment.paid_at::DATE >= v_payment.check_out
        THEN 'Settlement of earned guest receivable'
      WHEN v_payment.check_in IS NOT NULL AND v_payment.paid_at::DATE < v_payment.check_in
        THEN 'Advance guest deposit received before check-in'
      ELSE 'Unearned accommodation revenue collected'
    END,
    v_payment.recorded_by
  );

  UPDATE public.journal_entries
  SET status = 'posted'::public.journal_entry_status
  WHERE id = v_journal_entry_id;

  UPDATE public.financial_event_logs
  SET
    status = 'processed'::public.financial_event_status,
    journal_entry_id = v_journal_entry_id,
    processed_at = NOW(),
    error_message = NULL,
    updated_at = NOW()
  WHERE id = v_event_log_id;

  RETURN jsonb_build_object(
    'status', 'processed',
    'journal_entry_id', v_journal_entry_id,
    'event_log_id', v_event_log_id,
    'payment_id', v_payment.id,
    'booking_id', v_payment.booking_id
  );

EXCEPTION
  WHEN OTHERS THEN
    IF v_event_log_id IS NOT NULL THEN
      UPDATE public.financial_event_logs
      SET
        status = 'failed'::public.financial_event_status,
        error_message = SQLERRM,
        updated_at = NOW()
      WHERE id = v_event_log_id;
    END IF;

    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_accommodation_booking_payment_accounting(UUID) TO authenticated;

-- 3. Trigger booking payment posting automatically
CREATE OR REPLACE FUNCTION public.handle_accommodation_booking_payment_accounting_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.post_accommodation_booking_payment_accounting(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS accommodation_booking_payment_accounting_after_insert
  ON public.accommodation_booking_payments;

CREATE TRIGGER accommodation_booking_payment_accounting_after_insert
  AFTER INSERT ON public.accommodation_booking_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_accommodation_booking_payment_accounting_trigger();
