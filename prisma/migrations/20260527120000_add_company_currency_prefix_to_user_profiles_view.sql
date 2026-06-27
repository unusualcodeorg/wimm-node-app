-- Migration: Add company currency prefix to user_profiles_view
-- Description:
--   - Exposes companies.country_id and supported_countries.currency_prefix
--     through the authenticated profile view
--   - Enriches outlet payload with the same currency prefix for UI fallbacks

DROP VIEW IF EXISTS public.user_profiles_view;

CREATE OR REPLACE VIEW public.user_profiles_view AS
SELECT
  u.*,
  jsonb_build_object(
    'id', c.id,
    'business_name', c.business_name,
    'business_type', c.business_type,
    'country_id', c.country_id,
    'currency_prefix', sc.currency_prefix,
    'created_at', c.created_at,
    'updated_at', c.updated_at,
    'created_by', c.created_by
  ) AS company,
  jsonb_build_object(
    'id', o.id,
    'name', o.name,
    'address', o.address,
    'tin_number', o.tin_number,
    'phone', o.phone,
    'receipt_footnote', o.receipt_footnote,
    'business_type', o.business_type,
    'company_id', o.company_id,
    'currency_prefix', sc.currency_prefix,
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
LEFT JOIN public.supported_countries sc ON sc.id = c.country_id
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
