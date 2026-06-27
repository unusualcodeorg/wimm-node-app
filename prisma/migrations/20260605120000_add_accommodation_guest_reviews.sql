-- Migration: Add accommodation guest reviews
-- Created: 2026-06-05
-- Description:
--   Adds a guest review system for the accommodation module.
--   When a guest is checked out, a one-time review token is generated and
--   emailed to them. The submit-guest-review edge function (public, no JWT)
--   validates the token, records the review, and serves the HTML form page.
--
--   Review categories (industry-standard hospitality feedback):
--     1. Overall experience (required, 1-5)
--     2. Room cleanliness    (optional, 1-5)
--     3. Service quality     (optional, 1-5)
--     4. Food & beverage     (optional, 1-5) — null for properties without F&B
--     5. Remarks             (optional, free text)
--
--   The accommodation_reviews_analytics view gives property owners a rolled-up
--   picture of guest sentiment keyed to outlet_id so it respects multi-outlet.

-- ----------------------------------------------------------------
-- 1. Review tokens (one per booking, generated at checkout email time)
-- ----------------------------------------------------------------

CREATE TABLE public.accommodation_review_tokens (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id  UUID         NOT NULL
                           REFERENCES public.accommodation_bookings(id)
                           ON DELETE CASCADE,
  token       UUID         NOT NULL DEFAULT gen_random_uuid(),
  expires_at  TIMESTAMPTZ  NOT NULL DEFAULT (now() + INTERVAL '30 days'),
  used_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT accommodation_review_tokens_token_key UNIQUE (token),
  CONSTRAINT accommodation_review_tokens_booking_id_key UNIQUE (booking_id)
);

-- Only the service role can touch this table (edge functions run as service role)
ALTER TABLE public.accommodation_review_tokens ENABLE ROW LEVEL SECURITY;
-- No RLS policies added → effectively service-role only

-- ----------------------------------------------------------------
-- 2. Guest reviews
-- ----------------------------------------------------------------

CREATE TABLE public.accommodation_guest_reviews (
  id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id          UUID         NOT NULL
                                   REFERENCES public.accommodation_bookings(id)
                                   ON DELETE CASCADE,
  property_id         UUID         NOT NULL
                                   REFERENCES public.accommodation_properties(id)
                                   ON DELETE CASCADE,
  client_id           UUID         REFERENCES public.clients(id)
                                   ON DELETE SET NULL,
  token_id            UUID         REFERENCES public.accommodation_review_tokens(id)
                                   ON DELETE SET NULL,

  -- Ratings (1 = Poor, 5 = Excellent)
  overall_rating      SMALLINT     NOT NULL
                                   CONSTRAINT overall_rating_range
                                   CHECK (overall_rating BETWEEN 1 AND 5),
  cleanliness_rating  SMALLINT     CONSTRAINT cleanliness_rating_range
                                   CHECK (cleanliness_rating BETWEEN 1 AND 5),
  service_rating      SMALLINT     CONSTRAINT service_rating_range
                                   CHECK (service_rating BETWEEN 1 AND 5),
  food_rating         SMALLINT     CONSTRAINT food_rating_range
                                   CHECK (food_rating BETWEEN 1 AND 5),
  remarks             TEXT,

  submitted_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

  -- One review per booking
  CONSTRAINT accommodation_guest_reviews_booking_id_key UNIQUE (booking_id)
);

-- Enable RLS; authenticated users can read reviews for their outlet properties
ALTER TABLE public.accommodation_guest_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "accommodation_guest_reviews_select"
  ON public.accommodation_guest_reviews
  FOR SELECT
  TO authenticated
  USING (
    property_id IN (
      SELECT ap.id
      FROM public.accommodation_properties ap
      JOIN public.outlets o ON o.id = ap.outlet_id
      WHERE o.company_id = get_auth_user_company_id()
    )
  );

-- ----------------------------------------------------------------
-- 3. Analytics view
-- ----------------------------------------------------------------

CREATE OR REPLACE VIEW public.accommodation_reviews_analytics WITH (security_invoker = true) AS
SELECT
  r.id,
  r.booking_id,
  r.property_id,
  r.client_id,
  r.overall_rating,
  r.cleanliness_rating,
  r.service_rating,
  r.food_rating,
  r.remarks,
  r.submitted_at,

  -- Weighted average across all rated categories (treats null as not rated)
  ROUND(
    (
      r.overall_rating::numeric
      + COALESCE(r.cleanliness_rating::numeric, 0)
      + COALESCE(r.service_rating::numeric, 0)
      + COALESCE(r.food_rating::numeric, 0)
    ) / NULLIF(
      1
      + (r.cleanliness_rating IS NOT NULL)::int
      + (r.service_rating IS NOT NULL)::int
      + (r.food_rating IS NOT NULL)::int,
      0
    ),
    2
  )                                                AS computed_avg_rating,

  -- Guest details
  TRIM(
    COALESCE(c.first_name, '') || ' ' || COALESCE(c.last_name, '')
  )                                                AS guest_name,
  c.email                                          AS guest_email,
  c.contact                                        AS guest_phone,

  -- Booking context
  b.check_in,
  b.check_out,
  (b.check_out - b.check_in)                       AS nights_stayed,
  b.source                                          AS booking_source,

  -- Property context (outlet_id allows per-outlet scoping)
  p.name                                            AS property_name,
  p.outlet_id

