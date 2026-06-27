-- Migration: Create billing invoices table and refresh package limits
-- Created: 2026-04-09
-- Description:
--   1. Persists Stripe invoice records in Supabase for in-app billing history
--   2. Updates subscription package copy to reflect the current seat limits

CREATE TABLE IF NOT EXISTS public.billing_invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  stripe_invoice_id TEXT NOT NULL UNIQUE,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  invoice_number TEXT,
  amount_due INTEGER NOT NULL DEFAULT 0,
  amount_paid INTEGER NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'usd',
  status TEXT NOT NULL DEFAULT 'draft',
  invoice_date TIMESTAMPTZ,
  due_date TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  invoice_pdf TEXT,
  hosted_invoice_url TEXT,
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_billing_invoices_company_id
  ON public.billing_invoices(company_id);

CREATE INDEX IF NOT EXISTS idx_billing_invoices_company_id_invoice_date
  ON public.billing_invoices(company_id, invoice_date DESC);

CREATE INDEX IF NOT EXISTS idx_billing_invoices_stripe_subscription_id
  ON public.billing_invoices(stripe_subscription_id);

DROP TRIGGER IF EXISTS update_billing_invoices_updated_at
  ON public.billing_invoices;

CREATE TRIGGER update_billing_invoices_updated_at
BEFORE UPDATE ON public.billing_invoices
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.billing_invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view billing invoices for their company"
  ON public.billing_invoices;

CREATE POLICY "Users can view billing invoices for their company"
  ON public.billing_invoices FOR SELECT
  USING (company_id = public.get_auth_user_company_id());

DROP POLICY IF EXISTS "Super users can manage billing invoices for their company"
  ON public.billing_invoices;

CREATE POLICY "Super users can manage billing invoices for their company"
  ON public.billing_invoices FOR ALL
  USING (
    company_id = public.get_auth_user_company_id()
    AND EXISTS (
      SELECT 1
      FROM public.company_users_view cu
      WHERE cu.id = auth.uid()
        AND cu.company_id = public.get_auth_user_company_id()
        AND cu.is_active = true
        AND cu.role IN ('super', 'super_admin', 'admin')
    )
  )
  WITH CHECK (
    company_id = public.get_auth_user_company_id()
    AND EXISTS (
      SELECT 1
      FROM public.company_users_view cu
      WHERE cu.id = auth.uid()
        AND cu.company_id = public.get_auth_user_company_id()
        AND cu.is_active = true
        AND cu.role IN ('super', 'super_admin', 'admin')
    )
  );

GRANT SELECT ON public.billing_invoices TO authenticated;

CREATE OR REPLACE FUNCTION public.create_company_notification(
  p_company_id BIGINT,
  p_type notification_type,
  p_priority notification_priority,
  p_title TEXT,
  p_message TEXT,
  p_metadata JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notifications (
    user_id,
    company_id,
    type,
    priority,
    title,
    message,
    metadata
  )
  SELECT
    cu.id,
    p_company_id,
    p_type,
    p_priority,
    p_title,
    p_message,
    p_metadata
  FROM public.company_users_view cu
  WHERE cu.company_id = p_company_id
    AND cu.is_active = true;
END;
$$;

UPDATE public.subscription_packages
SET
  description = 'Perfect for small businesses just getting started',
  features = '["1 Outlet", "Up to 5 User Accounts", "Basic Menu Management", "Order Processing", "Email Support"]'::jsonb
WHERE id = 'starter';

UPDATE public.subscription_packages
SET
  description = 'Great for growing businesses with multiple locations',
  features = '["Up to 3 Outlets", "Up to 20 Users Per Outlet", "Advanced Analytics", "AI Menu Extraction", "Priority Support"]'::jsonb
WHERE id = 'professional';

UPDATE public.subscription_packages
SET
  description = 'Complete solution for large businesses with advanced needs',
  features = '["Unlimited Outlets", "Unlimited Users", "Advanced Analytics & Reports", "AI Menu Extraction", "Custom Integrations", "24/7 Premium Support"]'::jsonb
WHERE id = 'enterprise';
