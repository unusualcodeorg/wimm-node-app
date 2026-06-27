-- ============================================================
-- Migration: Add POS settlement accounting trigger
-- ============================================================

-- 1. Resolve company account by chart code
CREATE OR REPLACE FUNCTION public.get_company_account_id_by_code(
  p_company_id BIGINT,
  p_code TEXT
)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.id
  FROM public.accounts a
  WHERE a.company_id = p_company_id
    AND a.code = p_code
    AND a.is_active = TRUE
  ORDER BY a.created_at
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_account_id_by_code(BIGINT, TEXT) TO authenticated;

-- 2. Resolve debit-side settlement account
CREATE OR REPLACE FUNCTION public.resolve_sales_settlement_debit_account(
  p_company_id BIGINT,
  p_payment_method_id INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id UUID;
  v_method_type public.payment_method_type;
BEGIN
  SELECT pmam.account_id
  INTO v_account_id
  FROM public.payment_method_account_mappings pmam
  WHERE pmam.company_id = p_company_id
    AND pmam.payment_method_id = p_payment_method_id
  LIMIT 1;

  IF v_account_id IS NOT NULL THEN
    RETURN v_account_id;
  END IF;

  SELECT pm.type
  INTO v_method_type
  FROM public.payment_methods pm
  WHERE pm.id = p_payment_method_id
  LIMIT 1;

  IF v_method_type IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN CASE v_method_type
    WHEN 'cash'::public.payment_method_type THEN public.get_company_account_id_by_code(p_company_id, '1000')
    WHEN 'mobile_money'::public.payment_method_type THEN public.get_company_account_id_by_code(p_company_id, '1020')
    WHEN 'credit'::public.payment_method_type THEN public.get_company_account_id_by_code(p_company_id, '1100')
    WHEN 'non_chargeable'::public.payment_method_type THEN public.get_company_account_id_by_code(p_company_id, '6600')
    WHEN 'card'::public.payment_method_type THEN public.get_company_account_id_by_code(p_company_id, '1010')
    WHEN 'bank'::public.payment_method_type THEN public.get_company_account_id_by_code(p_company_id, '1010')
    WHEN 'check'::public.payment_method_type THEN public.get_company_account_id_by_code(p_company_id, '1010')
    ELSE NULL
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_sales_settlement_debit_account(BIGINT, INTEGER) TO authenticated;

-- 3. Resolve tax output account
CREATE OR REPLACE FUNCTION public.resolve_sales_tax_account(
  p_company_id BIGINT,
  p_tax_rate NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id UUID;
BEGIN
  SELECT tr.output_account_id
  INTO v_account_id
  FROM public.tax_rates tr
  WHERE tr.company_id = p_company_id
    AND tr.status = 'active'::public.tax_rate_status
    AND tr.application IN ('sales'::public.tax_application, 'both'::public.tax_application)
    AND ABS(tr.rate - COALESCE(p_tax_rate, 0)) < 0.0001
    AND tr.output_account_id IS NOT NULL
  ORDER BY tr.created_at
  LIMIT 1;

  IF v_account_id IS NOT NULL THEN
    RETURN v_account_id;
  END IF;

  RETURN public.get_company_account_id_by_code(p_company_id, '2040');
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_sales_tax_account(BIGINT, NUMERIC) TO authenticated;

-- 4. Resolve revenue account by practical sales rules
CREATE OR REPLACE FUNCTION public.resolve_sales_revenue_account(
  p_company_id BIGINT,
  p_order_mode public.order_mode,
  p_department_name TEXT,
  p_category_name TEXT,
  p_menu_item_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_classifier TEXT;
BEGIN
  IF p_order_mode = 'TAKEAWAY'::public.order_mode THEN
    RETURN public.get_company_account_id_by_code(p_company_id, '4210');
  END IF;

  v_classifier := lower(
    COALESCE(p_department_name, '') || ' ' ||
    COALESCE(p_category_name, '') || ' ' ||
    COALESCE(p_menu_item_name, '')
  );

  IF v_classifier ~ '(alcohol|beer|wine|whisky|whiskey|vodka|gin|rum|tequila|cocktail|liquor|spirit|champagne)' THEN
    RETURN public.get_company_account_id_by_code(p_company_id, '4230');
  END IF;

  IF v_classifier ~ '(beverage|drink|juice|soda|water|coffee|tea|bar|smoothie|shake)' THEN
    RETURN public.get_company_account_id_by_code(p_company_id, '4220');
  END IF;

  RETURN public.get_company_account_id_by_code(p_company_id, '4200');
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_sales_revenue_account(BIGINT, public.order_mode, TEXT, TEXT, TEXT) TO authenticated;

-- 5. Post accounting for one settlement row
CREATE OR REPLACE FUNCTION public.post_order_settlement_accounting(
  p_settlement_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settlement RECORD;
  v_payment_method RECORD;
  v_event_log_id UUID;
  v_existing_event RECORD;
  v_debit_account_id UUID;
  v_journal_entry_id UUID;
  v_credit_total NUMERIC(12, 2);
  v_rounding_difference NUMERIC(12, 2);
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

  WITH order_totals AS (
    SELECT
      COALESCE(
        SUM(oi.amount) FILTER (
          WHERE oi.status <> 'CANCELLED'::public.order_item_status
        ),
        0::numeric
      )::numeric(12, 6) AS items_total,
      COALESCE(
        (
          SELECT SUM(d.amount)
          FROM public.discounts d
          WHERE d.order_id = v_settlement.order_id
        ),
        0::numeric
      )::numeric(12, 6) AS discount_total
    FROM public.order_items oi
    WHERE oi.order_id = v_settlement.order_id
  ),
  item_financials AS (
    SELECT
      oi.id AS order_item_id,
      oi.amount::numeric(12, 6) AS gross_amount,
      CASE
        WHEN ot.items_total > 0 THEN
          (ot.discount_total * oi.amount::numeric(12, 6) / ot.items_total)
        ELSE 0::numeric
      END AS allocated_discount,
      mi.is_taxable,
      COALESCE(mi.tax_rate, 0)::numeric(12, 6) AS tax_rate,
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

  SELECT COALESCE(SUM(jel.credit), 0)::numeric(12, 2)
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

GRANT EXECUTE ON FUNCTION public.post_order_settlement_accounting(UUID) TO authenticated;

-- 6. Trigger settlement posting automatically
CREATE OR REPLACE FUNCTION public.handle_order_settlement_accounting_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.post_order_settlement_accounting(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS order_settlement_accounting_after_insert
  ON public.order_settlements;

CREATE TRIGGER order_settlement_accounting_after_insert
  AFTER INSERT ON public.order_settlements
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_order_settlement_accounting_trigger();
