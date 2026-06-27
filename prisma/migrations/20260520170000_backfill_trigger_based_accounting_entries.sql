-- ============================================================
-- Migration: Backfill trigger-based accounting entries
-- Created: 2026-05-20
-- Description:
--   - Backfills missing accounting journals for historical trigger-based events
--   - Covers POS settlements, accommodation payments, accommodation revenue recognition,
--     OTA booking imports, and OTA payouts
--   - Relies on idempotent posting functions and financial_event_logs

-- ============================================================
-- 1. Backfill historical POS settlement accounting
-- ============================================================
DO $$
DECLARE
  settlement_row RECORD;
BEGIN
  FOR settlement_row IN
    SELECT os.id
    FROM public.order_settlements os
    LEFT JOIN public.financial_event_logs fel
      ON fel.reference_type = 'order_settlement'
     AND fel.reference_id = os.id
     AND fel.source_module = 'sales'::public.journal_source_module
    WHERE fel.id IS NULL
    ORDER BY os.created_at, os.id
  LOOP
    PERFORM public.post_order_settlement_accounting(settlement_row.id);
  END LOOP;
END;
$$;

-- ============================================================
-- 2. Backfill historical accommodation payment accounting
-- ============================================================
DO $$
DECLARE
  payment_row RECORD;
BEGIN
  FOR payment_row IN
    SELECT abp.id
    FROM public.accommodation_booking_payments abp
    LEFT JOIN public.financial_event_logs fel
      ON fel.reference_type = 'accommodation_booking_payment'
     AND fel.reference_id = abp.id
     AND fel.source_module = 'accommodation'::public.journal_source_module
    WHERE fel.id IS NULL
    ORDER BY abp.paid_at, abp.id
  LOOP
    PERFORM public.post_accommodation_booking_payment_accounting(payment_row.id);
  END LOOP;
END;
$$;

-- ============================================================
-- 3. Backfill historical accommodation revenue recognition
-- ============================================================
DO $$
DECLARE
  booking_row RECORD;
  stay_date DATE;
  stay_date_end DATE;
BEGIN
  FOR booking_row IN
    SELECT
      ab.id,
      ab.status,
      ab.check_in,
      ab.check_out
    FROM public.accommodation_bookings ab
    WHERE ab.status IN (
      'checked_in'::public.accommodation_booking_status,
      'checked_out'::public.accommodation_booking_status
    )
      AND ab.check_out > ab.check_in
    ORDER BY ab.check_in, ab.id
  LOOP
    IF booking_row.status = 'checked_out'::public.accommodation_booking_status THEN
      stay_date_end := booking_row.check_out - 1;
    ELSE
      stay_date_end := LEAST(booking_row.check_out - 1, CURRENT_DATE - 1);
    END IF;

    IF stay_date_end < booking_row.check_in THEN
      CONTINUE;
    END IF;

    stay_date := booking_row.check_in;

    WHILE stay_date <= stay_date_end LOOP
      PERFORM public.post_accommodation_booking_revenue_recognition(
        booking_row.id,
        stay_date,
        'backfill'
      );
      stay_date := stay_date + 1;
    END LOOP;
  END LOOP;
END;
$$;

-- ============================================================
-- 4. Backfill OTA booking import accounting
-- ============================================================
DO $$
DECLARE
  booking_row RECORD;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'accommodation_bookings'
  ) THEN
    FOR booking_row IN
      SELECT ab.id
      FROM public.accommodation_bookings ab
      LEFT JOIN public.financial_event_logs fel
        ON fel.reference_type = 'accommodation_booking'
       AND fel.reference_id = ab.id
       AND fel.source_module = 'booking_com'::public.journal_source_module
       AND fel.event_type = 'ota_booking_imported'
      WHERE fel.id IS NULL
        AND lower(COALESCE(ab.source, '')) IN ('booking.com', 'booking_com', 'bookingcom')
        AND COALESCE(ab.ota_collects_payment, FALSE) = TRUE
      ORDER BY ab.created_at, ab.id
    LOOP
      PERFORM public.post_ota_booking_import_accounting(booking_row.id);
    END LOOP;
  END IF;
END;
$$;

-- ============================================================
-- 5. Backfill OTA payout accounting
-- ============================================================
DO $$
DECLARE
  payout_row RECORD;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'accommodation_ota_payouts'
  ) THEN
    FOR payout_row IN
      SELECT aop.id
      FROM public.accommodation_ota_payouts aop
      LEFT JOIN public.financial_event_logs fel
        ON fel.reference_type = 'accommodation_ota_payout'
       AND fel.reference_id = aop.id
       AND fel.source_module = 'booking_com'::public.journal_source_module
       AND fel.event_type = 'ota_payout_received'
      WHERE fel.id IS NULL
      ORDER BY aop.received_at, aop.id
    LOOP
      PERFORM public.post_accommodation_ota_payout_accounting(payout_row.id);
    END LOOP;
  END IF;
END;
$$;
