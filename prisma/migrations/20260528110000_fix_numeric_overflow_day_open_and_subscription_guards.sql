-- Migration: Fix numeric overflow, day_open column bug, and subscription guard triggers
-- Fixes the following errors found in error_logs.json:
--
-- 1. "numeric field overflow" — post_order_settlement_accounting cast amounts to NUMERIC(12,6)
--    (max ~999,999) causing overflow on large orders. Changed to NUMERIC(18,6).
--
-- 2. "column outl.day_open does not exist" — settle_credit_bill referenced outl.day_open
--    but the real column is outl.day_opened_at.
--
-- 3. check_user_plan_limit referenced NEW.company_id but users table has no company_id.
--    Rewritten to resolve company via outlet_id.
--
-- 4. check_outlet_plan_limit referenced outlets.is_active which does not exist on the
--    outlets table. Removed the non-existent filter.
--
-- 5. "duplicate key violates unique constraint idx_clients_company_email_unique" — Added
--    upsert_client RPC so the app can avoid hard errors on re-booking existing guests.

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 1: post_order_settlement_accounting — widen NUMERIC(12,6) → NUMERIC(18,6)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_order_settlement_accounting(p_settlement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_settlement RECORD;
  v_payment_method RECORD;
  v_event_log_id UUID;
  v_existing_event RECORD;
  v_debit_account_id UUID;
  v_journal_entry_id UUID;
  v_credit_total NUMERIC(18, 2);
  v_rounding_difference NUMERIC(18, 2);
  v_adjustment_line_id UUID;
  v_pending_note TEXT;
BEGIN
  SELECT
    os.id,
    os.order_id,
    os.amount,
    os.payment_method_id,
    os.notes,
    os.created_by,
    os.created_at,
    o.id AS resolved_order_id,
    o.bill_number,
    o.date AS entry_date,
    o.mode,
    o.client_id,
    o.outlet_id,
    outl.company_id
  INTO v_settlement
  FROM public.order_settlements os
  JOIN public.orders o
    ON o.id = os.order_id
  JOIN public.outlets outl
    ON outl.id = o.outlet_id
  WHERE os.id = p_settlement_id
  LIMIT 1;

  IF v_settlement.id IS NULL THEN
    RAISE EXCEPTION 'Settlement % does not exist', p_settlement_id;
  END IF;

  SELECT pm.id, pm.name, pm.type
  INTO v_payment_method
  FROM public.payment_methods pm
  WHERE pm.id = v_settlement.payment_method_id
  LIMIT 1;

  IF v_payment_method.id IS NULL THEN
    RAISE EXCEPTION 'Settlement % has an unknown payment method', p_settlement_id;
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
    v_settlement.company_id,
    v_settlement.outlet_id,
    'sale_settlement_posted',
    'sales'::public.journal_source_module,
    'order_settlement',
    v_settlement.id,
    'sales:settlement:' || v_settlement.id::text,
    'pending'::public.financial_event_status,
    jsonb_build_object(
      'order_id', v_settlement.order_id,
      'settlement_id', v_settlement.id,
      'payment_method_id', v_settlement.payment_method_id,
      'payment_method_name', v_payment_method.name,
      'amount', v_settlement.amount
    ),
    v_settlement.created_by
  )
  ON CONFLICT (company_id, idempotency_key) DO NOTHING
  RETURNING id
  INTO v_event_log_id;

  IF v_event_log_id IS NULL THEN
    SELECT *
    INTO v_existing_event
    FROM public.financial_event_logs fel
    WHERE fel.company_id = v_settlement.company_id
      AND fel.idempotency_key = 'sales:settlement:' || v_settlement.id::text
    LIMIT 1;

    IF v_existing_event.status = 'processed'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'processed',
        'journal_entry_id', v_existing_event.journal_entry_id,
        'event_log_id', v_existing_event.id,
        'settlement_id', v_settlement.id,
        'order_id', v_settlement.order_id
      );
    END IF;

    IF v_existing_event.status = 'ignored'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'ignored',
        'journal_entry_id', v_existing_event.journal_entry_id,
        'event_log_id', v_existing_event.id,
        'settlement_id', v_settlement.id,
        'order_id', v_settlement.order_id
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

  IF v_payment_method.type = 'status'::public.payment_method_type
     AND v_payment_method.name IN ('OPEN', 'PENDING', 'CANCELLED') THEN
    v_pending_note := CASE v_payment_method.name
      WHEN 'PENDING' THEN 'Pending settlement does not create an accounting posting until payment intent is resolved.'
      ELSE 'Operational settlement type does not create an accounting posting.'
    END;

    UPDATE public.financial_event_logs
    SET
      status = 'ignored'::public.financial_event_status,
      error_message = v_pending_note,
      processed_at = NOW(),
      updated_at = NOW()
    WHERE id = v_event_log_id;

    RETURN jsonb_build_object(
      'status', 'ignored',
      'event_log_id', v_event_log_id,
      'settlement_id', v_settlement.id,
      'order_id', v_settlement.order_id
    );
  END IF;

  v_debit_account_id := public.resolve_sales_settlement_debit_account(
    v_settlement.company_id,
    v_settlement.payment_method_id
  );

  IF v_debit_account_id IS NULL THEN
    RAISE EXCEPTION 'No debit account could be resolved for payment method % (%).',
      v_payment_method.name,
      v_settlement.payment_method_id;
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
    v_settlement.company_id,
    v_settlement.outlet_id,
    'outlet'::public.journal_posting_scope,
    'order_settlement',
    v_settlement.id,
    'sales'::public.journal_source_module,
    v_settlement.entry_date,
    format(
      'Sales settlement posting for bill #%s (order %s, settlement %s, method %s).',
      v_settlement.bill_number,
      v_settlement.order_id,
      v_settlement.id,
      v_payment_method.name
    ),
    'draft'::public.journal_entry_status,
    v_settlement.created_by
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
    v_settlement.company_id,
    v_journal_entry_id,
    v_debit_account_id,
    v_settlement.outlet_id,
    ROUND(v_settlement.amount, 2),
    0,
    format('Settlement via %s', v_payment_method.name),
    v_settlement.created_by
  );

  -- FIXED: Changed ::numeric(12, 6) → ::numeric(18, 6) throughout this CTE block.
  -- NUMERIC(12,6) allows only up to 999,999.999999; large orders exceed this limit.
  WITH order_totals AS (
    SELECT
      COALESCE(
        SUM(oi.amount) FILTER (
          WHERE oi.status <> 'CANCELLED'::public.order_item_status
        ),
        0::numeric
      )::numeric(18, 6) AS items_total,
      COALESCE(
        (
          SELECT SUM(d.amount)
          FROM public.discounts d
          WHERE d.order_id = v_settlement.order_id
        ),
        0::numeric
      )::numeric(18, 6) AS discount_total
    FROM public.order_items oi
    WHERE oi.order_id = v_settlement.order_id
  ),
  item_financials AS (
    SELECT
      oi.id AS order_item_id,
      oi.amount::numeric(18, 6) AS gross_amount,
      CASE
        WHEN ot.items_total > 0 THEN
          (ot.discount_total * oi.amount::numeric(18, 6) / ot.items_total)
        ELSE 0::numeric
      END AS allocated_discount,
      mi.is_taxable,
      COALESCE(mi.tax_rate, 0)::numeric(18, 6) AS tax_rate,
      dep.name AS department_name,
      cat.name AS category_name,
      mi.name AS menu_item_name
    FROM public.order_items oi
    JOIN public.menu_items mi
      ON mi.id = oi.menu_item_id
    LEFT JOIN public.departments dep
      ON dep.id = mi.department_id
    LEFT JOIN public.menu_categories cat
      ON cat.id = mi.category_id
    CROSS JOIN order_totals ot
    WHERE oi.order_id = v_settlement.order_id
      AND oi.status <> 'CANCELLED'::public.order_item_status
  ),
  item_net_values AS (
    SELECT
      ifn.order_item_id,
      GREATEST(ifn.gross_amount - ifn.allocated_discount, 0::numeric) AS order_item_net_amount,
      ifn.is_taxable,
      ifn.tax_rate,
      ifn.department_name,
      ifn.category_name,
      ifn.menu_item_name
    FROM item_financials ifn
  ),
  settlement_share AS (
    SELECT
      CASE
        WHEN SUM(inv.order_item_net_amount) = 0 THEN 0::numeric
        ELSE ROUND(v_settlement.amount / SUM(inv.order_item_net_amount), 12)
      END AS settlement_ratio
    FROM item_net_values inv
  ),
  settlement_item_allocations AS (
    SELECT
      inv.order_item_id,
      public.resolve_sales_revenue_account(
        v_settlement.company_id,
        v_settlement.mode,
        inv.department_name,
        inv.category_name,
        inv.menu_item_name
      ) AS revenue_account_id,
      CASE
        WHEN COALESCE(inv.is_taxable, FALSE) = TRUE AND inv.tax_rate > 0
          THEN public.resolve_sales_tax_account(v_settlement.company_id, inv.tax_rate)
        ELSE NULL
      END AS tax_account_id,
      ROUND(inv.order_item_net_amount * ss.settlement_ratio, 6) AS settlement_net_amount,
      COALESCE(inv.is_taxable, FALSE) AS is_taxable,
      inv.tax_rate
    FROM item_net_values inv
    CROSS JOIN settlement_share ss
  ),
  revenue_allocations AS (
    SELECT
      sia.revenue_account_id AS account_id,
      SUM(
        CASE
          WHEN sia.is_taxable = TRUE AND sia.tax_rate > 0
            THEN sia.settlement_net_amount - (
              sia.settlement_net_amount * sia.tax_rate / (100 + sia.tax_rate)
            )
          ELSE sia.settlement_net_amount
        END
      ) AS credit_amount
    FROM settlement_item_allocations sia
    WHERE sia.revenue_account_id IS NOT NULL
    GROUP BY sia.revenue_account_id
  ),
  tax_allocations AS (
    SELECT
      sia.tax_account_id AS account_id,
      SUM(
        CASE
          WHEN sia.is_taxable = TRUE AND sia.tax_rate > 0
            THEN (sia.settlement_net_amount * sia.tax_rate / (100 + sia.tax_rate))
          ELSE 0::numeric
        END
      ) AS credit_amount
    FROM settlement_item_allocations sia
    WHERE sia.tax_account_id IS NOT NULL
      AND sia.is_taxable = TRUE
      AND sia.tax_rate > 0
    GROUP BY sia.tax_account_id
  )
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
    v_settlement.company_id,
    v_journal_entry_id,
    allocations.account_id,
    v_settlement.outlet_id,
    0,
    ROUND(allocations.credit_amount, 2),
    allocations.description,
    v_settlement.created_by
  FROM (
    SELECT
      ra.account_id,
      ra.credit_amount,
      'Sales revenue recognition'::text AS description
    FROM revenue_allocations ra

    UNION ALL

    SELECT
      ta.account_id,
      ta.credit_amount,
      'Sales tax recognition'::text AS description
    FROM tax_allocations ta
  ) AS allocations
  WHERE allocations.account_id IS NOT NULL
    AND ROUND(allocations.credit_amount, 2) > 0;

  SELECT COALESCE(SUM(jel.credit), 0)::numeric(18, 2)
  INTO v_credit_total
  FROM public.journal_entry_lines jel
  WHERE jel.journal_entry_id = v_journal_entry_id;

  v_rounding_difference := ROUND(v_settlement.amount - v_credit_total, 2);

  IF v_rounding_difference <> 0 THEN
    SELECT jel.id
    INTO v_adjustment_line_id
    FROM public.journal_entry_lines jel
    WHERE jel.journal_entry_id = v_journal_entry_id
      AND jel.credit > 0
    ORDER BY jel.created_at
    LIMIT 1;

    IF v_adjustment_line_id IS NULL THEN
      RAISE EXCEPTION 'Unable to adjust settlement posting rounding because no credit line was created.';
    END IF;

    UPDATE public.journal_entry_lines
    SET credit = ROUND(credit + v_rounding_difference, 2)
    WHERE id = v_adjustment_line_id;
  END IF;

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
    'settlement_id', v_settlement.id,
    'order_id', v_settlement.order_id
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

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 2: settle_credit_bill — outl.day_open → outl.day_opened_at
-- ─────────────────────────────────────────────────────────────────────────────
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
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT o.company_id
  INTO   v_user_company_id
  FROM   public.users u
  JOIN   public.outlets o ON o.id = u.outlet_id
  WHERE  u.id = v_user_id
  LIMIT  1;

  IF v_user_company_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve company for current user';
  END IF;

  SELECT id
  INTO   v_credit_pm_id
  FROM   public.payment_methods
  WHERE  name = 'CREDIT'
  LIMIT  1;

  IF v_credit_pm_id IS NULL THEN
    RAISE EXCEPTION 'CREDIT payment method is not configured';
  END IF;

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

  -- FIXED: outl.day_open → outl.day_opened_at (column was renamed in migration 20260124000000)
  SELECT
    ord.id,
    ord.status_id,
    ord.date           AS original_date,
    ord.outlet_id,
    ord.bill_number,
    outl.company_id,
    outl.day_opened_at AS outlet_day_open
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

  SELECT fel.journal_entry_id
  INTO   v_old_je_id
  FROM   public.financial_event_logs fel
  WHERE  fel.reference_id   = v_old_settlement.id
    AND  fel.reference_type = 'order_settlement'
    AND  fel.source_module  = 'sales'
    AND  fel.status         = 'processed'
  LIMIT  1;

  IF v_old_je_id IS NOT NULL THEN
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
      jel.credit,
      jel.debit,
      format('Reversal: credit bill payment for bill #%s', v_order.bill_number),
      v_user_id
    FROM public.journal_entry_lines jel
    WHERE jel.journal_entry_id = v_old_je_id;

    UPDATE public.journal_entries
    SET
      reversed_by_journal_entry_id = v_reversal_je_id,
      reversed_at  = NOW(),
      reversed_by  = v_user_id,
      updated_at   = NOW()
    WHERE id = v_old_je_id;

    UPDATE public.financial_event_logs
    SET
      status     = 'ignored'::public.financial_event_status,
      updated_at = NOW()
    WHERE reference_id   = v_old_settlement.id
      AND reference_type = 'order_settlement'
      AND source_module  = 'sales';
  END IF;

  DELETE FROM public.order_settlements
  WHERE id = v_old_settlement.id;

  v_note_text := format(
    'Credit bill from %s, paid on %s',
    v_original_date,
    v_payment_date
  );
  IF p_notes IS NOT NULL AND TRIM(p_notes) <> '' THEN
    v_note_text := v_note_text || '. ' || TRIM(p_notes);
  END IF;

  UPDATE public.orders
  SET
    date       = v_payment_date,
    status_id  = p_payment_method_id,
    updated_at = NOW()
  WHERE id = p_order_id;

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

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 3: check_user_plan_limit — users table has no company_id column.
-- Resolve company via outlet_id instead.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_user_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id         BIGINT;
  v_plan               subscription_package;
  v_max_users          INTEGER;
  v_max_per_outlet     INTEGER;
  v_total_users        INTEGER;
  v_outlet_users       INTEGER;
