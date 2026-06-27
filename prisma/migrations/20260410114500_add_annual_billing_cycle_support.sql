-- Migration: Add annual billing cycle support
-- Created: 2026-04-10
-- Description: Extends subscription packages and billing records to support annual pricing and billing cycle tracking

DO $$
BEGIN
  CREATE TYPE billing_cycle AS ENUM ('monthly', 'annual');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END;
$$;

ALTER TABLE public.billing_records
ADD COLUMN IF NOT EXISTS billing_cycle billing_cycle NOT NULL DEFAULT 'monthly';

ALTER TABLE public.subscription_packages
ADD COLUMN IF NOT EXISTS annual_price DECIMAL(10, 2),
ADD COLUMN IF NOT EXISTS annual_stripe_price_id TEXT,
ADD COLUMN IF NOT EXISTS annual_discount_percentage INTEGER NOT NULL DEFAULT 0;

UPDATE public.subscription_packages
SET
  annual_price = 302.30,
  annual_discount_percentage = 16
WHERE id = 'starter';

UPDATE public.subscription_packages
SET
  annual_price = 503.90,
  annual_discount_percentage = 16
WHERE id = 'professional';

UPDATE public.subscription_packages
SET
  annual_price = 1991.90,
  annual_discount_percentage = 17
WHERE id = 'enterprise';

ALTER TABLE public.subscription_packages
ALTER COLUMN annual_price SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'subscription_packages_annual_discount_percentage_check'
      AND conrelid = 'public.subscription_packages'::regclass
  ) THEN
    ALTER TABLE public.subscription_packages
    ADD CONSTRAINT subscription_packages_annual_discount_percentage_check
    CHECK (annual_discount_percentage BETWEEN 0 AND 100);
  END IF;
END;
$$;

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
  canceled_at TIMESTAMPTZ
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
    br.canceled_at
  FROM billing_records br
  WHERE br.company_id = p_company_id
  ORDER BY br.created_at DESC
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_company_subscription(BIGINT) TO authenticated;
