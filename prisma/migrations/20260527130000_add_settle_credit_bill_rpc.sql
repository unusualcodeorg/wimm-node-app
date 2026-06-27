-- Migration: Add settle_credit_bill RPC
-- Created: 2026-05-27
-- Description:
--   Adds settle_credit_bill(order_id, payment_method_id, notes) so that
--   a CREDIT bill can be paid at a later date.
--
--   Accounting flow:
--     1. The original CREDIT settlement (Dr AR / Cr Revenue) is reversed via
--        a new journal entry posted on the payment day.
--     2. The old CREDIT settlement record is deleted.
--     3. The order's date is moved to the outlet's current business day
--        so it appears in that day's sales report.
--     4. A new settlement is inserted with the real payment method; the
--        existing trigger fires and posts the correct entry (Dr Cash/Card/etc.
--        / Cr Revenue) dated on the payment day.
--     5. Notes are auto-prefixed with
--        "Credit bill from {original_date}, paid on {payment_date}."
--        so the audit trail is preserved in the settlement record.

CREATE OR REPLACE FUNCTION public.settle_credit_bill(
  p_order_id         UUID,
  p_payment_method_id INTEGER,
  p_notes            TEXT DEFAULT NULL
)
RETURNS public.order_settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id                UUID;
  v_user_company_id        BIGINT;
  v_credit_pm_id           INTEGER;
  v_pm_type                public.payment_method_type;
  v_pm_name                TEXT;
  v_order                  RECORD;
  v_old_settlement         public.order_settlements;
  v_old_je_id              UUID;
  v_reversal_je_id         UUID;
  v_new_settlement         public.order_settlements;
  v_original_date          DATE;
  v_payment_date           DATE;
  v_note_text              TEXT;
