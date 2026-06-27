-- Migration: Update user_profiles_view for company-based billing
-- Created: 2026-01-30
-- Description: Updates user_profiles_view to fetch billing records by company_id instead of outlet_id

DROP VIEW IF EXISTS user_profiles_view;

CREATE OR REPLACE VIEW user_profiles_view AS
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
    'company_id', o.company_id,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'day_open', o.day_opened_at
  ) AS outlet,
  jsonb_build_object(
    'id', b.id,
    'package', b.package,
    'subscription_status', b.subscription_status,
    'trial_ends_at', b.trial_ends_at,
    'stripe_customer_id', b.stripe_customer_id,
    'stripe_subscription_id', b.stripe_subscription_id,
    'current_period_start', b.current_period_start,
    'current_period_end', b.current_period_end,
    'cancel_at_period_end', b.cancel_at_period_end,
    'canceled_at', b.canceled_at
  ) AS subscription
FROM
  users u
LEFT JOIN outlets o ON u.outlet_id = o.id
LEFT JOIN companies c ON o.company_id = c.id
LEFT JOIN billing_records b ON c.id = b.company_id;

-- Enable security invoker to respect RLS policies of underlying tables
ALTER VIEW user_profiles_view SET (security_invoker = on);

-- Grant access to authenticated users
GRANT SELECT ON user_profiles_view TO authenticated;
