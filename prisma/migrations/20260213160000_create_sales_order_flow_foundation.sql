-- Migration: Create sales order flow foundation
-- Created: 2026-02-13
-- Description:
--   Adds the core sales schema and database helpers for creating/fetching
--   running orders from the Sales page:
--   - payment_methods, clients, orders, order_items, order_settlements
--   - sales enums and indexes
--   - orders_view and outlet_tables_view running-order fields
--   - get_or_create_table_order(table_id, mode) RPC

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Enums
-- ============================================================
DO $$
BEGIN
  CREATE TYPE public.order_mode AS ENUM ('DINE', 'TAKEAWAY', 'CASH');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE public.order_item_status AS ENUM ('PENDING', 'CONFIRMED', 'CANCELLED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- 2. Payment methods (global, not tied to outlet/company)
-- ============================================================
CREATE TABLE public.payment_methods (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.payment_methods (id, name)
VALUES
  (1, 'CASH'),
  (2, 'CARD'),
  (3, 'MOBILE MONEY'),
  (4, 'CHECK'),
  (5, 'EFT'),
  (6, 'CANCELLED'),
  (7, 'NC'),
  (8, 'PENDING'),
  (9, 'OPEN')
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name;

-- ============================================================
-- 3. Clients
-- ============================================================
CREATE TABLE public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT,
  contact TEXT,
  address TEXT,
  tin_number TEXT,
  menu_percentage_rate NUMERIC(8, 4) NOT NULL DEFAULT 1 CHECK (menu_percentage_rate > 0),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_clients_company_id ON public.clients(company_id);
CREATE INDEX idx_clients_contact ON public.clients(contact);
CREATE UNIQUE INDEX idx_clients_company_email_unique
  ON public.clients(company_id, lower(email))
  WHERE email IS NOT NULL;

CREATE TRIGGER update_clients_updated_at
  BEFORE UPDATE ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 4. Supporting counter table for outlet-scoped bill numbers
-- ============================================================
CREATE TABLE public.outlet_order_counters (
  outlet_id UUID PRIMARY KEY REFERENCES public.outlets(id) ON DELETE CASCADE,
  last_bill_number INTEGER NOT NULL DEFAULT 0 CHECK (last_bill_number >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER update_outlet_order_counters_updated_at
  BEFORE UPDATE ON public.outlet_order_counters
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 5. Orders
-- ============================================================
CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_number INTEGER NOT NULL CHECK (bill_number > 0),
  table_id INTEGER NOT NULL REFERENCES public.outlet_tables(id) ON DELETE RESTRICT,
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  status_id INTEGER NOT NULL DEFAULT 9 REFERENCES public.payment_methods(id),
  waiter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  mode public.order_mode NOT NULL,
  discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT orders_outlet_bill_unique UNIQUE (outlet_id, bill_number)
);

CREATE INDEX idx_orders_table_id ON public.orders(table_id);
CREATE INDEX idx_orders_outlet_id ON public.orders(outlet_id);
CREATE INDEX idx_orders_status_id ON public.orders(status_id);
CREATE INDEX idx_orders_waiter_id ON public.orders(waiter_id);
CREATE INDEX idx_orders_date ON public.orders(date);
CREATE INDEX idx_orders_table_status ON public.orders(table_id, status_id);

-- At most one OPEN order per table
CREATE UNIQUE INDEX idx_orders_single_open_per_table
  ON public.orders(table_id)
  WHERE status_id = 9;

CREATE TRIGGER update_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Keep outlet/date aligned to selected table's outlet and validate client-company consistency.
CREATE OR REPLACE FUNCTION public.set_order_defaults_and_validate()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_table_outlet_id UUID;
  v_outlet_day DATE;
  v_order_company_id BIGINT;
  v_client_company_id BIGINT;
BEGIN
  SELECT os.outlet_id
  INTO v_table_outlet_id
  FROM public.outlet_tables ot
  JOIN public.outlet_sections os ON os.id = ot.section_id
  WHERE ot.id = NEW.table_id
  LIMIT 1;

  IF v_table_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Invalid table_id % for order', NEW.table_id;
  END IF;

  -- Enforce outlet from the selected table to prevent mismatches.
  NEW.outlet_id := v_table_outlet_id;

  IF NEW.date IS NULL THEN
    SELECT COALESCE(o.day_open, CURRENT_DATE)
    INTO v_outlet_day
    FROM public.outlets o
    WHERE o.id = v_table_outlet_id;

    NEW.date := COALESCE(v_outlet_day, CURRENT_DATE);
  END IF;

  IF NEW.waiter_id IS NULL THEN
    NEW.waiter_id := auth.uid();
  END IF;

  IF NEW.created_by IS NULL THEN
    NEW.created_by := auth.uid();
  END IF;

  IF NEW.client_id IS NOT NULL THEN
    SELECT o.company_id
    INTO v_order_company_id
    FROM public.outlets o
    WHERE o.id = v_table_outlet_id;

    SELECT c.company_id
    INTO v_client_company_id
    FROM public.clients c
    WHERE c.id = NEW.client_id;

    IF v_client_company_id IS NULL THEN
      RAISE EXCEPTION 'Invalid client_id % for order', NEW.client_id;
    END IF;

    IF v_order_company_id <> v_client_company_id THEN
      RAISE EXCEPTION 'Selected client does not belong to the order company';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER set_order_defaults_and_validate_trigger
  BEFORE INSERT OR UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.set_order_defaults_and_validate();

-- ============================================================
-- 6. Order items
-- ============================================================
CREATE TABLE public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE RESTRICT,
  quantity NUMERIC(10, 2) NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
  amount NUMERIC(12, 2) GENERATED ALWAYS AS ((quantity * unit_price)::NUMERIC(12, 2)) STORED,
  notes TEXT,
  status public.order_item_status NOT NULL DEFAULT 'PENDING',
  kot_id INTEGER NOT NULL DEFAULT 0 CHECK (kot_id >= 0),
  added_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX idx_order_items_menu_item_id ON public.order_items(menu_item_id);
CREATE INDEX idx_order_items_status ON public.order_items(status);
CREATE INDEX idx_order_items_order_kot ON public.order_items(order_id, kot_id);

CREATE TRIGGER update_order_items_updated_at
  BEFORE UPDATE ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 7. Order settlements
-- ============================================================
CREATE TABLE public.order_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  payment_method_id INTEGER NOT NULL REFERENCES public.payment_methods(id) ON DELETE RESTRICT,
  notes TEXT,
  created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_settlements_order_id ON public.order_settlements(order_id);
CREATE INDEX idx_order_settlements_payment_method_id ON public.order_settlements(payment_method_id);

-- ============================================================
-- 8. Views
-- ============================================================
CREATE OR REPLACE VIEW public.orders_view AS
WITH order_totals AS (
  SELECT
    oi.order_id,
    COALESCE(
      SUM(oi.amount) FILTER (WHERE oi.status <> 'CANCELLED'::public.order_item_status),
      0::NUMERIC
    )::NUMERIC(12, 2) AS total_amount,
    COUNT(*) FILTER (WHERE oi.status <> 'CANCELLED'::public.order_item_status) AS item_count,
    COUNT(*) FILTER (WHERE oi.status = 'PENDING'::public.order_item_status) AS pending_item_count
  FROM public.order_items oi
  GROUP BY oi.order_id
)
SELECT
  o.id AS order_id,
  o.bill_number,
  o.table_id,
  ot.name AS table_name,
  os.id AS section_id,
  os.name AS section_name,
  o.outlet_id,
  outl.name AS outlet_name,
  outl.company_id,
  o.date,
  o.status_id,
  pm.name AS status_name,
  o.waiter_id,
  TRIM(CONCAT(COALESCE(w.first_name, ''), ' ', COALESCE(w.last_name, ''))) AS waiter_name,
  o.client_id,
  CASE
    WHEN c.id IS NULL THEN NULL
    ELSE TRIM(CONCAT(COALESCE(c.first_name, ''), ' ', COALESCE(c.last_name, '')))
  END AS client_name,
  o.mode,
  o.discount_amount,
  COALESCE(otals.total_amount, 0::NUMERIC)::NUMERIC(12, 2) AS total_amount,
  GREATEST(
    COALESCE(otals.total_amount, 0::NUMERIC) - o.discount_amount,
    0::NUMERIC
  )::NUMERIC(12, 2) AS net_amount,
  COALESCE(otals.item_count, 0) AS item_count,
  COALESCE(otals.pending_item_count, 0) AS pending_item_count,
  (COALESCE(otals.pending_item_count, 0) > 0) AS has_pending_items,
  o.created_by,
  o.created_at,
  o.updated_at
FROM public.orders o
JOIN public.outlet_tables ot ON ot.id = o.table_id
JOIN public.outlet_sections os ON os.id = ot.section_id
JOIN public.outlets outl ON outl.id = o.outlet_id
JOIN public.payment_methods pm ON pm.id = o.status_id
LEFT JOIN public.users w ON w.id = o.waiter_id
LEFT JOIN public.clients c ON c.id = o.client_id
LEFT JOIN order_totals otals ON otals.order_id = o.id;

ALTER VIEW public.orders_view SET (security_invoker = on);

-- Include running order information in existing table view used by the Dining panel.
CREATE OR REPLACE VIEW public.outlet_tables_view AS
SELECT
  ot.id,
  ot.name,
  ot.section_id,
  ot.is_hidden,
  ot.created_at,
  ot.updated_at,
  os.name AS section_name,
  os.outlet_id,
  o.name AS outlet_name,
  o.company_id,
  ro.bill_number AS running_order_bill_number,
  (ro.bill_number IS NOT NULL) AS has_running_order
FROM
  public.outlet_tables ot
  LEFT JOIN public.outlet_sections os ON ot.section_id = os.id
  LEFT JOIN public.outlets o ON os.outlet_id = o.id
  LEFT JOIN LATERAL (
    SELECT ord.bill_number
    FROM public.orders ord
    WHERE ord.table_id = ot.id
      AND ord.status_id = 9
    ORDER BY ord.created_at DESC
    LIMIT 1
  ) ro ON true;

ALTER VIEW public.outlet_tables_view SET (security_invoker = on);

-- ============================================================
-- 9. RPC: get or create running order for a selected table
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_or_create_table_order(
  p_table_id INTEGER,
  p_mode public.order_mode DEFAULT 'DINE'
)
RETURNS SETOF public.orders_view
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_outlet_id UUID;
  v_open_status_id INTEGER;
  v_order_id UUID;
  v_outlet_day DATE;
  v_next_bill_number INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT o.company_id
  INTO v_user_company_id
  FROM public.users u
  JOIN public.outlets o ON o.id = u.outlet_id
  WHERE u.id = v_user_id
  LIMIT 1;

  IF v_user_company_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve company for current user';
  END IF;

  -- Lock selected table row to keep the get/create operation deterministic per table.
  SELECT os.outlet_id
  INTO v_outlet_id
  FROM public.outlet_tables ot
  JOIN public.outlet_sections os ON os.id = ot.section_id
  JOIN public.outlets o ON o.id = os.outlet_id
  WHERE ot.id = p_table_id
    AND o.company_id = v_user_company_id
  FOR UPDATE OF ot;

  IF v_outlet_id IS NULL THEN
    RAISE EXCEPTION 'Table % is not accessible for the current user', p_table_id;
  END IF;

  SELECT pm.id
  INTO v_open_status_id
  FROM public.payment_methods pm
  WHERE pm.name = 'OPEN'
  LIMIT 1;

  IF v_open_status_id IS NULL THEN
    RAISE EXCEPTION 'OPEN payment method is not configured';
  END IF;

  SELECT ord.id
  INTO v_order_id
  FROM public.orders ord
  WHERE ord.table_id = p_table_id
    AND ord.status_id = v_open_status_id
  ORDER BY ord.created_at DESC
  LIMIT 1;

  IF v_order_id IS NULL THEN
    SELECT COALESCE(outl.day_open, CURRENT_DATE)
    INTO v_outlet_day
    FROM public.outlets outl
    WHERE outl.id = v_outlet_id;

    INSERT INTO public.outlet_order_counters (outlet_id, last_bill_number)
    VALUES (v_outlet_id, 1)
    ON CONFLICT (outlet_id)
    DO UPDATE
      SET last_bill_number = public.outlet_order_counters.last_bill_number + 1,
          updated_at = now()
    RETURNING last_bill_number INTO v_next_bill_number;

    INSERT INTO public.orders (
      bill_number,
      table_id,
      outlet_id,
      date,
      status_id,
      waiter_id,
      mode,
      created_by
    )
    VALUES (
      v_next_bill_number,
      p_table_id,
      v_outlet_id,
      COALESCE(v_outlet_day, CURRENT_DATE),
      v_open_status_id,
      v_user_id,
      p_mode,
      v_user_id
    )
    RETURNING id INTO v_order_id;
  END IF;

  RETURN QUERY
  SELECT ov.*
  FROM public.orders_view ov
  WHERE ov.order_id = v_order_id;
END;
$$;

-- ============================================================
-- 10. RLS
-- ============================================================
ALTER TABLE public.payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outlet_order_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_settlements ENABLE ROW LEVEL SECURITY;

-- payment_methods: global read access only
CREATE POLICY "Authenticated users can view payment methods"
  ON public.payment_methods
  FOR SELECT
  TO authenticated
  USING (true);

-- clients policies
CREATE POLICY "Users can view clients in their company"
  ON public.clients
  FOR SELECT
  TO authenticated
  USING (
    company_id IN (
      SELECT o.company_id
      FROM public.outlets o
      JOIN public.users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid()
    )
  );

CREATE POLICY "Users can create clients in their company"
  ON public.clients
  FOR INSERT
  TO authenticated
  WITH CHECK (
    company_id IN (
      SELECT o.company_id
      FROM public.outlets o
      JOIN public.users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid()
    )
  );

CREATE POLICY "Users can update clients in their company"
  ON public.clients
  FOR UPDATE
  TO authenticated
  USING (
    company_id IN (
      SELECT o.company_id
      FROM public.outlets o
      JOIN public.users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid()
    )
  )
  WITH CHECK (
    company_id IN (
      SELECT o.company_id
      FROM public.outlets o
      JOIN public.users u ON u.outlet_id = o.id
      WHERE u.id = auth.uid()
    )
  );

-- orders policies
CREATE POLICY "Users can view orders in their company"
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id
      FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can create orders in their company"
  ON public.orders
  FOR INSERT
  TO authenticated
  WITH CHECK (
    outlet_id IN (
      SELECT o.id
      FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  );

CREATE POLICY "Users can update orders in their company"
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id
      FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  )
  WITH CHECK (
    outlet_id IN (
      SELECT o.id
      FROM public.outlets o
      WHERE o.company_id IN (
        SELECT o2.company_id
        FROM public.outlets o2
        JOIN public.users u ON u.outlet_id = o2.id
        WHERE u.id = auth.uid()
      )
    )
  );

-- order_items policies
CREATE POLICY "Users can view order items in their company"
  ON public.order_items
  FOR SELECT
  TO authenticated
  USING (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Users can create order items in their company"
  ON public.order_items
  FOR INSERT
  TO authenticated
  WITH CHECK (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Users can update order items in their company"
  ON public.order_items
  FOR UPDATE
  TO authenticated
  USING (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  )
  WITH CHECK (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

-- order_settlements policies
CREATE POLICY "Users can view order settlements in their company"
  ON public.order_settlements
  FOR SELECT
  TO authenticated
  USING (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Users can create order settlements in their company"
  ON public.order_settlements
  FOR INSERT
  TO authenticated
  WITH CHECK (
    order_id IN (
      SELECT ord.id
      FROM public.orders ord
      WHERE ord.outlet_id IN (
        SELECT o.id
        FROM public.outlets o
        WHERE o.company_id IN (
          SELECT o2.company_id
          FROM public.outlets o2
          JOIN public.users u ON u.outlet_id = o2.id
          WHERE u.id = auth.uid()
        )
      )
    )
  );

-- ============================================================
-- 11. Grants
-- ============================================================
GRANT SELECT ON public.payment_methods TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.clients TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.order_items TO authenticated;
GRANT SELECT, INSERT ON public.order_settlements TO authenticated;
GRANT SELECT ON public.orders_view TO authenticated;
GRANT SELECT ON public.outlet_tables_view TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_table_order(INTEGER, public.order_mode) TO authenticated;
