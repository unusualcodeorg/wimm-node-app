-- Migration: Attach inventory controls to default policies
-- Phase 4: Inventory Access Controls
--
-- manager: read-only access across all inventory sub-modules + invoice posting
-- accountant: page access + view-only on invoices, payments, and reports

WITH role_control_targets AS (
  SELECT
    'manager'::public.user_role AS role,
    unnest(
      ARRAY[
        'inventory.page_access',
        'inventory.items_view',
        'inventory.items_manage',
        'inventory.suppliers_view',
        'inventory.suppliers_manage',
        'inventory.invoices_view',
        'inventory.invoices_manage',
        'inventory.invoices_post',
        'inventory.payments_view',
        'inventory.payments_record',
        'inventory.stock_view',
        'inventory.stock_adjust',
        'inventory.stock_transfer',
        'inventory.recipes_view',
        'inventory.recipes_manage',
        'inventory.reports_view'
      ]::text[]
    ) AS control_code

  UNION ALL

  SELECT
    'accountant'::public.user_role AS role,
    unnest(
      ARRAY[
        'inventory.page_access',
        'inventory.invoices_view',
        'inventory.payments_view',
        'inventory.stock_view',
        'inventory.reports_view'
      ]::text[]
    ) AS control_code
),
policy_targets AS (
  SELECT DISTINCT
    ap.id    AS policy_id,
    ap.created_by AS added_by,
    rpa.role
  FROM public.role_policy_assignments rpa
  JOIN public.access_policies ap
    ON ap.id         = rpa.policy_id
   AND ap.company_id = rpa.company_id
  WHERE rpa.role IN ('manager'::public.user_role, 'accountant'::public.user_role)
),
policy_control_targets AS (
  SELECT
    pt.policy_id,
    ac.id    AS access_control_id,
    pt.added_by
  FROM policy_targets pt
  JOIN role_control_targets rct ON rct.role = pt.role
  JOIN public.access_controls ac ON ac.code  = rct.control_code
)
INSERT INTO public.access_policy_controls (
  policy_id,
  access_control_id,
  added_by
)
SELECT
  pct.policy_id,
  pct.access_control_id,
  pct.added_by
FROM policy_control_targets pct
ON CONFLICT (policy_id, access_control_id) DO NOTHING;
