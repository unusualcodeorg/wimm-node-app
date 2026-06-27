-- ============================================================
-- Migration: Create business dashboard views
-- Created: 2026-05-20
-- Description:
--   - Creates aggregate views for accounting dashboard metrics, charts, and cards
--   - Supports period filtering by exposing daily grain views
--   - Includes financial, revenue mix, cash balance, recent journal, and guest-origin views

-- ============================================================
-- 1. Daily financial metrics
-- ============================================================
DROP VIEW IF EXISTS public.business_dashboard_financial_daily_view;

CREATE VIEW public.business_dashboard_financial_daily_view
WITH (security_invoker = true) AS
SELECT
  je.company_id,
  je.outlet_id,
  je.entry_date AS metric_date,
  COUNT(DISTINCT je.id)::INT AS journal_count,
  COUNT(jel.id)::INT AS line_count,
  ROUND(
    SUM(
      CASE
        WHEN a.type = 'revenue'::public.account_type
          THEN jel.credit - jel.debit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS income_amount,
  ROUND(
    SUM(
      CASE
        WHEN a.type = 'expense'::public.account_type
          THEN jel.debit - jel.credit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS expense_amount,
  ROUND(
    SUM(
      CASE
        WHEN a.type = 'cogs'::public.account_type
          THEN jel.debit - jel.credit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS cogs_amount,
  ROUND(
    SUM(
      CASE
        WHEN a.type = 'revenue'::public.account_type
          THEN jel.credit - jel.debit
        WHEN a.type IN ('expense'::public.account_type, 'cogs'::public.account_type)
          THEN -(jel.debit - jel.credit)
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS net_income_amount,
  ROUND(
    SUM(
      CASE
        WHEN a.subtype IN ('cash', 'bank', 'cash_equivalent', 'cash_clearing')
          THEN jel.debit - jel.credit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS net_cash_movement,
  ROUND(
    SUM(
      CASE
        WHEN a.subtype IN ('cash', 'bank', 'cash_equivalent', 'cash_clearing')
             AND jel.debit > 0
          THEN jel.debit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS cash_inflow_amount,
  ROUND(
    SUM(
      CASE
        WHEN a.subtype IN ('cash', 'bank', 'cash_equivalent', 'cash_clearing')
             AND jel.credit > 0
          THEN jel.credit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS cash_outflow_amount,
  ROUND(
    SUM(
      CASE
        WHEN a.type = 'revenue'::public.account_type
             AND je.source_module = 'sales'::public.journal_source_module
          THEN jel.credit - jel.debit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS pos_revenue_amount,
  ROUND(
    SUM(
      CASE
        WHEN a.type = 'revenue'::public.account_type
             AND je.source_module IN (
               'accommodation'::public.journal_source_module,
               'booking_com'::public.journal_source_module
             )
          THEN jel.credit - jel.debit
        ELSE 0::NUMERIC
      END
    ),
    2
  ) AS accommodation_revenue_amount
FROM public.journal_entries je
JOIN public.journal_entry_lines jel
  ON jel.journal_entry_id = je.id
JOIN public.accounts a
  ON a.id = jel.account_id
WHERE je.status IN (
  'posted'::public.journal_entry_status,
  'reversed'::public.journal_entry_status
)
GROUP BY
  je.company_id,
  je.outlet_id,
  je.entry_date;

GRANT SELECT ON public.business_dashboard_financial_daily_view TO authenticated;

-- ============================================================
-- 2. Daily cash balance trend
-- ============================================================
DROP VIEW IF EXISTS public.business_dashboard_cash_balance_daily_view;

CREATE VIEW public.business_dashboard_cash_balance_daily_view
WITH (security_invoker = true) AS
WITH daily_cash AS (
  SELECT
    je.company_id,
    je.outlet_id,
    je.entry_date AS metric_date,
    ROUND(
      SUM(
        CASE
          WHEN a.subtype IN ('cash', 'bank', 'cash_equivalent', 'cash_clearing')
            THEN jel.debit - jel.credit
          ELSE 0::NUMERIC
        END
      ),
      2
    ) AS daily_net_cash_movement
  FROM public.journal_entries je
  JOIN public.journal_entry_lines jel
    ON jel.journal_entry_id = je.id
  JOIN public.accounts a
    ON a.id = jel.account_id
  WHERE je.status IN (
    'posted'::public.journal_entry_status,
    'reversed'::public.journal_entry_status
  )
  GROUP BY je.company_id, je.outlet_id, je.entry_date
)
SELECT
  dc.company_id,
  dc.outlet_id,
  dc.metric_date,
  COALESCE(
    SUM(dc.daily_net_cash_movement) OVER (
      PARTITION BY dc.company_id, dc.outlet_id
      ORDER BY dc.metric_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ),
    0::NUMERIC
  ) AS opening_cash_balance,
  dc.daily_net_cash_movement,
  ROUND(
    SUM(dc.daily_net_cash_movement) OVER (
      PARTITION BY dc.company_id, dc.outlet_id
      ORDER BY dc.metric_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ),
    2
  ) AS closing_cash_balance
FROM daily_cash dc;

GRANT SELECT ON public.business_dashboard_cash_balance_daily_view TO authenticated;

-- ============================================================
-- 3. Revenue growth / module mix
-- ============================================================
DROP VIEW IF EXISTS public.business_dashboard_revenue_growth_daily_view;

CREATE VIEW public.business_dashboard_revenue_growth_daily_view
WITH (security_invoker = true) AS
WITH pos_daily AS (
  SELECT
    outl.company_id,
    os.order_id,
    o.outlet_id,
    o.date AS metric_date,
    ROUND(SUM(os.amount), 2) AS pos_collected_amount,
    COUNT(os.id)::INT AS settlement_count
  FROM public.order_settlements os
  JOIN public.orders o
    ON o.id = os.order_id
  JOIN public.outlets outl
    ON outl.id = o.outlet_id
  GROUP BY outl.company_id, os.order_id, o.outlet_id, o.date
),
pos_daily_agg AS (
  SELECT
    company_id,
    outlet_id,
    metric_date,
    ROUND(SUM(pos_collected_amount), 2) AS pos_collected_amount,
    COUNT(order_id)::INT AS settled_orders_count,
    SUM(settlement_count)::INT AS settlement_count
  FROM pos_daily
  GROUP BY company_id, outlet_id, metric_date
),
accommodation_daily AS (
  SELECT
    o.company_id,
    abr.outlet_id,
    abr.stay_date AS metric_date,
    ROUND(SUM(abr.daily_revenue), 2) AS accommodation_revenue_amount,
    COUNT(DISTINCT abr.booking_id)::INT AS active_booking_count
  FROM public.accommodation_booking_daily_revenue abr
  JOIN public.outlets o
    ON o.id = abr.outlet_id
  GROUP BY o.company_id, abr.outlet_id, abr.stay_date
),
combined_dates AS (
  SELECT company_id, outlet_id, metric_date FROM pos_daily_agg
  UNION
  SELECT company_id, outlet_id, metric_date FROM accommodation_daily
)
SELECT
  cd.company_id,
  cd.outlet_id,
  cd.metric_date,
  COALESCE(pda.pos_collected_amount, 0::NUMERIC) AS pos_collected_amount,
  COALESCE(ad.accommodation_revenue_amount, 0::NUMERIC) AS accommodation_revenue_amount,
  ROUND(
    COALESCE(pda.pos_collected_amount, 0::NUMERIC)
    + COALESCE(ad.accommodation_revenue_amount, 0::NUMERIC),
    2
  ) AS total_revenue_amount,
  COALESCE(pda.settled_orders_count, 0) AS settled_orders_count,
  COALESCE(pda.settlement_count, 0) AS settlement_count,
  COALESCE(ad.active_booking_count, 0) AS active_booking_count
FROM combined_dates cd
LEFT JOIN pos_daily_agg pda
  ON pda.company_id = cd.company_id
 AND pda.outlet_id IS NOT DISTINCT FROM cd.outlet_id
 AND pda.metric_date = cd.metric_date
LEFT JOIN accommodation_daily ad
  ON ad.company_id = cd.company_id
 AND ad.outlet_id IS NOT DISTINCT FROM cd.outlet_id
 AND ad.metric_date = cd.metric_date;

GRANT SELECT ON public.business_dashboard_revenue_growth_daily_view TO authenticated;

-- ============================================================
-- 4. Recent journals preview
-- ============================================================
DROP VIEW IF EXISTS public.business_dashboard_recent_journals_view;

CREATE VIEW public.business_dashboard_recent_journals_view
WITH (security_invoker = true) AS
SELECT
  je.company_id,
  je.outlet_id,
  je.id AS journal_entry_id,
  je.created_at,
  je.entry_date,
  je.source_module,
  je.reference_type,
  je.reference_id,
  je.memo,
  ROUND(COALESCE(SUM(jel.debit), 0), 2) AS total_debit,
  ROUND(COALESCE(SUM(jel.credit), 0), 2) AS total_credit,
  ROUND(GREATEST(COALESCE(SUM(jel.debit), 0), COALESCE(SUM(jel.credit), 0)), 2) AS amount
FROM public.journal_entries je
JOIN public.journal_entry_lines jel
  ON jel.journal_entry_id = je.id
WHERE je.status IN (
  'posted'::public.journal_entry_status,
  'reversed'::public.journal_entry_status
)
GROUP BY
  je.company_id,
  je.outlet_id,
  je.id,
  je.created_at,
  je.entry_date,
  je.source_module,
  je.reference_type,
  je.reference_id,
  je.memo;

GRANT SELECT ON public.business_dashboard_recent_journals_view TO authenticated;

-- ============================================================
-- 5. Accommodation guest origins
-- ============================================================
DROP VIEW IF EXISTS public.business_dashboard_guest_origins_view;

CREATE VIEW public.business_dashboard_guest_origins_view
WITH (security_invoker = true) AS
SELECT
  o.company_id,
  ap.outlet_id,
  COALESCE(ab.guest_country_id, c.country_id) AS country_id,
  co.name AS country_name,
  co.iso_code AS country_iso_code,
  COUNT(DISTINCT ab.id)::INT AS bookings_count,
  ROUND(COALESCE(SUM(ab.total_amount), 0), 2) AS total_revenue,
  ROUND(COALESCE(SUM(ab.amount_paid), 0), 2) AS total_paid,
  MAX(ab.check_in) AS last_check_in
FROM public.accommodation_bookings ab
JOIN public.accommodation_properties ap
  ON ap.id = ab.property_id
JOIN public.outlets o
  ON o.id = ap.outlet_id
LEFT JOIN public.clients c
  ON c.id = ab.client_id
LEFT JOIN public.countries co
  ON co.id = COALESCE(ab.guest_country_id, c.country_id)
WHERE ab.status NOT IN (
  'cancelled'::public.accommodation_booking_status,
  'no_show'::public.accommodation_booking_status
)
GROUP BY
  o.company_id,
  ap.outlet_id,
  COALESCE(ab.guest_country_id, c.country_id),
  co.name,
  co.iso_code;

GRANT SELECT ON public.business_dashboard_guest_origins_view TO authenticated;