FROM public.accommodation_guest_reviews r
JOIN  public.accommodation_bookings   b ON b.id = r.booking_id
LEFT  JOIN public.clients             c ON c.id = r.client_id
JOIN  public.accommodation_properties p ON p.id = r.property_id;

-- Grant read access to authenticated users (row access controlled by the
-- underlying table's RLS)
GRANT SELECT ON public.accommodation_reviews_analytics TO authenticated;

-- ----------------------------------------------------------------
-- 4. Helper RPC: summary stats for the reviews dashboard
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_accommodation_reviews_stats(
  p_property_id  UUID,
  p_date_from    DATE DEFAULT NULL,
  p_date_to      DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  -- avg_computed is calculated inline to avoid joining the security_invoker view
  -- from within a SECURITY DEFINER context (auth.uid() would be undefined there).
  SELECT json_build_object(
    'total_reviews',        COUNT(*),
    'avg_overall',          ROUND(AVG(r.overall_rating)::numeric, 2),
    'avg_cleanliness',      ROUND(AVG(r.cleanliness_rating)::numeric, 2),
    'avg_service',          ROUND(AVG(r.service_rating)::numeric, 2),
    'avg_food',             ROUND(AVG(r.food_rating)::numeric, 2),
    'avg_computed',         ROUND(AVG(
      (r.overall_rating
       + COALESCE(r.cleanliness_rating, r.overall_rating)
       + COALESCE(r.service_rating,     r.overall_rating)
       + COALESCE(r.food_rating,        r.overall_rating)
      )::numeric / 4.0
    ), 2),
    'five_star_count',      COUNT(*) FILTER (WHERE r.overall_rating = 5),
    'four_star_count',      COUNT(*) FILTER (WHERE r.overall_rating = 4),
    'three_star_count',     COUNT(*) FILTER (WHERE r.overall_rating = 3),
    'two_star_count',       COUNT(*) FILTER (WHERE r.overall_rating = 2),
    'one_star_count',       COUNT(*) FILTER (WHERE r.overall_rating = 1),
    -- Response rate: reviews vs total checked-out bookings in the same period
    'total_checkouts',      (
      SELECT COUNT(*)
      FROM accommodation_bookings b2
      JOIN accommodation_properties ap2 ON ap2.id = b2.property_id
      WHERE ap2.id = p_property_id
        AND b2.status = 'checked_out'
        AND (p_date_from IS NULL OR b2.check_out >= p_date_from)
        AND (p_date_to   IS NULL OR b2.check_out <= p_date_to)
    )
  )
  INTO v_result
  FROM accommodation_guest_reviews r
  WHERE r.property_id = p_property_id
    AND (p_date_from IS NULL OR r.submitted_at::date >= p_date_from)
    AND (p_date_to   IS NULL OR r.submitted_at::date <= p_date_to);

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_accommodation_reviews_stats TO authenticated;

-- ----------------------------------------------------------------
-- 5. Monthly trend RPC (for the bar chart on the reviews dashboard)
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_accommodation_reviews_monthly_trend(
  p_property_id  UUID,
  p_months       INT DEFAULT 12
)
RETURNS TABLE(
  month_label    TEXT,
  month_start    DATE,
  five_star      BIGINT,
  four_star      BIGINT,
  three_star     BIGINT,
  two_star       BIGINT,
  one_star       BIGINT,
  total          BIGINT,
  avg_rating     NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    TO_CHAR(DATE_TRUNC('month', r.submitted_at), 'Mon YY')  AS month_label,
    DATE_TRUNC('month', r.submitted_at)::date               AS month_start,
    COUNT(*) FILTER (WHERE r.overall_rating = 5)            AS five_star,
    COUNT(*) FILTER (WHERE r.overall_rating = 4)            AS four_star,
    COUNT(*) FILTER (WHERE r.overall_rating = 3)            AS three_star,
    COUNT(*) FILTER (WHERE r.overall_rating = 2)            AS two_star,
    COUNT(*) FILTER (WHERE r.overall_rating = 1)            AS one_star,
    COUNT(*)                                                AS total,
    ROUND(AVG(r.overall_rating)::numeric, 2)               AS avg_rating
  FROM public.accommodation_guest_reviews r
  WHERE r.property_id = p_property_id
    AND r.submitted_at >= DATE_TRUNC('month', now()) - (p_months - 1) * INTERVAL '1 month'
  GROUP BY DATE_TRUNC('month', r.submitted_at)
  ORDER BY month_start;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_accommodation_reviews_monthly_trend TO authenticated;