BEGIN
  -- users table has no company_id; resolve via outlet
  IF NEW.outlet_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT o.company_id
    INTO v_company_id
    FROM outlets o
   WHERE o.id = NEW.outlet_id
   LIMIT 1;

  IF v_company_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT br.package
    INTO v_plan
    FROM billing_records br
   WHERE br.company_id = v_company_id
   LIMIT 1;

  IF v_plan IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT prl.max_users, prl.max_users_per_outlet
    INTO v_max_users, v_max_per_outlet
    FROM plan_rate_limits prl
   WHERE prl.plan_id = v_plan;

  IF v_max_users IS NOT NULL THEN
    SELECT COUNT(*)
      INTO v_total_users
      FROM users u
      JOIN outlets o ON o.id = u.outlet_id
     WHERE o.company_id = v_company_id
       AND u.disabled_at IS NULL;

    IF v_total_users >= v_max_users THEN
      RAISE EXCEPTION 'user_limit_exceeded: Your % plan allows a maximum of % user(s). Upgrade your plan to add more users.',
        v_plan, v_max_users
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF v_max_per_outlet IS NOT NULL THEN
    SELECT COUNT(*)
      INTO v_outlet_users
      FROM users
     WHERE outlet_id = NEW.outlet_id
       AND disabled_at IS NULL;

    IF v_outlet_users >= v_max_per_outlet THEN
      RAISE EXCEPTION 'user_limit_exceeded: Your % plan allows a maximum of % users per outlet. Remove a user from this outlet or upgrade your plan.',
        v_plan, v_max_per_outlet
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 4: check_outlet_plan_limit — outlets table has no is_active column.
-- Count all outlets for the company instead.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_outlet_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_plan           subscription_package;
  v_max_outlets    INTEGER;
  v_active_outlets INTEGER;
