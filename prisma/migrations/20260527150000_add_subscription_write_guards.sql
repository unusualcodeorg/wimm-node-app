-- Subscription Write Guards: DB-level enforcement that blocks write operations
-- on core business tables when a company's subscription is paused/suspended.
--
-- Active conditions (writes allowed):
--   subscription_status IN ('active', 'trialing')
--   subscription_status = 'past_due' AND grace_period_ends_at > NOW()
--
-- Blocked conditions (writes rejected):
--   subscription_status = 'past_due' AND grace_period_ends_at <= NOW()
--   subscription_status IN ('suspended', 'canceled')
--   (no billing record → allowed, covers onboarding)

-- ──────────────────────────────────────────────
-- Helper: resolve company_id from outlet_id
-- ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_company_id_for_outlet(p_outlet_id UUID)
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT company_id FROM outlets WHERE id = p_outlet_id LIMIT 1;
$$;

-- ──────────────────────────────────────────────
-- Helper: check if subscription allows writes
-- Returns TRUE (allowed) or FALSE (blocked).
-- ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION company_subscription_allows_writes(p_company_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    (
      SELECT
        CASE
          WHEN br.subscription_status IN ('active', 'trialing') THEN TRUE
          WHEN br.subscription_status = 'past_due'
               AND (br.grace_period_ends_at IS NULL OR br.grace_period_ends_at > NOW())
            THEN TRUE
          ELSE FALSE
        END
      FROM billing_records br
      WHERE br.company_id = p_company_id
      LIMIT 1
    ),
    TRUE  -- No billing record: allow (new companies during onboarding)
  );
$$;

-- ──────────────────────────────────────────────
-- Shared trigger function for tables with direct company_id
-- ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION enforce_subscription_write_access_by_company()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT company_subscription_allows_writes(NEW.company_id) THEN
    RAISE EXCEPTION 'subscription_paused: Your subscription has been paused due to a payment issue. Please update your payment method to continue.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────
-- Shared trigger function for tables with outlet_id (no direct company_id)
-- ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION enforce_subscription_write_access_by_outlet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id BIGINT;
BEGIN
  v_company_id := get_company_id_for_outlet(NEW.outlet_id);

  IF v_company_id IS NOT NULL AND NOT company_subscription_allows_writes(v_company_id) THEN
    RAISE EXCEPTION 'subscription_paused: Your subscription has been paused due to a payment issue. Please update your payment method to continue.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────
-- orders  (links via outlet_id)
-- ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_subscription_guard_orders ON orders;
CREATE TRIGGER trg_subscription_guard_orders
  BEFORE INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_outlet();

-- ──────────────────────────────────────────────
-- accommodation_bookings  (links via outlet_id)
-- ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_subscription_guard_bookings ON accommodation_bookings;
CREATE TRIGGER trg_subscription_guard_bookings
  BEFORE INSERT ON accommodation_bookings
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_outlet();

-- ──────────────────────────────────────────────
-- journal_entries  (direct company_id)
-- ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_subscription_guard_journal_entries ON journal_entries;
CREATE TRIGGER trg_subscription_guard_journal_entries
  BEFORE INSERT ON journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_company();

-- ──────────────────────────────────────────────
-- accounts / chart of accounts  (direct company_id)
-- ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_subscription_guard_accounts ON accounts;
CREATE TRIGGER trg_subscription_guard_accounts
  BEFORE INSERT ON accounts
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_company();

-- ──────────────────────────────────────────────
-- inventory_items  (direct company_id)
-- ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_subscription_guard_inventory_items ON inventory_items;
CREATE TRIGGER trg_subscription_guard_inventory_items
  BEFORE INSERT ON inventory_items
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_company();

-- ──────────────────────────────────────────────
-- inventory_recipes  (direct company_id)
-- ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_subscription_guard_inventory_recipes ON inventory_recipes;
CREATE TRIGGER trg_subscription_guard_inventory_recipes
  BEFORE INSERT ON inventory_recipes
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_company();

-- ──────────────────────────────────────────────
-- supplier_invoices  (direct company_id)
-- ──────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_subscription_guard_supplier_invoices ON supplier_invoices;
CREATE TRIGGER trg_subscription_guard_supplier_invoices
  BEFORE INSERT ON supplier_invoices
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_company();
