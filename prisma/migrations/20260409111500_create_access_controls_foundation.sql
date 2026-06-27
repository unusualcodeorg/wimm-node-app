-- Migration: Create access controls foundation
-- Created: 2026-04-09
-- Description:
--   - Creates global access controls catalog shared across all companies
--   - Creates company-owned access policies and policy-control mappings
--   - Creates outlet-role policy assignments for restricted roles
--   - Adds helper functions for security management and effective access resolution

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Supporting enum and indexes
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'access_control_area'
  ) THEN
    CREATE TYPE public.access_control_area AS ENUM ('dashboard', 'sales');
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_outlets_company_id_id_unique
  ON public.outlets(company_id, id);

-- ============================================================
-- 2. Access controls catalog
-- ============================================================
CREATE TABLE IF NOT EXISTS public.access_controls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  area public.access_control_area NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT access_controls_code_unique UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_access_controls_area_sort_order
  ON public.access_controls(area, sort_order, name);

DROP TRIGGER IF EXISTS update_access_controls_updated_at ON public.access_controls;
CREATE TRIGGER update_access_controls_updated_at
  BEFORE UPDATE ON public.access_controls
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 3. Company-owned access policies
-- ============================================================
CREATE TABLE IF NOT EXISTS public.access_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  created_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_access_policies_company_lower_name_unique
  ON public.access_policies(company_id, lower(name));

CREATE UNIQUE INDEX IF NOT EXISTS idx_access_policies_company_id_id_unique
  ON public.access_policies(company_id, id);

CREATE INDEX IF NOT EXISTS idx_access_policies_company_id_created_at
  ON public.access_policies(company_id, created_at DESC);

DROP TRIGGER IF EXISTS update_access_policies_updated_at ON public.access_policies;
CREATE TRIGGER update_access_policies_updated_at
  BEFORE UPDATE ON public.access_policies
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 4. Policy-to-control mappings
-- ============================================================
CREATE TABLE IF NOT EXISTS public.access_policy_controls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id UUID NOT NULL REFERENCES public.access_policies(id) ON DELETE CASCADE,
  access_control_id UUID NOT NULL REFERENCES public.access_controls(id) ON DELETE CASCADE,
  added_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT access_policy_controls_policy_control_unique UNIQUE (policy_id, access_control_id)
);

CREATE INDEX IF NOT EXISTS idx_access_policy_controls_policy_id
  ON public.access_policy_controls(policy_id);

CREATE INDEX IF NOT EXISTS idx_access_policy_controls_access_control_id
  ON public.access_policy_controls(access_control_id);

-- ============================================================
-- 5. Outlet-role policy assignments
-- ============================================================
CREATE TABLE IF NOT EXISTS public.role_policy_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id BIGINT NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  outlet_id UUID NOT NULL,
  role public.user_role NOT NULL,
  policy_id UUID NOT NULL,
  assigned_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT role_policy_assignments_role_restricted_only CHECK (
    role <> ALL (ARRAY['super'::public.user_role, 'admin'::public.user_role, 'super_admin'::public.user_role])
  ),
  CONSTRAINT role_policy_assignments_outlet_fk FOREIGN KEY (company_id, outlet_id)
    REFERENCES public.outlets(company_id, id) ON DELETE CASCADE,
  CONSTRAINT role_policy_assignments_policy_fk FOREIGN KEY (company_id, policy_id)
    REFERENCES public.access_policies(company_id, id) ON DELETE CASCADE,
  CONSTRAINT role_policy_assignments_outlet_role_unique UNIQUE (outlet_id, role)
);

CREATE INDEX IF NOT EXISTS idx_role_policy_assignments_company_id
  ON public.role_policy_assignments(company_id);

CREATE INDEX IF NOT EXISTS idx_role_policy_assignments_policy_id
  ON public.role_policy_assignments(policy_id);

CREATE INDEX IF NOT EXISTS idx_role_policy_assignments_outlet_role
  ON public.role_policy_assignments(outlet_id, role);