BEGIN
  -- Auth ----------------------------------------------------------------
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Caller company ------------------------------------------------------
  SELECT o.company_id
  INTO   v_user_company_id
  FROM   public.users u
  JOIN   public.outlets o ON o.id = u.outlet_id
  WHERE  u.id = v_user_id
  LIMIT  1;

  IF v_user_company_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve company for current user';
  END IF;

  -- CREDIT payment method id -------------------------------------------
  SELECT id
  INTO   v_credit_pm_id
  FROM   public.payment_methods
  WHERE  name = 'CREDIT'
  LIMIT  1;

  IF v_credit_pm_id IS NULL THEN
    RAISE EXCEPTION 'CREDIT payment method is not configured';
  END IF;

  -- Validate target payment method is a real settlement type -----------
  SELECT pm.type, pm.name
  INTO   v_pm_type, v_pm_name
  FROM   public.payment_methods pm
  WHERE  pm.id = p_payment_method_id;

  IF v_pm_type IS NULL THEN
    RAISE EXCEPTION 'Payment method % does not exist', p_payment_method_id;
  END IF;

  IF v_pm_type = 'status'::public.payment_method_type
     OR v_pm_type = 'credit'::public.payment_method_type THEN
    RAISE EXCEPTION
      'Payment method % cannot be used to settle a credit bill. Use cash, card, mobile money, EFT or similar.',
      v_pm_name;
  END IF;

  -- Lock and fetch the order -------------------------------------------
  SELECT
    ord.id,
    ord.status_id,
    ord.date           AS original_date,
    ord.outlet_id,
    ord.bill_number,
    outl.company_id,
    outl.day_open      AS outlet_day_open
  INTO v_order
  FROM   public.orders   ord
  JOIN   public.outlets  outl ON outl.id = ord.outlet_id
  WHERE  ord.id = p_order_id
  FOR UPDATE OF ord;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Order % does not exist', p_order_id;
  END IF;

  IF v_order.company_id <> v_user_company_id THEN
    RAISE EXCEPTION 'Order is not accessible for the current user';
  END IF;

  IF v_order.status_id <> v_credit_pm_id THEN
    RAISE EXCEPTION
      'Only orders with CREDIT status can be settled via this function. Current status_id: %',
      v_order.status_id;
  END IF;

  -- Find the existing CREDIT settlement --------------------------------
  SELECT *
  INTO   v_old_settlement
  FROM   public.order_settlements os
  WHERE  os.order_id          = p_order_id
    AND  os.payment_method_id = v_credit_pm_id
  ORDER  BY os.created_at
  LIMIT  1;

  IF v_old_settlement.id IS NULL THEN
    RAISE EXCEPTION 'No CREDIT settlement record found for order %', p_order_id;
  END IF;

  v_original_date := v_order.original_date;
  v_payment_date  := COALESCE(v_order.outlet_day_open, CURRENT_DATE);

  -- Reverse the original CREDIT journal entry (if one exists) ---------
  SELECT fel.journal_entry_id
  INTO   v_old_je_id
  FROM   public.financial_event_logs fel
  WHERE  fel.reference_id   = v_old_settlement.id
    AND  fel.reference_type = 'order_settlement'
    AND  fel.source_module  = 'sales'
    AND  fel.status         = 'processed'
  LIMIT  1;

  IF v_old_je_id IS NOT NULL THEN
    -- Create reversal header
    INSERT INTO public.journal_entries (
      company_id,
      outlet_id,
      reference_type,
      reference_id,
      source_module,
      entry_date,
      memo,
      status,
      reversal_of_journal_entry_id,
      created_by
    )
    SELECT
      je.company_id,
      je.outlet_id,
      je.reference_type,
      je.reference_id,
      je.source_module,
      v_payment_date,
      format(
        'Reversal of credit bill for bill #%s (order %s). Credit issued on %s, payment received on %s.',
        v_order.bill_number,
        p_order_id,
        v_original_date,
        v_payment_date
      ),
      'posted'::public.journal_entry_status,
      v_old_je_id,
      v_user_id
    FROM public.journal_entries je
    WHERE je.id = v_old_je_id
    RETURNING id INTO v_reversal_je_id;

    -- Create reversal lines (swap debit ↔ credit)
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
    SELECT
      jel.company_id,
      v_reversal_je_id,
      jel.account_id,
      jel.outlet_id,
      jel.credit,   -- original credit becomes debit
      jel.debit,    -- original debit becomes credit
      format('Reversal: credit bill payment for bill #%s', v_order.bill_number),
      v_user_id
    FROM public.journal_entry_lines jel
    WHERE jel.journal_entry_id = v_old_je_id;

    -- Mark original entry as reversed
    UPDATE public.journal_entries
    SET
      reversed_by_journal_entry_id = v_reversal_je_id,
      reversed_at  = NOW(),
      reversed_by  = v_user_id,
      updated_at   = NOW()
    WHERE id = v_old_je_id;

    -- Mark old financial_event_log as superseded
    UPDATE public.financial_event_logs
    SET
      status     = 'ignored'::public.financial_event_status,
      updated_at = NOW()
    WHERE reference_id   = v_old_settlement.id
      AND reference_type = 'order_settlement'
      AND source_module  = 'sales';
  END IF;

  -- Delete the old CREDIT settlement -----------------------------------
  -- (removes this bill from the creditors view and the original day's
  --  payment-method summary)
  DELETE FROM public.order_settlements
  WHERE id = v_old_settlement.id;

  -- Build the auto-prefixed note --------------------------------------
  v_note_text := format(
    'Credit bill from %s, paid on %s',
    v_original_date,
    v_payment_date
  );
  IF p_notes IS NOT NULL AND TRIM(p_notes) <> '' THEN
    v_note_text := v_note_text || '. ' || TRIM(p_notes);
  END IF;

  -- Move the order to the payment day and update status ---------------
  -- (The inventory trigger's idempotency guard prevents double-deduction)
  UPDATE public.orders
  SET
    date       = v_payment_date,
    status_id  = p_payment_method_id,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- Insert the new settlement (accounting trigger fires here) ---------
  INSERT INTO public.order_settlements (
    order_id,
    amount,
    payment_method_id,
    notes,
    created_by
  )
  VALUES (
    p_order_id,
    v_old_settlement.amount,
    p_payment_method_id,
    v_note_text,
    v_user_id
  )
  RETURNING * INTO v_new_settlement;

  RETURN v_new_settlement;
END;
$$;

GRANT EXECUTE ON FUNCTION public.settle_credit_bill(UUID, INTEGER, TEXT) TO authenticated;
