-- Email notification recipients per outlet
-- events is a text[] containing zero or more of: 'sales_report', 'accommodation_booking'
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.outlet_email_configurations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT NOT NULL,
  events TEXT[] NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS outlet_email_configurations_outlet_id_idx
  ON public.outlet_email_configurations (outlet_id);

-- RLS
ALTER TABLE public.outlet_email_configurations ENABLE ROW LEVEL SECURITY;

-- Company members can read configurations for their own outlets
DROP POLICY IF EXISTS "outlet_email_config_select" ON public.outlet_email_configurations;
CREATE POLICY "outlet_email_config_select" ON public.outlet_email_configurations
  FOR SELECT USING (
    outlet_id IN (
      SELECT id FROM public.outlets WHERE company_id = public.get_auth_user_company_id()
    )
  );

-- Only authorised roles (super/admin/super_admin) can manage configurations
DROP POLICY IF EXISTS "outlet_email_config_insert" ON public.outlet_email_configurations;
CREATE POLICY "outlet_email_config_insert" ON public.outlet_email_configurations
  FOR INSERT WITH CHECK (
    outlet_id IN (
      SELECT id FROM public.outlets WHERE company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "outlet_email_config_update" ON public.outlet_email_configurations;
CREATE POLICY "outlet_email_config_update" ON public.outlet_email_configurations
  FOR UPDATE USING (
    outlet_id IN (
      SELECT id FROM public.outlets WHERE company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "outlet_email_config_delete" ON public.outlet_email_configurations;
CREATE POLICY "outlet_email_config_delete" ON public.outlet_email_configurations
  FOR DELETE USING (
    outlet_id IN (
      SELECT id FROM public.outlets WHERE company_id = public.get_auth_user_company_id()
    )
  );

-- Insert access control entry for email configuration management
INSERT INTO public.access_controls (code, name, description, area, sort_order)
VALUES (
  'dashboard.email_config.manage',
  'Manage email configurations',
  'Allows the user to add, update, and remove email notification recipients.',
  'dashboard',
  125
)
ON CONFLICT (code) DO NOTHING;
