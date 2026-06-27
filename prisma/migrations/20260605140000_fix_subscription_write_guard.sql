-- Fix company_subscription_allows_writes to never block a client whose
-- Stripe subscription is provably still running, and to fully bypass
-- subscription checks for internal test accounts.
--
-- Changes vs original (20260527150000_add_subscription_write_guards.sql):
--   1. Add is_test_account column to companies — test accounts bypass all checks.
--   2. Allow 'incomplete' — initial payment is still being processed by Stripe.
--   3. Add current_period_end safety net for past_due recovery: if Stripe
--      collected payment and updated current_period_end to a future date, the
--      subscription is effectively active even if the status webhook was delayed.
--   4. Add ORDER BY br.created_at DESC for consistency with get_company_subscription
--      and user_profiles_view (both use the same ordering on billing_records).

-- ── 1. Add is_test_account to companies ──────────────────────────
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS is_test_account BOOLEAN NOT NULL DEFAULT false;

-- ── 2. Replace company_subscription_allows_writes ────────────────
CREATE OR REPLACE FUNCTION company_subscription_allows_writes(p_company_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_is_test BOOLEAN;
BEGIN
  -- Test accounts are never restricted
  SELECT COALESCE(is_test_account, false)
    INTO v_is_test
    FROM companies
   WHERE id = p_company_id;

  IF v_is_test THEN
    RETURN TRUE;
  END IF;

  -- Standard subscription check
  RETURN COALESCE(
    (
      SELECT
        CASE
          -- Unambiguously active states
          WHEN br.subscription_status IN ('active', 'trialing') THEN TRUE

          -- Initial payment in flight — allow while Stripe processes it
          WHEN br.subscription_status = 'incomplete' THEN TRUE

          -- past_due: allow within grace window, OR if current billing period
          -- has not yet ended (proves Stripe collected payment even if the
          -- subscription.updated webhook hasn't arrived yet)
          WHEN br.subscription_status = 'past_due'
               AND (
                 br.grace_period_ends_at IS NULL
                 OR br.grace_period_ends_at > NOW()
                 OR (br.current_period_end IS NOT NULL AND br.current_period_end > NOW())
               )
            THEN TRUE

          -- Explicitly canceled — block
          WHEN br.subscription_status = 'canceled' THEN FALSE

          ELSE FALSE
        END
      FROM billing_records br
      WHERE br.company_id = p_company_id
      ORDER BY br.created_at DESC
      LIMIT 1
    ),
    TRUE  -- No billing record → allow (company during onboarding)
  );
END;
$$;
