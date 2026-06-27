-- Migration: Add subscription recovery lifecycle and company purge support
-- Description:
--   - Tracks billing grace, suspension, reminder, and purge lifecycle state
--   - Adds internal helpers for invoking scheduled Edge Functions
--   - Adds a purge_company_data RPC for full workspace cleanup preparation
--   - Extends user_profiles_view and get_company_subscription with recovery fields

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

ALTER TYPE public.notification_type
  ADD VALUE IF NOT EXISTS 'billing_payment_reminder';

ALTER TYPE public.notification_type
  ADD VALUE IF NOT EXISTS 'billing_subscription_suspended';

ALTER TYPE public.notification_type
  ADD VALUE IF NOT EXISTS 'billing_data_purge_warning';

ALTER TYPE public.notification_type
  ADD VALUE IF NOT EXISTS 'billing_subscription_reactivated';

ALTER TABLE public.billing_records
  ADD COLUMN IF NOT EXISTS stripe_environment TEXT,
  ADD COLUMN IF NOT EXISTS grace_period_ends_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS data_purge_scheduled_for TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_payment_reminder_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_purge_warning_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_reminder_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_stripe_sync_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'billing_records_stripe_environment_check'
      AND conrelid = 'public.billing_records'::regclass
  ) THEN
    ALTER TABLE public.billing_records
      ADD CONSTRAINT billing_records_stripe_environment_check
      CHECK (
        stripe_environment IS NULL
        OR stripe_environment IN ('development', 'production')
      );
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_billing_records_recovery_status
  ON public.billing_records(subscription_status, grace_period_ends_at, data_purge_scheduled_for);

CREATE INDEX IF NOT EXISTS idx_billing_records_stripe_environment
  ON public.billing_records(stripe_environment);

CREATE INDEX IF NOT EXISTS idx_billing_records_data_purge_scheduled_for
  ON public.billing_records(data_purge_scheduled_for)
  WHERE data_purge_scheduled_for IS NOT NULL;

CREATE OR REPLACE FUNCTION public.invoke_internal_edge_function(
  p_function_name TEXT,
  p_body JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, net, vault
AS $$
DECLARE
  v_project_url TEXT;
  v_service_role_key TEXT;
  v_request_id BIGINT;
BEGIN
  SELECT decrypted_secret
  INTO v_project_url
  FROM vault.decrypted_secrets
  WHERE name = 'project_url'
  LIMIT 1;

  SELECT decrypted_secret
  INTO v_service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF v_project_url IS NULL OR v_service_role_key IS NULL THEN
    RAISE EXCEPTION
      'Vault secrets project_url and service_role_key must be configured before invoking internal edge functions';
  END IF;

  SELECT net.http_post(
    url := v_project_url || '/functions/v1/' || p_function_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key
    ),
    body := p_body,
    timeout_milliseconds := 10000
  )
  INTO v_request_id;

  RETURN v_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.invoke_internal_edge_function(TEXT, JSONB)
  TO service_role;

CREATE OR REPLACE FUNCTION public.purge_company_data(p_company_id BIGINT)
RETURNS TABLE (
  company_id BIGINT,
  deleted_user_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_ids UUID[];
  v_deleted_company_id BIGINT;
BEGIN
  SELECT COALESCE(array_agg(u.id), '{}'::UUID[])
  INTO v_user_ids
  FROM public.users u
  WHERE u.company_id = p_company_id;

  DELETE FROM public.user_onboarding_progress
  WHERE user_id = ANY(v_user_ids);

  DELETE FROM public.companies
  WHERE id = p_company_id
  RETURNING id INTO v_deleted_company_id;

  IF v_deleted_company_id IS NULL THEN
    RAISE EXCEPTION 'Company % was not found or could not be deleted', p_company_id;
  END IF;

  RETURN QUERY
  SELECT
    v_deleted_company_id,
    COALESCE(array_length(v_user_ids, 1), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.purge_company_data(BIGINT) TO service_role;

DROP FUNCTION IF EXISTS public.get_company_subscription(BIGINT);

CREATE FUNCTION public.get_company_subscription(p_company_id BIGINT)
RETURNS TABLE (
  id UUID,
  package subscription_package,
  billing_cycle billing_cycle,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  trial_ends_at TIMESTAMPTZ,
  subscription_status subscription_status,
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancel_at_period_end BOOLEAN,
  canceled_at TIMESTAMPTZ,
  grace_period_ends_at TIMESTAMPTZ,
  suspended_at TIMESTAMPTZ,
  data_purge_scheduled_for TIMESTAMPTZ,
  last_payment_reminder_sent_at TIMESTAMPTZ,
  last_purge_warning_sent_at TIMESTAMPTZ,
  payment_reminder_count INTEGER,
  last_stripe_sync_at TIMESTAMPTZ,
  stripe_environment TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    br.id,
    br.package,
    br.billing_cycle,
    br.stripe_customer_id,
    br.stripe_subscription_id,
    br.trial_ends_at,
    br.subscription_status,
    br.current_period_start,
    br.current_period_end,
    br.cancel_at_period_end,
    br.canceled_at,
    br.grace_period_ends_at,
    br.suspended_at,
    br.data_purge_scheduled_for,
    br.last_payment_reminder_sent_at,
    br.last_purge_warning_sent_at,
    br.payment_reminder_count,
    br.last_stripe_sync_at,
    br.stripe_environment
  FROM public.billing_records br
  WHERE br.company_id = p_company_id
  ORDER BY br.created_at DESC
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_subscription(BIGINT)
  TO authenticated;

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
      'grace_period_ends_at', b.grace_period_ends_at,
      'suspended_at', b.suspended_at,
      'data_purge_scheduled_for', b.data_purge_scheduled_for,
      'last_payment_reminder_sent_at', b.last_payment_reminder_sent_at,
      'last_purge_warning_sent_at', b.last_purge_warning_sent_at,
      'payment_reminder_count', b.payment_reminder_count,
      'last_stripe_sync_at', b.last_stripe_sync_at,
      'stripe_environment', b.stripe_environment,
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
