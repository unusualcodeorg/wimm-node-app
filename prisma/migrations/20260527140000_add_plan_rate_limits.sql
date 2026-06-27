-- Plan Rate Limits: DB-level enforcement for subscription plan outlet/user caps.
-- Starter: 1 outlet, 5 total users
-- Professional: 3 outlets, 50 users per outlet
-- Enterprise: unlimited (NULL)

CREATE TABLE IF NOT EXISTS plan_rate_limits (
  plan_id       subscription_package PRIMARY KEY REFERENCES subscription_packages(id) ON DELETE CASCADE,
  max_outlets   INTEGER,             -- NULL = unlimited
  max_users     INTEGER,             -- NULL = no total-user cap (used for starter only)
  max_users_per_outlet INTEGER,      -- NULL = no per-outlet cap (used for professional)
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO plan_rate_limits (plan_id, max_outlets, max_users, max_users_per_outlet)
VALUES
  ('starter',      1,    5,    NULL),
  ('professional', 3,    NULL, 50),
  ('enterprise',   NULL, NULL, NULL)
ON CONFLICT (plan_id) DO UPDATE
  SET max_outlets          = EXCLUDED.max_outlets,
      max_users            = EXCLUDED.max_users,
      max_users_per_outlet = EXCLUDED.max_users_per_outlet;

-- ──────────────────────────────────────────────
-- Outlet limit trigger
-- ──────────────────────────────────────────────
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
  -- Resolve the company plan
  SELECT br.package
    INTO v_plan
    FROM billing_records br
   WHERE br.company_id = NEW.company_id
   LIMIT 1;

  IF v_plan IS NULL THEN
    RETURN NEW; -- No billing record yet; allow during onboarding
  END IF;

  SELECT prl.max_outlets
    INTO v_max_outlets
    FROM plan_rate_limits prl
   WHERE prl.plan_id = v_plan;

  -- NULL means unlimited
  IF v_max_outlets IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*)
    INTO v_active_outlets
    FROM outlets
   WHERE company_id = NEW.company_id
     AND is_active = TRUE;

  IF v_active_outlets >= v_max_outlets THEN
    RAISE EXCEPTION 'outlet_limit_exceeded: Your % plan allows a maximum of % outlet(s). Upgrade your plan to add more outlets.',
      v_plan, v_max_outlets
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_outlet_plan_limit ON outlets;
CREATE TRIGGER trg_check_outlet_plan_limit
  BEFORE INSERT ON outlets
  FOR EACH ROW
  EXECUTE FUNCTION check_outlet_plan_limit();

-- ──────────────────────────────────────────────
-- User limit trigger
-- ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_user_plan_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_plan               subscription_package;
  v_max_users          INTEGER;
  v_max_per_outlet     INTEGER;
  v_total_users        INTEGER;
  v_outlet_users       INTEGER;
BEGIN
  -- Resolve the company plan
  SELECT br.package
    INTO v_plan
    FROM billing_records br
   WHERE br.company_id = NEW.company_id
   LIMIT 1;

  IF v_plan IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT prl.max_users, prl.max_users_per_outlet
    INTO v_max_users, v_max_per_outlet
    FROM plan_rate_limits prl
   WHERE prl.plan_id = v_plan;

  -- Check total-user cap (used by starter)
  IF v_max_users IS NOT NULL THEN
    SELECT COUNT(*)
      INTO v_total_users
      FROM users
     WHERE company_id = NEW.company_id
       AND disabled_at IS NULL;

    IF v_total_users >= v_max_users THEN
      RAISE EXCEPTION 'user_limit_exceeded: Your % plan allows a maximum of % user(s). Upgrade your plan to add more users.',
        v_plan, v_max_users
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Check per-outlet cap (used by professional)
  IF v_max_per_outlet IS NOT NULL AND NEW.outlet_id IS NOT NULL THEN
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

DROP TRIGGER IF EXISTS trg_check_user_plan_limit ON users;
CREATE TRIGGER trg_check_user_plan_limit
  BEFORE INSERT ON users
  FOR EACH ROW
  EXECUTE FUNCTION check_user_plan_limit();

-- RLS: service role and super users can manage plan_rate_limits
ALTER TABLE plan_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "plan_rate_limits_read"
  ON plan_rate_limits FOR SELECT
  TO authenticated
  USING (true);
