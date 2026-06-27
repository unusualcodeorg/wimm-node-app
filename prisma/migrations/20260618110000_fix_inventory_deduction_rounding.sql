-- Fix: inventory_stock_balances_value_matches_components constraint violation
-- Root cause: deduct_order_inventory() subtracted a pre-rounded v_consumption_value
-- from total_value, causing rounding drift vs. ROUND(quantity_on_hand * average_cost, 2).
-- Fix: compute v_new_qty and v_new_total_value as variables, then UPDATE with both,
-- matching the pattern used correctly by post_supplier_invoice().

CREATE OR REPLACE FUNCTION public.deduct_order_inventory(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id           BIGINT;
  v_outlet_id            UUID;
  v_stock_location_id    UUID;
  v_item                 RECORD;
  v_recipe               RECORD;
  v_ingredient           RECORD;
  v_balance              public.inventory_stock_balances;
  v_consumption_qty      NUMERIC(14, 4);
  v_unit_cost            NUMERIC(14, 4);
  v_consumption_value    NUMERIC(14, 2);
  v_new_qty              NUMERIC(14, 4);
  v_new_total_value      NUMERIC(14, 2);
  v_total_cogs           NUMERIC(14, 2) := 0;
  v_cogs_account_id      UUID;
  v_inventory_account_id UUID;
  v_journal_entry_id     UUID;
  v_user_id              UUID;
  v_items_processed      INTEGER := 0;
BEGIN
  v_user_id := auth.uid();

  SELECT outl.company_id, o.outlet_id
  INTO v_company_id, v_outlet_id
  FROM public.orders o
  JOIN public.outlets outl ON outl.id = o.outlet_id
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  -- Idempotency guard
  IF EXISTS (
    SELECT 1 FROM public.financial_event_logs
    WHERE source_module  = 'inventory'
      AND event_type     = 'ORDER_INVENTORY_DEDUCTED'
      AND reference_type = 'order'
      AND reference_id   = p_order_id
      AND status         = 'processed'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Inventory already deducted for this order');
  END IF;

  -- Resolve primary stock location for the outlet
  SELECT id INTO v_stock_location_id
  FROM public.inventory_stock_locations
  WHERE outlet_id = v_outlet_id AND is_active = true
  ORDER BY created_at
  LIMIT 1;

  IF v_stock_location_id IS NULL THEN
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id, idempotency_key, status, error_message
    ) VALUES (
      v_company_id, v_outlet_id, 'inventory', 'ORDER_INVENTORY_DEDUCTED',
      'order', p_order_id,
      format('order_inventory_%s', p_order_id),
      'failed', 'No active stock location found for outlet'
    );
    RETURN jsonb_build_object('success', false, 'error', 'No active stock location found for this outlet');
  END IF;

  BEGIN
    -- Process each CONFIRMED order item
    FOR v_item IN
      SELECT oi.menu_item_id, oi.quantity
      FROM public.order_items oi
      WHERE oi.order_id = p_order_id
        AND oi.status = 'CONFIRMED'::public.order_item_status
    LOOP
      -- Resolve recipe: outlet-specific first, then company-wide fallback
      SELECT r.id, r.yield_quantity
      INTO v_recipe
      FROM public.inventory_recipes r
      WHERE r.company_id   = v_company_id
        AND r.menu_item_id = v_item.menu_item_id
        AND r.is_active    = true
        AND (r.outlet_id = v_outlet_id OR r.outlet_id IS NULL)
      ORDER BY (r.outlet_id IS NULL)  -- false (outlet-specific) sorts before true (company-wide)
      LIMIT 1;

      IF NOT FOUND THEN
        CONTINUE;  -- no active recipe — skip this item
      END IF;

      -- Deduct each ingredient
      FOR v_ingredient IN
        SELECT ri.inventory_item_id, ri.quantity AS ingredient_qty
        FROM public.inventory_recipe_items ri
        WHERE ri.recipe_id = v_recipe.id
      LOOP
        v_consumption_qty := ROUND(
          (v_item.quantity / GREATEST(v_recipe.yield_quantity, 0.0001)) * v_ingredient.ingredient_qty,
          4
        );

        -- Lock and read the current balance for weighted-average cost
        SELECT * INTO v_balance
        FROM public.inventory_stock_balances
        WHERE company_id        = v_company_id
          AND outlet_id         = v_outlet_id
          AND stock_location_id = v_stock_location_id
          AND inventory_item_id = v_ingredient.inventory_item_id
        FOR UPDATE;

        v_unit_cost         := COALESCE(v_balance.average_cost, 0);
        v_consumption_value := ROUND(v_consumption_qty * v_unit_cost, 2);
        v_total_cogs        := v_total_cogs + v_consumption_value;

        -- Stock movement (sale_consumption; reference_id is TEXT in this table)
        INSERT INTO public.inventory_stock_movements (
          company_id, outlet_id, stock_location_id, inventory_item_id,
          movement_type, reference_type, reference_id,
          quantity, unit_cost, total_cost, movement_date, created_by
        ) VALUES (
          v_company_id, v_outlet_id, v_stock_location_id, v_ingredient.inventory_item_id,
          'sale_consumption', 'order', p_order_id::TEXT,
          v_consumption_qty, v_unit_cost, v_consumption_value,
          NOW(), v_user_id
        );

        -- Update or create stock balance
        IF FOUND THEN
          -- Compute new qty and total_value together so total_value = ROUND(new_qty * avg_cost, 2)
          -- and the inventory_stock_balances_value_matches_components constraint is satisfied.
          v_new_qty         := v_balance.quantity_on_hand - v_consumption_qty;
          v_new_total_value := GREATEST(ROUND((v_new_qty * v_unit_cost)::numeric, 2), 0);

          UPDATE public.inventory_stock_balances
          SET
            quantity_on_hand = v_new_qty,
            total_value      = v_new_total_value,
            updated_at       = NOW()
          WHERE id = v_balance.id;
        ELSE
          INSERT INTO public.inventory_stock_balances (
            company_id, outlet_id, stock_location_id, inventory_item_id,
            quantity_on_hand, average_cost, total_value, created_by
          ) VALUES (
            v_company_id, v_outlet_id, v_stock_location_id,
            v_ingredient.inventory_item_id,
            -v_consumption_qty, 0, 0, v_user_id
          );
        END IF;

        v_items_processed := v_items_processed + 1;
      END LOOP;
    END LOOP;

    -- Post COGS journal entry: Dr Food Cost (5000) / Cr Inventory Asset (1200)
    IF v_total_cogs > 0 THEN
      SELECT id INTO v_cogs_account_id
      FROM public.accounts
      WHERE company_id = v_company_id AND code = '5000' AND is_active = true
      LIMIT 1;

      SELECT id INTO v_inventory_account_id
      FROM public.accounts
      WHERE company_id = v_company_id AND code = '1200' AND is_active = true
      LIMIT 1;

      IF v_cogs_account_id IS NOT NULL AND v_inventory_account_id IS NOT NULL THEN
        INSERT INTO public.journal_entries (
          company_id, outlet_id, posting_scope,
          reference_type, reference_id,
          source_module, entry_date, memo, status, created_by
        ) VALUES (
          v_company_id, v_outlet_id,
          'outlet'::public.journal_posting_scope,
          'order', p_order_id,
          'inventory'::public.journal_source_module,
          CURRENT_DATE,
          format('COGS — inventory consumed by order %s', p_order_id),
          'draft'::public.journal_entry_status,
          v_user_id
        )
        RETURNING id INTO v_journal_entry_id;

        INSERT INTO public.journal_entry_lines (
          company_id, journal_entry_id, account_id, outlet_id,
          debit, credit, description, created_by
        ) VALUES (
          v_company_id, v_journal_entry_id, v_cogs_account_id, v_outlet_id,
          ROUND(v_total_cogs, 2), 0,
          'Cost of goods sold — recipe consumption',
          v_user_id
        );

        INSERT INTO public.journal_entry_lines (
          company_id, journal_entry_id, account_id, outlet_id,
          debit, credit, description, created_by
        ) VALUES (
          v_company_id, v_journal_entry_id, v_inventory_account_id, v_outlet_id,
          0, ROUND(v_total_cogs, 2),
          'Inventory asset consumed by sale',
          v_user_id
        );

        UPDATE public.journal_entries
        SET status = 'posted'::public.journal_entry_status
        WHERE id = v_journal_entry_id;
      END IF;
    END IF;

    -- Idempotency log — success
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id,
      idempotency_key,
      journal_entry_id, status, payload
    ) VALUES (
      v_company_id, v_outlet_id,
      'inventory', 'ORDER_INVENTORY_DEDUCTED',
      'order', p_order_id,
      format('order_inventory_%s', p_order_id),
      v_journal_entry_id,
      'processed',
      jsonb_build_object(
        'order_id',          p_order_id,
        'outlet_id',         v_outlet_id,
        'stock_location_id', v_stock_location_id,
        'items_processed',   v_items_processed,
        'total_cogs',        v_total_cogs,
        'journal_entry_id',  v_journal_entry_id
      )
    );

    RETURN jsonb_build_object(
      'success',           true,
      'order_id',          p_order_id,
      'items_processed',   v_items_processed,
      'total_cogs',        v_total_cogs,
      'journal_entry_id',  v_journal_entry_id
    );

  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.financial_event_logs (
      company_id, outlet_id, source_module, event_type,
      reference_type, reference_id,
      idempotency_key, status, error_message
    ) VALUES (
      v_company_id, v_outlet_id,
      'inventory', 'ORDER_INVENTORY_DEDUCTED',
      'order', p_order_id,
      format('order_inventory_err_%s', gen_random_uuid()),
      'failed', SQLERRM
    );

    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deduct_order_inventory(UUID) TO authenticated;