DROP TRIGGER IF EXISTS update_role_policy_assignments_updated_at ON public.role_policy_assignments;
CREATE TRIGGER update_role_policy_assignments_updated_at
  BEFORE UPDATE ON public.role_policy_assignments
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 6. Seed global access controls
-- ============================================================
INSERT INTO public.access_controls (code, name, description, area, sort_order)
VALUES
  (
    'dashboard.page.access',
    'Access dashboard page',
    'Allows the user to open and use the dashboard area of the app.',
    'dashboard',
    10
  ),
  (
    'dashboard.departments.create',
    'Create departments',
    'Allows the user to create new outlet departments from the dashboard.',
    'dashboard',
    20
  ),
  (
    'dashboard.menu.manage',
    'Manage menu items',
    'Allows the user to create, update, and remove menu categories, menu items, and add-ons.',
    'dashboard',
    30
  ),
  (
    'dashboard.sections_tables.manage',
    'Manage sections and tables',
    'Allows the user to create and update outlet sections, tables, and printer setup from the dashboard.',
    'dashboard',
    40
  ),
  (
    'dashboard.outlets.manage',
    'Manage outlets',
    'Allows the user to create, update, and manage outlet details.',
    'dashboard',
    50
  ),
  (
    'dashboard.clients.view',
    'View clients',
    'Allows the user to access company client records in the dashboard.',
    'dashboard',
    60
  ),
  (
    'dashboard.users.manage',
    'Manage user accounts',
    'Allows the user to create, invite, disable, and manage employee user accounts.',
    'dashboard',
    70
  ),
  (
    'dashboard.sales_reports.view',
    'View sales reports',
    'Allows the user to open dashboard sales reports and related financial reporting pages.',
    'dashboard',
    80
  ),
  (
    'dashboard.security.access',
    'Access security page',
    'Allows the user to open the security area and manage access policies and permissions.',
    'dashboard',
    90
  ),
  (
    'dashboard.settings.access',
    'Access settings page',
    'Allows the user to open the company settings area in the dashboard.',
    'dashboard',
    100
  ),
  (
    'dashboard.billings.access',
    'Access billings page',
    'Allows the user to open billing and subscription management pages.',
    'dashboard',
    110
  ),
  (
    'dashboard.multiple_outlets.access',
    'Access multiple outlets',
    'Allows the user to switch outlet context and work across more than one outlet.',
    'dashboard',
    120
  ),
  (
    'sales.day.open',
    'Open a new day',
    'Allows the user to open a new business day from the sales page.',
    'sales',
    130
  ),
  (
    'sales.orders.create',
    'Create orders',
    'Allows the user to create new dine-in, takeaway, or cash orders from the sales page.',
    'sales',
    140
  ),
  (
    'sales.order_items.delete_pending',
    'Delete pending order items',
    'Allows the user to remove order items before they are confirmed to a KOT.',
    'sales',
    150
  ),
  (
    'sales.order_items.shift',
    'Shift items between tables',
    'Allows the user to move confirmed order items between tables and running orders.',
    'sales',
    160
  ),
  (
    'sales.discounts.offer',
    'Offer discounts',
    'Allows the user to add, replace, or remove discounts on running orders.',
    'sales',
    170
  ),
  (
    'sales.order_items.cancel',
    'Cancel order items',
    'Allows the user to cancel already confirmed order items and record a reason.',
    'sales',
    180
  ),
  (
    'sales.bills.reprint',
    'Re-print bills',
    'Allows the user to re-print customer bills.',
    'sales',
    190
  ),
  (
    'sales.kots.reprint',
    'Re-print KOTs',
    'Allows the user to re-print kitchen order tickets.',
    'sales',
    200
  )
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  area = EXCLUDED.area,
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();

-- ============================================================
-- 7. Helper functions
-- ============================================================
CREATE OR REPLACE FUNCTION public.auth_user_can_access_security_console()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.get_auth_user_role() IN ('super'::public.user_role, 'super_admin'::public.user_role), false);
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_access_security_console() TO authenticated;

