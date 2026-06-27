-- Migration: Accommodation booking payments table + dashboard stats RPC
-- Depends on: 20260505120000_create_accommodation_schema.sql
--             20260507140000_add_pending_booking_status.sql  (pending enum value)
--             20260213160000_create_sales_order_flow_foundation.sql (payment_methods)

-- ============================================================
-- 0. Set column default to 'pending' (MUST run after migration
--    20260507140000 has committed the new enum value)
-- ============================================================
ALTER TABLE public.accommodation_bookings
  ALTER COLUMN status SET DEFAULT 'pending';

-- ============================================================
-- 1. accommodation_booking_payments
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_booking_payments (
  id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id        UUID         NOT NULL REFERENCES public.accommodation_bookings(id) ON DELETE CASCADE,
  amount            NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  payment_method_id INTEGER      NOT NULL REFERENCES public.payment_methods(id),
  notes             TEXT,
  paid_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
  recorded_by       UUID         REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_accommodation_booking_payments_booking_id
  ON public.accommodation_booking_payments(booking_id);

-- ---- RLS ----
ALTER TABLE public.accommodation_booking_payments ENABLE ROW LEVEL SECURITY;

-- Authenticated users can view payments for bookings they can see
-- (leverages the same company-scoping as the bookings table)
DROP POLICY IF EXISTS "Users can view booking payments" ON public.accommodation_booking_payments;
CREATE POLICY "Users can view booking payments"
  ON public.accommodation_booking_payments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.accommodation_bookings ab
      JOIN public.accommodation_properties ap ON ap.id = ab.property_id
      JOIN public.outlets o ON o.id = ap.outlet_id
      JOIN public.users u ON u.outlet_id = o.id OR o.company_id = (
        SELECT company_id FROM public.outlets WHERE id = u.outlet_id LIMIT 1
      )
      WHERE ab.id = accommodation_booking_payments.booking_id
        AND u.id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can insert booking payments" ON public.accommodation_booking_payments;
CREATE POLICY "Users can insert booking payments"
  ON public.accommodation_booking_payments FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.accommodation_bookings ab
      JOIN public.accommodation_properties ap ON ap.id = ab.property_id
      JOIN public.outlets o ON o.id = ap.outlet_id
      JOIN public.users u ON u.outlet_id = o.id OR o.company_id = (
        SELECT company_id FROM public.outlets WHERE id = u.outlet_id LIMIT 1
      )
      WHERE ab.id = booking_id
        AND u.id = auth.uid()
    )
  );

GRANT SELECT, INSERT ON public.accommodation_booking_payments TO authenticated;

-- ============================================================
-- 2. Trigger: keep accommodation_bookings.amount_paid in sync
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_accommodation_booking_amount_paid()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking_id UUID;
BEGIN
  v_booking_id := COALESCE(NEW.booking_id, OLD.booking_id);

  UPDATE public.accommodation_bookings
  SET amount_paid = (
    SELECT COALESCE(SUM(amount), 0)
    FROM public.accommodation_booking_payments
    WHERE booking_id = v_booking_id
  )
  WHERE id = v_booking_id;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_accommodation_booking_amount_paid
  ON public.accommodation_booking_payments;

CREATE TRIGGER trg_sync_accommodation_booking_amount_paid
  AFTER INSERT OR UPDATE OR DELETE
  ON public.accommodation_booking_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_accommodation_booking_amount_paid();

-- ============================================================
-- 3. Dashboard stats RPC
--    Returns aggregate KPIs for a property + date window.
--    date_from / date_to are inclusive, applied to check_in date.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_accommodation_dashboard_stats(
  p_property_id UUID,
  p_date_from   DATE DEFAULT (CURRENT_DATE - INTERVAL '30 days')::DATE,
  p_date_to     DATE DEFAULT CURRENT_DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stats       JSONB;
  v_sources     JSONB;
  v_countries   JSONB;
BEGIN
  -- Core booking KPIs
  SELECT jsonb_build_object(
    'total_bookings',
      COUNT(*) FILTER (WHERE status NOT IN ('cancelled')),
    'pending_bookings',
      COUNT(*) FILTER (WHERE status = 'pending'),
    'confirmed_bookings',
      COUNT(*) FILTER (WHERE status = 'confirmed'),
    'checked_in',
      COUNT(*) FILTER (WHERE status = 'checked_in'),
    'checked_out',
      COUNT(*) FILTER (WHERE status = 'checked_out'),
    'cancelled',
      COUNT(*) FILTER (WHERE status = 'cancelled'),
    'no_show',
      COUNT(*) FILTER (WHERE status = 'no_show'),
    'total_revenue',
      COALESCE(SUM(total_amount) FILTER (
        WHERE status NOT IN ('cancelled', 'no_show')
      ), 0),
    'total_paid',
      COALESCE(SUM(amount_paid) FILTER (
        WHERE status NOT IN ('cancelled', 'no_show')
      ), 0),
    'avg_nights',
      COALESCE(ROUND(AVG(
        EXTRACT(DAY FROM (check_out::TIMESTAMP - check_in::TIMESTAMP))
      ) FILTER (
        WHERE status NOT IN ('cancelled', 'no_show')
      ), 1), 0)
  )
  INTO v_stats
  FROM public.accommodation_bookings
  WHERE property_id = p_property_id
    AND check_in BETWEEN p_date_from AND p_date_to;

  -- Bookings by source (top 8)
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'source_name', COALESCE(bs.name, ab.source, 'Direct'),
        'booking_count', src_counts.cnt,
        'revenue', src_counts.rev
      )
      ORDER BY src_counts.cnt DESC
    ),
    '[]'::jsonb
  )
  INTO v_sources
  FROM (
    SELECT
      source_id,
      source,
      COUNT(*)            AS cnt,
      SUM(total_amount)   AS rev
    FROM public.accommodation_bookings
    WHERE property_id = p_property_id
      AND check_in BETWEEN p_date_from AND p_date_to
      AND status NOT IN ('cancelled', 'no_show')
    GROUP BY source_id, source
    LIMIT 8
  ) src_counts
  LEFT JOIN public.accommodation_booking_sources bs ON bs.id = src_counts.source_id
  LEFT JOIN public.accommodation_bookings ab
    ON ab.property_id = p_property_id AND ab.source_id = src_counts.source_id LIMIT 1;

  -- Top guest countries (top 10)
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'country_name', COALESCE(c.name, 'Unknown'),
        'count', cc.cnt
      )
      ORDER BY cc.cnt DESC
    ),
    '[]'::jsonb
  )
  INTO v_countries
  FROM (
    SELECT
      guest_country_id,
      COUNT(*) AS cnt
    FROM public.accommodation_bookings
    WHERE property_id = p_property_id
      AND check_in BETWEEN p_date_from AND p_date_to
      AND status NOT IN ('cancelled', 'no_show')
      AND guest_country_id IS NOT NULL
    GROUP BY guest_country_id
    LIMIT 10
  ) cc
  LEFT JOIN public.countries c ON c.id = cc.guest_country_id;

  RETURN v_stats
    || jsonb_build_object('bookings_by_source', v_sources)
    || jsonb_build_object('top_countries', v_countries);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_accommodation_dashboard_stats(UUID, DATE, DATE)
  TO authenticated;