BEGIN
  SELECT br.package
    INTO v_plan
    FROM billing_records br
   WHERE br.company_id = NEW.company_id
   LIMIT 1;

  IF v_plan IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT prl.max_outlets
    INTO v_max_outlets
    FROM plan_rate_limits prl
   WHERE prl.plan_id = v_plan;

  IF v_max_outlets IS NULL THEN
    RETURN NEW;
  END IF;

  -- outlets table has no is_active column; count all outlets for this company
  SELECT COUNT(*)
    INTO v_active_outlets
    FROM outlets
   WHERE company_id = NEW.company_id;

  IF v_active_outlets >= v_max_outlets THEN
    RAISE EXCEPTION 'outlet_limit_exceeded: Your % plan allows a maximum of % outlet(s). Upgrade your plan to add more outlets.',
      v_plan, v_max_outlets
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 5: upsert_client — handle duplicate email gracefully.
-- Call this instead of a direct INSERT when the client email may already exist.
-- Returns the existing record (with updated fields) or the newly created one.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.upsert_client(
  p_company_id           BIGINT,
  p_first_name           TEXT,
  p_last_name            TEXT,
  p_email                TEXT    DEFAULT NULL,
  p_contact              TEXT    DEFAULT NULL,
  p_address              TEXT    DEFAULT NULL,
  p_nationality          TEXT    DEFAULT NULL,
  p_date_of_birth        DATE    DEFAULT NULL,
  p_id_type              TEXT    DEFAULT NULL,
  p_id_number            TEXT    DEFAULT NULL,
  p_country_id           SMALLINT DEFAULT NULL,
  p_accommodation_notes  TEXT    DEFAULT NULL,
  p_tin_number           TEXT    DEFAULT NULL,
  p_menu_percentage_rate NUMERIC DEFAULT NULL
)
RETURNS public.clients
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id  UUID;
  v_client   public.clients;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_email IS NOT NULL THEN
    INSERT INTO public.clients (
      company_id, first_name, last_name, email, contact, address,
      nationality, date_of_birth, id_type, id_number, country_id,
      accommodation_notes, tin_number, menu_percentage_rate, created_by
    )
    VALUES (
      p_company_id, p_first_name, p_last_name, p_email, p_contact, p_address,
      p_nationality, p_date_of_birth, p_id_type, p_id_number, p_country_id,
      p_accommodation_notes, p_tin_number,
      COALESCE(p_menu_percentage_rate, 1),
      v_user_id
    )
    ON CONFLICT (company_id, lower(email)) WHERE (email IS NOT NULL)
    DO UPDATE SET
      first_name            = EXCLUDED.first_name,
      last_name             = EXCLUDED.last_name,
      contact               = COALESCE(EXCLUDED.contact,              clients.contact),
      address               = COALESCE(EXCLUDED.address,              clients.address),
      nationality           = COALESCE(EXCLUDED.nationality,          clients.nationality),
      date_of_birth         = COALESCE(EXCLUDED.date_of_birth,        clients.date_of_birth),
      id_type               = COALESCE(EXCLUDED.id_type,              clients.id_type),
      id_number             = COALESCE(EXCLUDED.id_number,            clients.id_number),
      country_id            = COALESCE(EXCLUDED.country_id,           clients.country_id),
      accommodation_notes   = COALESCE(EXCLUDED.accommodation_notes,  clients.accommodation_notes),
      tin_number            = COALESCE(EXCLUDED.tin_number,           clients.tin_number),
      updated_at            = NOW()
    RETURNING * INTO v_client;
  ELSE
    INSERT INTO public.clients (
      company_id, first_name, last_name, email, contact, address,
      nationality, date_of_birth, id_type, id_number, country_id,
      accommodation_notes, tin_number, menu_percentage_rate, created_by
    )
    VALUES (
      p_company_id, p_first_name, p_last_name, NULL, p_contact, p_address,
      p_nationality, p_date_of_birth, p_id_type, p_id_number, p_country_id,
      p_accommodation_notes, p_tin_number,
      COALESCE(p_menu_percentage_rate, 1),
      v_user_id
    )
    RETURNING * INTO v_client;
  END IF;

  RETURN v_client;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_client(
  BIGINT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, SMALLINT, TEXT, TEXT, NUMERIC
) TO authenticated;