CREATE OR REPLACE FUNCTION public.auth_user_can_manage_company_access(p_company_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    public.get_auth_user_role() = 'super_admin'::public.user_role
    OR (
      public.get_auth_user_role() = 'super'::public.user_role
      AND public.get_auth_user_company_id()::BIGINT = p_company_id
    ),
    false
  );
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_manage_company_access(BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.auth_user_can_manage_access_policy(p_policy_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.access_policies ap
    WHERE ap.id = p_policy_id
      AND public.auth_user_can_manage_company_access(ap.company_id)
  );
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_manage_access_policy(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_auth_user_effective_access_controls()
RETURNS TABLE (
  id UUID,
  code TEXT,
  name TEXT,
  description TEXT,
  area public.access_control_area,
  sort_order INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH auth_user AS (
    SELECT
      u.id,
      u.role,
      u.outlet_id,
      o.company_id AS company_id
    FROM public.users u
    LEFT JOIN public.outlets o ON o.id = u.outlet_id
    WHERE u.id = auth.uid()
    LIMIT 1
  ),
  unrestricted_controls AS (
    SELECT ac.id, ac.code, ac.name, ac.description, ac.area, ac.sort_order
    FROM public.access_controls ac
    WHERE EXISTS (
      SELECT 1
      FROM auth_user au
      WHERE au.role IN (
        'super'::public.user_role,
        'admin'::public.user_role,
        'super_admin'::public.user_role
      )
    )
  ),
  assigned_controls AS (
    SELECT DISTINCT ac.id, ac.code, ac.name, ac.description, ac.area, ac.sort_order
    FROM auth_user au
    JOIN public.role_policy_assignments rpa
      ON rpa.company_id = au.company_id
     AND rpa.outlet_id = au.outlet_id
     AND rpa.role = au.role
    JOIN public.access_policy_controls apc
      ON apc.policy_id = rpa.policy_id
    JOIN public.access_controls ac
      ON ac.id = apc.access_control_id
  )
  SELECT DISTINCT effective.id, effective.code, effective.name, effective.description, effective.area, effective.sort_order
  FROM (
    SELECT * FROM unrestricted_controls
    UNION ALL
    SELECT * FROM assigned_controls
  ) AS effective
  ORDER BY effective.sort_order, effective.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_auth_user_effective_access_controls() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_auth_user_access_control_codes()
RETURNS TEXT[]
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    ARRAY(
      SELECT gac.code
      FROM public.get_auth_user_effective_access_controls() gac
      ORDER BY gac.sort_order, gac.name
    ),
    ARRAY[]::TEXT[]
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_auth_user_access_control_codes() TO authenticated;

-- ============================================================
-- 8. RLS setup
-- ============================================================
ALTER TABLE public.access_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_policy_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_policy_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Access managers can view global access controls" ON public.access_controls;
CREATE POLICY "Access managers can view global access controls"
  ON public.access_controls
  FOR SELECT
  TO authenticated
  USING (public.auth_user_can_access_security_console());

DROP POLICY IF EXISTS "Access managers can view company access policies" ON public.access_policies;
CREATE POLICY "Access managers can view company access policies"
  ON public.access_policies
  FOR SELECT
  TO authenticated
  USING (public.auth_user_can_manage_company_access(company_id));

DROP POLICY IF EXISTS "Access managers can insert company access policies" ON public.access_policies;
CREATE POLICY "Access managers can insert company access policies"
  ON public.access_policies
  FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_user_can_manage_company_access(company_id));

DROP POLICY IF EXISTS "Access managers can update company access policies" ON public.access_policies;
CREATE POLICY "Access managers can update company access policies"
  ON public.access_policies
  FOR UPDATE
  TO authenticated
  USING (public.auth_user_can_manage_company_access(company_id))
  WITH CHECK (public.auth_user_can_manage_company_access(company_id));

DROP POLICY IF EXISTS "Access managers can delete company access policies" ON public.access_policies;
CREATE POLICY "Access managers can delete company access policies"
  ON public.access_policies
  FOR DELETE
  TO authenticated
  USING (public.auth_user_can_manage_company_access(company_id));

DROP POLICY IF EXISTS "Access managers can view policy access controls" ON public.access_policy_controls;
CREATE POLICY "Access managers can view policy access controls"
  ON public.access_policy_controls
  FOR SELECT
  TO authenticated
  USING (public.auth_user_can_manage_access_policy(policy_id));

DROP POLICY IF EXISTS "Access managers can insert policy access controls" ON public.access_policy_controls;
CREATE POLICY "Access managers can insert policy access controls"
  ON public.access_policy_controls
  FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_user_can_manage_access_policy(policy_id));

DROP POLICY IF EXISTS "Access managers can delete policy access controls" ON public.access_policy_controls;
CREATE POLICY "Access managers can delete policy access controls"
  ON public.access_policy_controls
  FOR DELETE
  TO authenticated
  USING (public.auth_user_can_manage_access_policy(policy_id));

DROP POLICY IF EXISTS "Access managers can view role policy assignments" ON public.role_policy_assignments;
CREATE POLICY "Access managers can view role policy assignments"
  ON public.role_policy_assignments
  FOR SELECT
  TO authenticated
  USING (public.auth_user_can_manage_company_access(company_id));

DROP POLICY IF EXISTS "Access managers can insert role policy assignments" ON public.role_policy_assignments;
CREATE POLICY "Access managers can insert role policy assignments"
  ON public.role_policy_assignments
  FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_user_can_manage_company_access(company_id));

DROP POLICY IF EXISTS "Access managers can update role policy assignments" ON public.role_policy_assignments;
CREATE POLICY "Access managers can update role policy assignments"
  ON public.role_policy_assignments
  FOR UPDATE
  TO authenticated
  USING (public.auth_user_can_manage_company_access(company_id))
  WITH CHECK (public.auth_user_can_manage_company_access(company_id));

DROP POLICY IF EXISTS "Access managers can delete role policy assignments" ON public.role_policy_assignments;
CREATE POLICY "Access managers can delete role policy assignments"
  ON public.role_policy_assignments
  FOR DELETE
  TO authenticated
  USING (public.auth_user_can_manage_company_access(company_id));

-- ============================================================
-- 9. Grants
-- ============================================================
GRANT SELECT ON public.access_controls TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.access_policies TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.access_policy_controls TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.role_policy_assignments TO authenticated;
