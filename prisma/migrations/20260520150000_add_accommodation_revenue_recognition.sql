-- ============================================================
-- Migration: Add accommodation revenue recognition
-- Created: 2026-05-20
-- Description:
--   - Adds stay-date based accommodation revenue recognition helpers
--   - Supports both nightly recognition and checkout catch-up posting
--   - Uses financial_event_logs for idempotency and audit traceability
--   - Uses existing accommodation booking lifecycle tables/events only

-- ============================================================
-- 1. Daily revenue allocation helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.calculate_accommodation_booking_daily_revenue(
  p_total_amount NUMERIC,
  p_check_in DATE,
  p_check_out DATE,
  p_stay_date DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_nights INTEGER;
  v_daily_base NUMERIC(12, 2);
BEGIN
  v_nights := GREATEST((p_check_out - p_check_in), 1);

  IF p_stay_date < p_check_in OR p_stay_date >= p_check_out THEN
    RETURN 0;
  END IF;

  v_daily_base := ROUND(COALESCE(p_total_amount, 0) / v_nights, 2);

  IF p_stay_date < (p_check_out - 1) THEN
    RETURN v_daily_base;
  END IF;

  RETURN ROUND(COALESCE(p_total_amount, 0) - (v_daily_base * (v_nights - 1)), 2);
END;
$$;

GRANT EXECUTE ON FUNCTION public.calculate_accommodation_booking_daily_revenue(NUMERIC, DATE, DATE, DATE) TO authenticated;

-- ============================================================
-- 2. Post one stay-date revenue recognition event
-- ============================================================
CREATE OR REPLACE FUNCTION public.post_accommodation_booking_revenue_recognition(
  p_booking_id UUID,
  p_stay_date DATE,
  p_trigger_source TEXT DEFAULT 'night_audit'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_event_log_id UUID;
  v_existing_event RECORD;
  v_journal_entry_id UUID;
  v_room_revenue_account_id UUID;
  v_unearned_account_id UUID;
  v_deposit_account_id UUID;
  v_receivable_account_id UUID;
  v_daily_revenue NUMERIC(12, 2);
  v_recognized_to_date NUMERIC(12, 2);
  v_paid_to_date NUMERIC(12, 2);
  v_precheckin_paid_to_date NUMERIC(12, 2);
  v_deposit_available NUMERIC(12, 2);
  v_liability_available NUMERIC(12, 2);
  v_unearned_available NUMERIC(12, 2);
  v_deposit_debit NUMERIC(12, 2);
  v_unearned_debit NUMERIC(12, 2);
  v_receivable_debit NUMERIC(12, 2);
  v_trigger_source_clean TEXT;
BEGIN
  v_trigger_source_clean := lower(NULLIF(btrim(COALESCE(p_trigger_source, 'night_audit')), ''));

  SELECT
    ab.id,
    ab.check_in,
    ab.check_out,
    ab.total_amount,
    ab.amount_paid,
    ab.status,
    ab.created_by,
    ab.source,
    ap.id AS property_id,
    ap.name AS property_name,
    ap.outlet_id,
    outl.company_id
  INTO v_booking
  FROM public.accommodation_bookings ab
  JOIN public.accommodation_properties ap
    ON ap.id = ab.property_id
  JOIN public.outlets outl
    ON outl.id = ap.outlet_id
  WHERE ab.id = p_booking_id
  LIMIT 1;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Accommodation booking % does not exist', p_booking_id;
  END IF;

  IF v_booking.status IN (
    'cancelled'::public.accommodation_booking_status,
    'no_show'::public.accommodation_booking_status
  ) THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'booking_id', p_booking_id,
      'stay_date', p_stay_date,
      'reason', 'cancelled_or_no_show'
    );
  END IF;

  IF p_stay_date < v_booking.check_in OR p_stay_date >= v_booking.check_out THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'booking_id', p_booking_id,
      'stay_date', p_stay_date,
      'reason', 'outside_stay_window'
    );
  END IF;

  v_daily_revenue := public.calculate_accommodation_booking_daily_revenue(
    v_booking.total_amount,
    v_booking.check_in,
    v_booking.check_out,
    p_stay_date
  );

  IF v_daily_revenue <= 0 THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'booking_id', p_booking_id,
      'stay_date', p_stay_date,
      'reason', 'zero_daily_revenue'
    );
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
    v_booking.company_id,
    v_booking.outlet_id,
    'booking_revenue_recognized:' || p_stay_date::text,
    'accommodation'::public.journal_source_module,
    'accommodation_booking_revenue',
    v_booking.id,
    'accommodation:revenue:' || v_booking.id::text || ':' || p_stay_date::text,
    'pending'::public.financial_event_status,
    jsonb_build_object(
      'booking_id', v_booking.id,
      'stay_date', p_stay_date,
      'trigger_source', COALESCE(v_trigger_source_clean, 'night_audit'),
      'recognized_amount', v_daily_revenue,
      'property_id', v_booking.property_id,
      'property_name', v_booking.property_name
    ),
    v_booking.created_by
  )
  ON CONFLICT (company_id, idempotency_key) DO NOTHING
  RETURNING id
  INTO v_event_log_id;

  IF v_event_log_id IS NULL THEN
    SELECT *
    INTO v_existing_event
    FROM public.financial_event_logs fel
    WHERE fel.company_id = v_booking.company_id
      AND fel.idempotency_key = 'accommodation:revenue:' || v_booking.id::text || ':' || p_stay_date::text
    LIMIT 1;

    IF v_existing_event.status = 'processed'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'processed',
        'journal_entry_id', v_existing_event.journal_entry_id,
        'event_log_id', v_existing_event.id,
        'booking_id', v_booking.id,
        'stay_date', p_stay_date
      );
    END IF;

    IF v_existing_event.status = 'ignored'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'ignored',
        'event_log_id', v_existing_event.id,
        'booking_id', v_booking.id,
        'stay_date', p_stay_date
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

  SELECT COALESCE(
    SUM((fel.payload ->> 'recognized_amount')::NUMERIC),
    0
  )::NUMERIC(12, 2)
  INTO v_recognized_to_date
  FROM public.financial_event_logs fel
  WHERE fel.company_id = v_booking.company_id
    AND fel.source_module = 'accommodation'::public.journal_source_module
    AND fel.reference_type = 'accommodation_booking_revenue'
    AND fel.reference_id = v_booking.id
    AND fel.status = 'processed'::public.financial_event_status
    AND (fel.payload ->> 'stay_date') IS NOT NULL
    AND ((fel.payload ->> 'stay_date')::DATE < p_stay_date);

  SELECT COALESCE(SUM(abp.amount), 0)::NUMERIC(12, 2)
  INTO v_paid_to_date
  FROM public.accommodation_booking_payments abp
  JOIN public.payment_methods pm
    ON pm.id = abp.payment_method_id
  WHERE abp.booking_id = v_booking.id
    AND abp.paid_at::DATE <= p_stay_date
    AND pm.type <> 'status'::public.payment_method_type;

  SELECT COALESCE(SUM(abp.amount), 0)::NUMERIC(12, 2)
  INTO v_precheckin_paid_to_date
  FROM public.accommodation_booking_payments abp
  JOIN public.payment_methods pm
    ON pm.id = abp.payment_method_id
  WHERE abp.booking_id = v_booking.id
    AND abp.paid_at::DATE <= p_stay_date
    AND abp.paid_at::DATE < v_booking.check_in
    AND pm.type <> 'status'::public.payment_method_type;

  v_deposit_available := GREATEST(v_precheckin_paid_to_date - v_recognized_to_date, 0)::NUMERIC(12, 2);
  v_liability_available := GREATEST(v_paid_to_date - v_recognized_to_date, 0)::NUMERIC(12, 2);
  v_unearned_available := GREATEST(v_liability_available - v_deposit_available, 0)::NUMERIC(12, 2);

  v_deposit_debit := LEAST(v_daily_revenue, v_deposit_available)::NUMERIC(12, 2);
  v_unearned_debit := LEAST(v_daily_revenue - v_deposit_debit, v_unearned_available)::NUMERIC(12, 2);
  v_receivable_debit := ROUND(v_daily_revenue - v_deposit_debit - v_unearned_debit, 2);

  v_room_revenue_account_id := public.get_company_account_id_by_code(v_booking.company_id, '4000');
  v_unearned_account_id := public.get_company_account_id_by_code(v_booking.company_id, '2100');
  v_deposit_account_id := public.get_company_account_id_by_code(v_booking.company_id, '2120');
  v_receivable_account_id := public.get_company_account_id_by_code(v_booking.company_id, '1110');

  IF v_room_revenue_account_id IS NULL THEN
    RAISE EXCEPTION 'Room Revenue account (4000) is not configured for company %.', v_booking.company_id;
  END IF;

  IF v_deposit_debit > 0 AND v_deposit_account_id IS NULL THEN
    RAISE EXCEPTION 'Advance Guest Deposits account (2120) is not configured for company %.', v_booking.company_id;
  END IF;

  IF v_unearned_debit > 0 AND v_unearned_account_id IS NULL THEN
    RAISE EXCEPTION 'Unearned Room Revenue account (2100) is not configured for company %.', v_booking.company_id;
  END IF;

  IF v_receivable_debit > 0 AND v_receivable_account_id IS NULL THEN
    RAISE EXCEPTION 'Guest Receivables account (1110) is not configured for company %.', v_booking.company_id;
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
    v_booking.company_id,
    v_booking.outlet_id,
    'outlet'::public.journal_posting_scope,
    'accommodation_booking_revenue',
    v_booking.id,
    'accommodation'::public.journal_source_module,
    p_stay_date,
    format(
      'Accommodation revenue recognition for booking %s on %s (%s).',
      v_booking.id,
      p_stay_date,
      COALESCE(v_trigger_source_clean, 'night_audit')
    ),
    'draft'::public.journal_entry_status,
    v_booking.created_by
  )
  RETURNING id
  INTO v_journal_entry_id;

  IF v_deposit_debit > 0 THEN
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
      v_booking.company_id,
      v_journal_entry_id,
      v_deposit_account_id,
      v_booking.outlet_id,
      v_deposit_debit,
      0,
      'Recognize revenue from advance guest deposits',
      v_booking.created_by
    );
  END IF;

  IF v_unearned_debit > 0 THEN
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
      v_booking.company_id,
      v_journal_entry_id,
      v_unearned_account_id,
      v_booking.outlet_id,
      v_unearned_debit,
      0,
      'Recognize earned revenue from unearned room revenue',
      v_booking.created_by
    );
  END IF;

  IF v_receivable_debit > 0 THEN
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
      v_booking.company_id,
      v_journal_entry_id,
      v_receivable_account_id,
      v_booking.outlet_id,
      v_receivable_debit,
      0,
      'Recognize earned revenue as guest receivable',
      v_booking.created_by
    );
  END IF;

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
    v_booking.company_id,
    v_journal_entry_id,
    v_room_revenue_account_id,
    v_booking.outlet_id,
    0,
    v_daily_revenue,
    'Recognize earned accommodation room revenue',
    v_booking.created_by
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
    payload = COALESCE(payload, '{}'::jsonb)
      || jsonb_build_object(
        'recognized_amount', v_daily_revenue,
        'deposit_debit', v_deposit_debit,
        'unearned_debit', v_unearned_debit,
        'receivable_debit', v_receivable_debit,
        'stay_date', p_stay_date,
        'trigger_source', COALESCE(v_trigger_source_clean, 'night_audit')
      ),
    updated_at = NOW()
  WHERE id = v_event_log_id;

  RETURN jsonb_build_object(
    'status', 'processed',
    'journal_entry_id', v_journal_entry_id,
    'event_log_id', v_event_log_id,
    'booking_id', v_booking.id,
    'stay_date', p_stay_date,
    'recognized_amount', v_daily_revenue
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

GRANT EXECUTE ON FUNCTION public.post_accommodation_booking_revenue_recognition(UUID, DATE, TEXT) TO authenticated;

-- ============================================================
-- 3. Property night audit revenue recognition
-- ============================================================
CREATE OR REPLACE FUNCTION public.run_accommodation_night_audit_revenue_recognition(
  p_property_id UUID,
  p_stay_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id BIGINT;
  v_processed_count INTEGER := 0;
  v_booking RECORD;
BEGIN
  SELECT o.company_id
  INTO v_company_id
  FROM public.accommodation_properties ap
  JOIN public.outlets o
    ON o.id = ap.outlet_id
  WHERE ap.id = p_property_id
  LIMIT 1;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Accommodation property % does not exist', p_property_id;
  END IF;

  IF v_company_id <> public.get_auth_user_company_id() THEN
    RAISE EXCEPTION 'Property is not accessible for the current user';
  END IF;

  FOR v_booking IN
    SELECT ab.id
    FROM public.accommodation_bookings ab
    WHERE ab.property_id = p_property_id
      AND ab.status IN (
        'checked_in'::public.accommodation_booking_status,
        'checked_out'::public.accommodation_booking_status
      )
      AND ab.check_in <= p_stay_date
      AND ab.check_out > p_stay_date
  LOOP
    PERFORM public.post_accommodation_booking_revenue_recognition(
      v_booking.id,
      p_stay_date,
      'night_audit'
    );
    v_processed_count := v_processed_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'processed',
    'property_id', p_property_id,
    'stay_date', p_stay_date,
    'bookings_considered', v_processed_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.run_accommodation_night_audit_revenue_recognition(UUID, DATE) TO authenticated;

-- ============================================================
-- 4. Checkout catch-up trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_accommodation_checkout_revenue_recognition_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stay_date DATE;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.status = 'checked_out'::public.accommodation_booking_status THEN
    v_stay_date := NEW.check_in;

    WHILE v_stay_date < NEW.check_out LOOP
      PERFORM public.post_accommodation_booking_revenue_recognition(
        NEW.id,
        v_stay_date,
        'checkout'
      );
      v_stay_date := v_stay_date + 1;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS accommodation_checkout_revenue_recognition_after_update
  ON public.accommodation_bookings;

CREATE TRIGGER accommodation_checkout_revenue_recognition_after_update
  AFTER UPDATE ON public.accommodation_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_accommodation_checkout_revenue_recognition_trigger();
