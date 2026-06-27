-- Create a view for user profiles with related company, outlet, and subscription data
-- Returns complex relations as JSON objects

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
    -- 'day_open', o.day_opened_at,
    'address', o.address,
    'company_id', o.company_id,
    'created_at', o.created_at,
    'updated_at', o.updated_at
  ) AS outlet,
  jsonb_build_object(
    'id', b.id,
    'package', b.package,
    'subscription_status', b.subscription_status,
    'trial_ends_at', b.trial_ends_at,
    'stripe_customer_id', b.stripe_customer_id,
    'stripe_subscription_id', b.stripe_subscription_id
  ) AS subscription
FROM
  users u
LEFT JOIN outlets o ON u.outlet_id = o.id
LEFT JOIN companies c ON o.company_id = c.id
LEFT JOIN billing_records b ON o.id = b.outlet_id;

-- Enable security invoker to respect RLS policies of underlying tables
ALTER VIEW user_profiles_view SET (security_invoker = on);

-- Grant access to authenticated users
GRANT SELECT ON user_profiles_view TO authenticated;
