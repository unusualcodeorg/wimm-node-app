-- Migration: Create user onboarding progress foundation
-- Description:
--   - Stores per-user first-time onboarding progress and milestone completion
--   - Exposes onboarding progress from user_profiles_view

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.user_onboarding_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  flow_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'in_progress',
  completed_steps TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
  current_step TEXT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_onboarding_progress_status_check CHECK (
    status IN ('not_started', 'in_progress', 'completed', 'skipped')
  ),
  CONSTRAINT user_onboarding_progress_flow_unique UNIQUE (user_id, flow_key)
);

CREATE INDEX IF NOT EXISTS idx_user_onboarding_progress_user_id
  ON public.user_onboarding_progress(user_id);

CREATE INDEX IF NOT EXISTS idx_user_onboarding_progress_status
  ON public.user_onboarding_progress(status);

DROP TRIGGER IF EXISTS update_user_onboarding_progress_updated_at
  ON public.user_onboarding_progress;

CREATE TRIGGER update_user_onboarding_progress_updated_at
  BEFORE UPDATE ON public.user_onboarding_progress
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.user_onboarding_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their onboarding progress"
  ON public.user_onboarding_progress;
CREATE POLICY "Users can view their onboarding progress"
  ON public.user_onboarding_progress
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their onboarding progress"
  ON public.user_onboarding_progress;
CREATE POLICY "Users can insert their onboarding progress"
  ON public.user_onboarding_progress
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their onboarding progress"
  ON public.user_onboarding_progress;
CREATE POLICY "Users can update their onboarding progress"
  ON public.user_onboarding_progress
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

GRANT ALL ON public.user_onboarding_progress TO authenticated;

DROP VIEW IF EXISTS public.user_profiles_view;

CREATE OR REPLACE VIEW public.user_profiles_view AS
SELECT
  u.*,
  jsonb_build_object(
    'id', c.id,
    'business_name', c.business_name,
    'business_type', c.business_type,
    'country_id', c.country_id,
    'created_at', c.created_at,
    'created_by', c.created_by
  ) AS company,
  jsonb_build_object(
    'id', o.id,
    'name', o.name,
    'address', o.address,
    'business_type', o.business_type,
    'company_id', o.company_id,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'day_open', o.day_opened_at
  ) AS outlet,
  CASE
    WHEN b.id IS NULL THEN NULL
    ELSE jsonb_build_object(
      'id', b.id,
      'package', b.package,
      'billing_cycle', b.billing_cycle,
      'subscription_status', b.subscription_status,
      'trial_ends_at', b.trial_ends_at,
      'stripe_customer_id', b.stripe_customer_id,
      'stripe_subscription_id', b.stripe_subscription_id,
      'current_period_start', b.current_period_start,
      'current_period_end', b.current_period_end,
      'cancel_at_period_end', b.cancel_at_period_end,
      'canceled_at', b.canceled_at,
      'created_at', b.created_at,
      'updated_at', b.updated_at
    )
  END AS subscription,
  CASE
    WHEN uop.user_id IS NULL THEN NULL
    ELSE jsonb_build_object(
      'flow_key', uop.flow_key,
      'status', uop.status,
      'completed_steps', uop.completed_steps,
      'current_step', uop.current_step,
      'started_at', uop.started_at,
      'completed_at', uop.completed_at,
      'last_seen_at', uop.last_seen_at
    )
  END AS onboarding
FROM public.users u
LEFT JOIN public.outlets o ON u.outlet_id = o.id
LEFT JOIN public.companies c ON o.company_id = c.id
LEFT JOIN LATERAL (
  SELECT br.*
  FROM public.billing_records br
  WHERE br.company_id = c.id
  ORDER BY br.created_at DESC
  LIMIT 1
) b ON TRUE
LEFT JOIN public.user_onboarding_progress uop
  ON uop.user_id = u.id
  AND uop.flow_key = 'restaurant_first_time_setup';

ALTER VIEW public.user_profiles_view SET (security_invoker = on);
GRANT SELECT ON public.user_profiles_view TO authenticated;
