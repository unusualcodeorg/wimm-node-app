-- Migration: Add outlet-level business type and expose it in user profile view
-- Created: 2026-02-22
-- Description:
--   - Adds `business_type` to outlets
--   - Backfills outlet business type from company business type
--   - Adds trigger defaulting outlet business type from company on insert/update
--   - Updates user_profiles_view outlet payload to include outlet business_type

-- ============================================================
-- 1. Add outlet business_type column
-- ============================================================
ALTER TABLE public.outlets
ADD COLUMN IF NOT EXISTS business_type public.business_type;

UPDATE public.outlets o
SET business_type = c.business_type
FROM public.companies c
WHERE c.id = o.company_id
  AND o.business_type IS NULL;

ALTER TABLE public.outlets
ALTER COLUMN business_type SET DEFAULT 'other'::public.business_type;

ALTER TABLE public.outlets
ALTER COLUMN business_type SET NOT NULL;

-- ============================================================
-- 2. Keep outlet business_type aligned when omitted
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_outlet_business_type_from_company()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_company_business_type public.business_type;
BEGIN
  IF NEW.business_type IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.business_type
  INTO v_company_business_type
  FROM public.companies c
  WHERE c.id = NEW.company_id
  LIMIT 1;

  NEW.business_type := COALESCE(v_company_business_type, 'other'::public.business_type);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_outlet_business_type_from_company_trigger ON public.outlets;

CREATE TRIGGER set_outlet_business_type_from_company_trigger
  BEFORE INSERT OR UPDATE ON public.outlets
  FOR EACH ROW
  EXECUTE FUNCTION public.set_outlet_business_type_from_company();

-- ============================================================
-- 3. Update user_profiles_view
-- ============================================================
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
  public.users u
LEFT JOIN public.outlets o ON u.outlet_id = o.id
LEFT JOIN public.companies c ON o.company_id = c.id
LEFT JOIN public.billing_records b ON c.id = b.company_id;

ALTER VIEW public.user_profiles_view SET (security_invoker = on);
GRANT SELECT ON public.user_profiles_view TO authenticated;
