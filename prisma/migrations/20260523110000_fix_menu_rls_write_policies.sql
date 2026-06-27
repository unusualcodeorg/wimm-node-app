-- Fix: menu write policies only covered 'super' role.
-- admin and super_admin are full-access roles that also need write access.
-- Additionally, any role explicitly granted the relevant access control code must be able to write.
-- The same gap exists on menu_categories, departments, and addon_library — fixed here too.

-- ─── menu_items ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Super users can manage items" ON public.menu_items;

CREATE POLICY "Authorised users can manage menu items"
  ON public.menu_items
  FOR ALL
  USING (
    (
      EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN (
            'super'::public.user_role,
            'admin'::public.user_role,
            'super_admin'::public.user_role
          )
      )
      OR 'dashboard.menu.manage' = ANY(public.get_auth_user_access_control_codes())
    )
    AND outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id = public.get_auth_user_company_id()
    )
  );

-- ─── menu_categories ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Super users can manage categories" ON public.menu_categories;

CREATE POLICY "Authorised users can manage menu categories"
  ON public.menu_categories
  FOR ALL
  USING (
    (
      EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN (
            'super'::public.user_role,
            'admin'::public.user_role,
            'super_admin'::public.user_role
          )
      )
      OR 'dashboard.menu.manage' = ANY(public.get_auth_user_access_control_codes())
    )
    AND outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id = public.get_auth_user_company_id()
    )
  );

-- ─── departments ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Super users can manage departments" ON public.departments;

CREATE POLICY "Authorised users can manage departments"
  ON public.departments
  FOR ALL
  USING (
    (
      EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN (
            'super'::public.user_role,
            'admin'::public.user_role,
            'super_admin'::public.user_role
          )
      )
      OR 'dashboard.departments.create' = ANY(public.get_auth_user_access_control_codes())
    )
    AND outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id = public.get_auth_user_company_id()
    )
  );

-- ─── addon_library ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Super users can manage addons" ON public.addon_library;

CREATE POLICY "Authorised users can manage addons"
  ON public.addon_library
  FOR ALL
  USING (
    (
      EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN (
            'super'::public.user_role,
            'admin'::public.user_role,
            'super_admin'::public.user_role
          )
      )
      OR 'dashboard.menu.manage' = ANY(public.get_auth_user_access_control_codes())
    )
    AND outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id = public.get_auth_user_company_id()
    )
  );
