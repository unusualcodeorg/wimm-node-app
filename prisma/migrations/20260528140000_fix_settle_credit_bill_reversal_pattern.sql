-- Migration: Fix settle_credit_bill reversal pattern to satisfy all triggers
-- Created: 2026-05-28
-- Description:
--   Two BEFORE INSERT/UPDATE triggers on journal_entries create a deadlock:
--
--   • enforce_journal_reversal_metadata (20260518170000):
--       if reversal_of_journal_entry_id IS NOT NULL then status MUST be 'posted'.
--   • enforce_posted_journal_entry_balance (20260518130000):
--       if status = 'posted' then at least one line must already exist.
--
--   Because lines cannot exist before the header, you cannot satisfy both on INSERT.
--   The working solution (used by reverse_journal_entry in 20260518180000) is to:
--
--     Step 1  INSERT header  status='draft', reversal_of_journal_entry_id=NULL
--     Step 2  INSERT lines   (debit ↔ credit swapped)
--     Step 3  UPDATE header  status='posted' + reversal_of_journal_entry_id=<orig>
--                 → all three triggers now pass simultaneously
--     Step 4  UPDATE original status='reversed' + reversed_by_journal_entry_id=<rev>
--
--   Previous migrations incorrectly set reversal_of_journal_entry_id on the INSERT
--   (20260528120000) or set it only on the header UPDATE without also transitioning
--   the original entry to 'reversed' (20260528130000).

CREATE OR REPLACE FUNCTION public.settle_credit_bill(
  p_order_id          UUID,
  p_payment_method_id INTEGER,
  p_notes             TEXT DEFAULT NULL
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
  -- ── Auth ──────────────────────────────────────────────────────────────────
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- ── Caller company ────────────────────────────────────────────────────────
  SELECT o.company_id
  INTO   v_user_company_id
  FROM   public.users   u
  JOIN   public.outlets o ON o.id = u.outlet_id
  WHERE  u.id = v_user_id
  LIMIT  1;

  IF v_user_company_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve company for current user';
  END IF;

  -- ── CREDIT payment method id ──────────────────────────────────────────────
  SELECT id
  INTO   v_credit_pm_id
  FROM   public.payment_methods
  WHERE  name = 'CREDIT'
  LIMIT  1;

  IF v_credit_pm_id IS NULL THEN
    RAISE EXCEPTION 'CREDIT payment method is not configured';
  END IF;

  -- ── Validate target payment method ────────────────────────────────────────
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

  -- ── Lock and fetch the order ──────────────────────────────────────────────
  SELECT
    ord.id,
    ord.status_id,
    ord.date            AS original_date,
    ord.outlet_id,
    ord.bill_number,
    outl.company_id,
    outl.day_opened_at  AS outlet_day_open
  INTO v_order
  FROM   public.orders  ord
  JOIN   public.outlets outl ON outl.id = ord.outlet_id
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

  -- ── Find the existing CREDIT settlement ───────────────────────────────────
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

  -- ── Reverse the original CREDIT journal entry (if one exists) ─────────────
  SELECT fel.journal_entry_id
  INTO   v_old_je_id
  FROM   public.financial_event_logs fel
  WHERE  fel.reference_id   = v_old_settlement.id
    AND  fel.reference_type = 'order_settlement'
    AND  fel.source_module  = 'sales'
    AND  fel.status         = 'processed'
  LIMIT  1;

  IF v_old_je_id IS NOT NULL THEN
    -- ── Step 1: Insert reversal header as 'draft' WITHOUT reversal_of_journal_entry_id.
    --
    --   Setting reversal_of_journal_entry_id on INSERT would trigger
    --   enforce_journal_reversal_metadata which requires status='posted'.
    --   But posting requires lines to exist first (enforce_posted_journal_entry_balance).
    --   We defer the link to Step 3 (the UPDATE), exactly as reverse_journal_entry() does.
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
    SELECT
      je.company_id,
      je.outlet_id,
      je.posting_scope,
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
      'draft'::public.journal_entry_status,
      v_user_id
    FROM public.journal_entries je
    WHERE je.id = v_old_je_id
    RETURNING id INTO v_reversal_je_id;

    -- ── Step 2: Insert reversal lines (swap debit ↔ credit).
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

    -- ── Step 3: Post the reversal AND link it to the original in one UPDATE.
    --
    --   All three triggers now pass simultaneously:
    --     enforce_journal_entry_lifecycle:       draft → posted is a valid transition.
    --     enforce_journal_reversal_metadata:     reversal_of_journal_entry_id IS NOT NULL
    --                                            and status = 'posted' → OK.
    --     enforce_posted_journal_entry_balance:  status = 'posted' and lines exist → OK.
    UPDATE public.journal_entries
    SET
      status                       = 'posted'::public.journal_entry_status,
      reversal_of_journal_entry_id = v_old_je_id,
      updated_at                   = NOW()
    WHERE id = v_reversal_je_id;

    -- ── Step 4: Mark the original entry as reversed.
    --
    --   enforce_journal_entry_lifecycle:     posted → reversed is a valid transition.
    --   enforce_journal_reversal_metadata:   status = 'reversed' requires
    --                                        reversed_by_journal_entry_id IS NOT NULL → set here.
    UPDATE public.journal_entries
    SET
      status                       = 'reversed'::public.journal_entry_status,
      reversed_by_journal_entry_id = v_reversal_je_id,
      reversed_at                  = NOW(),
      reversed_by                  = v_user_id,
      updated_at                   = NOW()
    WHERE id = v_old_je_id;

    -- ── Step 5: Mark old financial_event_log as superseded.
    UPDATE public.financial_event_logs
    SET
      status     = 'ignored'::public.financial_event_status,
      updated_at = NOW()
    WHERE reference_id   = v_old_settlement.id
      AND reference_type = 'order_settlement'
      AND source_module  = 'sales';
  END IF;

  -- ── Delete the old CREDIT settlement ──────────────────────────────────────
  DELETE FROM public.order_settlements
  WHERE id = v_old_settlement.id;

  -- ── Build the auto-prefixed note ──────────────────────────────────────────
  v_note_text := format(
    'Credit bill from %s, paid on %s',
    v_original_date,
    v_payment_date
  );
  IF p_notes IS NOT NULL AND TRIM(p_notes) <> '' THEN
    v_note_text := v_note_text || '. ' || TRIM(p_notes);
  END IF;

  -- ── Move the order to the payment day and update status ───────────────────
  UPDATE public.orders
  SET
    date       = v_payment_date,
    status_id  = p_payment_method_id,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- ── Insert the new settlement (accounting trigger fires here) ─────────────
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
