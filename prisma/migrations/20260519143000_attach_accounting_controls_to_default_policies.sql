-- ============================================================
-- Migration: Attach accounting controls to default policies
-- ============================================================

WITH role_control_targets AS (
  SELECT
    'manager'::public.user_role AS role,
    unnest(
      ARRAY[
        'accounting.view_accounts',
        'accounting.view_journals',
        'accounting.view_reports'
      ]::text[]
    ) AS control_code

  UNION ALL

  SELECT
    'accountant'::public.user_role AS role,
    unnest(
      ARRAY[
        'accounting.view_accounts',
        'accounting.manage_accounts',
        'accounting.view_journals',
        'accounting.post_journals',
        'accounting.reverse_journals',
        'accounting.close_periods',
        'accounting.view_reports',
        'accounting.export_reports',
        'accounting.manage_tax_rates',
        'accounting.manage_payment_mappings'
      ]::text[]
    ) AS control_code
),
policy_targets AS (
  SELECT DISTINCT
    ap.id AS policy_id,
    ap.created_by AS added_by,
    rpa.role
  FROM public.role_policy_assignments rpa
  JOIN public.access_policies ap
    ON ap.id = rpa.policy_id
   AND ap.company_id = rpa.company_id
  WHERE rpa.role IN ('manager'::public.user_role, 'accountant'::public.user_role)
),
policy_control_targets AS (
  SELECT
    pt.policy_id,
    ac.id AS access_control_id,
    pt.added_by
  FROM policy_targets pt
  JOIN role_control_targets rct
    ON rct.role = pt.role
  JOIN public.access_controls ac
    ON ac.code = rct.control_code
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
