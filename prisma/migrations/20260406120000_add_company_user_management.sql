-- Migration: Add company user management foundations
-- Created: 2026-04-06
-- Description:
--   - Adds activation/audit fields to public.users
--   - Updates handle_new_user() to propagate role/outlet/inviter metadata
--   - Creates a flat company_users_view for dashboard management queries

-- ============================================================
-- 1. Add user activation and audit columns
-- ============================================================
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS disabled_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS disabled_by UUID REFERENCES public.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_is_active ON public.users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_invited_by ON public.users(invited_by);
CREATE INDEX IF NOT EXISTS idx_users_disabled_by ON public.users(disabled_by);

-- ============================================================
-- 2. Update the auth.users propagation trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role_text TEXT;
  v_role public.user_role := 'super'::public.user_role;
  v_outlet_id UUID;
  v_invited_by UUID;
  v_is_active BOOLEAN := true;
BEGIN
  v_role_text := NULLIF(NEW.raw_user_meta_data->>'role', '');

  IF v_role_text IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON e.enumtypid = t.oid
      WHERE t.typname = 'user_role'
        AND e.enumlabel = v_role_text
    ) THEN
    v_role := v_role_text::public.user_role;
  END IF;

  v_outlet_id := NULLIF(NEW.raw_user_meta_data->>'outlet_id', '')::UUID;
  v_invited_by := NULLIF(NEW.raw_user_meta_data->>'invited_by', '')::UUID;

  IF NEW.raw_user_meta_data ? 'is_active' THEN
    BEGIN
      v_is_active := COALESCE(
        NULLIF(NEW.raw_user_meta_data->>'is_active', '')::BOOLEAN,
        true
      );
    EXCEPTION
      WHEN others THEN
        v_is_active := true;
    END;
  END IF;

  INSERT INTO public.users (
    id,
    email,
    first_name,
    last_name,
    role,
    outlet_id,
    is_active,
    invited_by
  )
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
    v_role,
    v_outlet_id,
    v_is_active,
    v_invited_by
  );

  RETURN NEW;
END;
$$;

-- ============================================================
-- 3. Flat view for dashboard employee management
-- ============================================================
DROP VIEW IF EXISTS public.company_users_view;

CREATE VIEW public.company_users_view AS
SELECT
  u.id,
  u.email,
  u.first_name,
  u.last_name,
  u.role,
  u.outlet_id,
  u.is_active,
  u.invited_by,
  u.disabled_at,
  u.disabled_by,
  u.created_at,
  u.updated_at,
  o.company_id,
  o.name AS outlet_name,
  o.business_type AS outlet_business_type,
  jsonb_build_object(
    'id', inviter.id,
    'email', inviter.email,
    'first_name', inviter.first_name,
    'last_name', inviter.last_name
  ) AS invited_by_user,
  jsonb_build_object(
    'id', disabler.id,
    'email', disabler.email,
    'first_name', disabler.first_name,
    'last_name', disabler.last_name
  ) AS disabled_by_user
FROM public.users u
LEFT JOIN public.outlets o
  ON o.id = u.outlet_id
LEFT JOIN public.users inviter
  ON inviter.id = u.invited_by
LEFT JOIN public.users disabler
  ON disabler.id = u.disabled_by;

ALTER VIEW public.company_users_view SET (security_invoker = on);
GRANT SELECT ON public.company_users_view TO authenticated;
