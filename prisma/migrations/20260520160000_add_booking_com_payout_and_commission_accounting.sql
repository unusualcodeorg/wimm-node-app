-- ============================================================
-- Migration: Add Booking.com payout and commission accounting
-- Created: 2026-05-20
-- Description:
--   - Extends accommodation OTA mapping fields for Booking.com
--   - Adds OTA payout source tables and reconciliation support
--   - Posts OTA-collected booking imports to receivables/unearned revenue
--   - Posts Booking.com payout receipts and commission expense

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. OTA schema extensions
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'ota_platform'
  ) THEN
    CREATE TYPE public.ota_platform AS ENUM (
      'booking_com',
      'airbnb'
    );
  END IF;
END;
$$;

ALTER TABLE public.accommodation_properties
  ADD COLUMN IF NOT EXISTS booking_com_hotel_id TEXT,
  ADD COLUMN IF NOT EXISTS booking_com_connection_status TEXT,
  ADD COLUMN IF NOT EXISTS booking_com_last_sync_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_accommodation_properties_booking_com_hotel_id_unique
  ON public.accommodation_properties(booking_com_hotel_id)
  WHERE booking_com_hotel_id IS NOT NULL;

ALTER TABLE public.accommodation_room_types
  ADD COLUMN IF NOT EXISTS external_room_type_id TEXT,
  ADD COLUMN IF NOT EXISTS source TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_accommodation_room_types_property_source_external_unique
  ON public.accommodation_room_types(property_id, lower(COALESCE(source, '')), lower(COALESCE(external_room_type_id, '')))
  WHERE external_room_type_id IS NOT NULL;

ALTER TABLE public.accommodation_rate_plans
  ADD COLUMN IF NOT EXISTS external_rate_plan_id TEXT,
  ADD COLUMN IF NOT EXISTS source TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_accommodation_rate_plans_property_source_external_unique
  ON public.accommodation_rate_plans(property_id, lower(COALESCE(source, '')), lower(COALESCE(external_rate_plan_id, '')))
  WHERE external_rate_plan_id IS NOT NULL;

ALTER TABLE public.accommodation_bookings
  ADD COLUMN IF NOT EXISTS ota_collects_payment BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS ota_gross_amount NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS ota_commission_amount NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS ota_net_amount NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS ota_last_sync_log_id UUID;

ALTER TABLE public.accommodation_bookings
  DROP CONSTRAINT IF EXISTS accommodation_bookings_ota_sync_log_fk;

ALTER TABLE public.accommodation_bookings
  ADD CONSTRAINT accommodation_bookings_ota_sync_log_fk
  FOREIGN KEY (ota_last_sync_log_id)
  REFERENCES public.accommodation_sync_logs(id)
  ON DELETE SET NULL;

ALTER TABLE public.accommodation_bookings
  DROP CONSTRAINT IF EXISTS accommodation_bookings_ota_amounts_non_negative;

ALTER TABLE public.accommodation_bookings
  ADD CONSTRAINT accommodation_bookings_ota_amounts_non_negative CHECK (
    COALESCE(ota_gross_amount, 0) >= 0
    AND COALESCE(ota_commission_amount, 0) >= 0
    AND COALESCE(ota_net_amount, 0) >= 0
  );

-- ============================================================
-- 2. OTA payout source tables
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_ota_payouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id UUID NOT NULL REFERENCES public.accommodation_properties(id) ON DELETE CASCADE,
  platform public.ota_platform NOT NULL,
  payout_reference TEXT NOT NULL,
  gross_amount NUMERIC(12, 2) NOT NULL CHECK (gross_amount >= 0),
  commission_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (commission_amount >= 0),
  net_amount NUMERIC(12, 2) NOT NULL CHECK (net_amount >= 0),
  currency TEXT NOT NULL DEFAULT 'UGX',
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sync_log_id UUID REFERENCES public.accommodation_sync_logs(id) ON DELETE SET NULL,
  raw_payload JSONB,
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accommodation_ota_payouts_reference_not_blank CHECK (length(btrim(payout_reference)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_accommodation_ota_payouts_property_platform_reference_unique
  ON public.accommodation_ota_payouts(property_id, platform, payout_reference);

CREATE INDEX IF NOT EXISTS idx_accommodation_ota_payouts_property_received_at
  ON public.accommodation_ota_payouts(property_id, received_at DESC);

DROP TRIGGER IF EXISTS update_accommodation_ota_payouts_updated_at
  ON public.accommodation_ota_payouts;
CREATE TRIGGER update_accommodation_ota_payouts_updated_at
  BEFORE UPDATE ON public.accommodation_ota_payouts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.accommodation_ota_payout_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_id UUID NOT NULL REFERENCES public.accommodation_ota_payouts(id) ON DELETE CASCADE,
  booking_id UUID NOT NULL REFERENCES public.accommodation_bookings(id) ON DELETE CASCADE,
  gross_amount NUMERIC(12, 2) NOT NULL CHECK (gross_amount >= 0),
  commission_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (commission_amount >= 0),
  net_amount NUMERIC(12, 2) NOT NULL CHECK (net_amount >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accommodation_ota_payout_bookings_unique UNIQUE (payout_id, booking_id)
);

CREATE INDEX IF NOT EXISTS idx_accommodation_ota_payout_bookings_booking_id
  ON public.accommodation_ota_payout_bookings(booking_id);

CREATE OR REPLACE FUNCTION public.validate_accommodation_ota_payout_booking_link()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_payout_property_id UUID;
  v_booking_property_id UUID;
BEGIN
  SELECT property_id
  INTO v_payout_property_id
  FROM public.accommodation_ota_payouts
  WHERE id = NEW.payout_id;

  SELECT property_id
  INTO v_booking_property_id
  FROM public.accommodation_bookings
  WHERE id = NEW.booking_id;

  IF v_payout_property_id IS NULL OR v_booking_property_id IS NULL THEN
    RAISE EXCEPTION 'Invalid OTA payout or booking link.';
  END IF;

  IF v_payout_property_id <> v_booking_property_id THEN
    RAISE EXCEPTION 'OTA payout bookings must belong to the same property as the payout.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_accommodation_ota_payout_booking_link_before_write
  ON public.accommodation_ota_payout_bookings;
CREATE TRIGGER validate_accommodation_ota_payout_booking_link_before_write
  BEFORE INSERT OR UPDATE ON public.accommodation_ota_payout_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_accommodation_ota_payout_booking_link();

-- ============================================================
-- 3. OTA payout RLS
-- ============================================================
ALTER TABLE public.accommodation_ota_payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_ota_payout_bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view ota payouts" ON public.accommodation_ota_payouts;
CREATE POLICY "Users can view ota payouts"
  ON public.accommodation_ota_payouts FOR SELECT
  TO authenticated
  USING (public.auth_user_can_access_accommodation_property(property_id));

DROP POLICY IF EXISTS "Users can insert ota payouts" ON public.accommodation_ota_payouts;
CREATE POLICY "Users can insert ota payouts"
  ON public.accommodation_ota_payouts FOR INSERT
  TO authenticated
  WITH CHECK (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Users can update ota payouts" ON public.accommodation_ota_payouts;
CREATE POLICY "Users can update ota payouts"
  ON public.accommodation_ota_payouts FOR UPDATE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  )
  WITH CHECK (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Users can delete ota payouts" ON public.accommodation_ota_payouts;
CREATE POLICY "Users can delete ota payouts"
  ON public.accommodation_ota_payouts FOR DELETE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Users can view ota payout bookings" ON public.accommodation_ota_payout_bookings;
CREATE POLICY "Users can view ota payout bookings"
  ON public.accommodation_ota_payout_bookings FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.accommodation_ota_payouts aop
      WHERE aop.id = payout_id
        AND public.auth_user_can_access_accommodation_property(aop.property_id)
    )
  );

DROP POLICY IF EXISTS "Users can insert ota payout bookings" ON public.accommodation_ota_payout_bookings;
CREATE POLICY "Users can insert ota payout bookings"
  ON public.accommodation_ota_payout_bookings FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.accommodation_ota_payouts aop
      WHERE aop.id = payout_id
        AND public.auth_user_can_access_accommodation_property(aop.property_id)
        AND public.auth_user_can_manage_accommodation()
    )
  );

DROP POLICY IF EXISTS "Users can update ota payout bookings" ON public.accommodation_ota_payout_bookings;
CREATE POLICY "Users can update ota payout bookings"
  ON public.accommodation_ota_payout_bookings FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.accommodation_ota_payouts aop
      WHERE aop.id = payout_id
        AND public.auth_user_can_access_accommodation_property(aop.property_id)
        AND public.auth_user_can_manage_accommodation()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.accommodation_ota_payouts aop
      WHERE aop.id = payout_id
        AND public.auth_user_can_access_accommodation_property(aop.property_id)
        AND public.auth_user_can_manage_accommodation()
    )
  );

DROP POLICY IF EXISTS "Users can delete ota payout bookings" ON public.accommodation_ota_payout_bookings;
CREATE POLICY "Users can delete ota payout bookings"
  ON public.accommodation_ota_payout_bookings FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.accommodation_ota_payouts aop
      WHERE aop.id = payout_id
        AND public.auth_user_can_access_accommodation_property(aop.property_id)
        AND public.auth_user_can_manage_accommodation()
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.accommodation_ota_payouts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.accommodation_ota_payout_bookings TO authenticated;

-- ============================================================
-- 4. OTA account resolution helpers
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_ota_receivable_account(
  p_company_id BIGINT,
  p_platform public.ota_platform
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.get_company_account_id_by_code(p_company_id, '1130');
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_ota_receivable_account(BIGINT, public.ota_platform) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_ota_commission_expense_account(
  p_company_id BIGINT,
  p_platform public.ota_platform
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN CASE p_platform
    WHEN 'booking_com'::public.ota_platform THEN public.get_company_account_id_by_code(p_company_id, '6300')
    WHEN 'airbnb'::public.ota_platform THEN public.get_company_account_id_by_code(p_company_id, '6310')
    ELSE NULL
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_ota_commission_expense_account(BIGINT, public.ota_platform) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_ota_payout_bank_account(
  p_company_id BIGINT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.get_company_account_id_by_code(p_company_id, '1010');
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_ota_payout_bank_account(BIGINT) TO authenticated;

CREATE OR REPLACE FUNCTION public.normalize_ota_platform_from_booking_source(
  p_source TEXT
)
RETURNS public.ota_platform
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_source TEXT;
BEGIN
  v_source := lower(btrim(COALESCE(p_source, '')));

  IF v_source IN ('booking.com', 'booking_com', 'bookingcom') THEN
    RETURN 'booking_com'::public.ota_platform;
  END IF;

  IF v_source = 'airbnb' THEN
    RETURN 'airbnb'::public.ota_platform;
  END IF;

  RETURN NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.normalize_ota_platform_from_booking_source(TEXT) TO authenticated;

-- ============================================================
-- 5. OTA-collected booking import posting
-- ============================================================
CREATE OR REPLACE FUNCTION public.post_ota_booking_import_accounting(
  p_booking_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_booking RECORD;
  v_platform public.ota_platform;
  v_event_log_id UUID;
  v_existing_event RECORD;
  v_receivable_account_id UUID;
  v_unearned_account_id UUID;
  v_journal_entry_id UUID;
  v_gross_amount NUMERIC(12, 2);
BEGIN
  SELECT
    ab.id,
    ab.status,
    ab.source,
    ab.external_id,
    ab.check_in,
    ab.check_out,
    ab.total_amount,
    ab.ota_collects_payment,
    ab.ota_gross_amount,
    ab.ota_commission_amount,
    ab.ota_net_amount,
    ab.created_by,
    ab.ota_last_sync_log_id,
    ap.id AS property_id,
    ap.name AS property_name,
    ap.outlet_id,
    o.company_id
  INTO v_booking
  FROM public.accommodation_bookings ab
  JOIN public.accommodation_properties ap
    ON ap.id = ab.property_id
  JOIN public.outlets o
    ON o.id = ap.outlet_id
  WHERE ab.id = p_booking_id
  LIMIT 1;

  IF v_booking.id IS NULL THEN
    RAISE EXCEPTION 'Accommodation booking % does not exist', p_booking_id;
  END IF;

  v_platform := public.normalize_ota_platform_from_booking_source(v_booking.source);

  IF v_platform IS NULL OR v_platform <> 'booking_com'::public.ota_platform THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'booking_id', v_booking.id,
      'reason', 'not_booking_com'
    );
  END IF;

  IF v_booking.status IN (
    'cancelled'::public.accommodation_booking_status,
    'no_show'::public.accommodation_booking_status
  ) THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'booking_id', v_booking.id,
      'reason', 'cancelled_or_no_show'
    );
  END IF;

  IF COALESCE(v_booking.ota_collects_payment, FALSE) = FALSE THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'booking_id', v_booking.id,
      'reason', 'ota_does_not_collect_payment'
    );
  END IF;

  v_gross_amount := COALESCE(v_booking.ota_gross_amount, v_booking.total_amount, 0)::NUMERIC(12, 2);

  IF v_gross_amount <= 0 THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'booking_id', v_booking.id,
      'reason', 'zero_gross_amount'
    );
  END IF;

  INSERT INTO public.financial_event_logs (
    company_id,
    outlet_id,
    event_type,
    source_module,
    reference_type,
    reference_id,
    idempotency_key,
    status,
    payload,
    created_by
  )
  VALUES (
    v_booking.company_id,
    v_booking.outlet_id,
    'ota_booking_imported',
    'booking_com'::public.journal_source_module,
    'accommodation_booking',
    v_booking.id,
    'booking_com:booking_import:' || v_booking.id::text,
    'pending'::public.financial_event_status,
    jsonb_build_object(
      'booking_id', v_booking.id,
      'property_id', v_booking.property_id,
      'property_name', v_booking.property_name,
      'external_id', v_booking.external_id,
      'platform', 'booking_com',
      'gross_amount', v_gross_amount,
      'sync_log_id', v_booking.ota_last_sync_log_id
    ),
    v_booking.created_by
  )
  ON CONFLICT (company_id, idempotency_key) DO NOTHING
  RETURNING id INTO v_event_log_id;

  IF v_event_log_id IS NULL THEN
    SELECT *
    INTO v_existing_event
    FROM public.financial_event_logs fel
    WHERE fel.company_id = v_booking.company_id
      AND fel.idempotency_key = 'booking_com:booking_import:' || v_booking.id::text
    LIMIT 1;

    IF v_existing_event.status = 'processed'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'processed',
        'journal_entry_id', v_existing_event.journal_entry_id,
        'event_log_id', v_existing_event.id,
        'booking_id', v_booking.id
      );
    END IF;

    IF v_existing_event.status = 'ignored'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'ignored',
        'event_log_id', v_existing_event.id,
        'booking_id', v_booking.id
      );
    END IF;

    v_event_log_id := v_existing_event.id;

    UPDATE public.financial_event_logs
    SET
      status = 'pending'::public.financial_event_status,
      error_message = NULL,
      processed_at = NULL,
      journal_entry_id = NULL,
      updated_at = NOW()
    WHERE id = v_event_log_id;
  END IF;

  v_receivable_account_id := public.resolve_ota_receivable_account(v_booking.company_id, v_platform);
  v_unearned_account_id := public.get_company_account_id_by_code(v_booking.company_id, '2100');

  IF v_receivable_account_id IS NULL THEN
    RAISE EXCEPTION 'OTA Receivables account (1130) is not configured for company %.', v_booking.company_id;
  END IF;

  IF v_unearned_account_id IS NULL THEN
    RAISE EXCEPTION 'Unearned Room Revenue account (2100) is not configured for company %.', v_booking.company_id;
  END IF;

  INSERT INTO public.journal_entries (
    company_id,
    outlet_id,
    posting_scope,
    reference_type,
    reference_id,
    source_module,
    entry_date,
    memo,
    status,
    created_by
  )
  VALUES (
    v_booking.company_id,
    v_booking.outlet_id,
    'outlet'::public.journal_posting_scope,
    'accommodation_booking',
    v_booking.id,
    'booking_com'::public.journal_source_module,
    v_booking.check_in,
    format(
      'Booking.com OTA-collected booking import for booking %s (%s).',
      v_booking.id,
      COALESCE(v_booking.external_id, 'no external id')
    ),
    'draft'::public.journal_entry_status,
    v_booking.created_by
  )
  RETURNING id INTO v_journal_entry_id;

  INSERT INTO public.journal_entry_lines (
    company_id,
    journal_entry_id,
    account_id,
    outlet_id,
    debit,
    credit,
    description,
    created_by
  )
  VALUES (
    v_booking.company_id,
    v_journal_entry_id,
    v_receivable_account_id,
    v_booking.outlet_id,
    v_gross_amount,
    0,
    'Recognize Booking.com OTA receivable',
    v_booking.created_by
  ), (
    v_booking.company_id,
    v_journal_entry_id,
    v_unearned_account_id,
    v_booking.outlet_id,
    0,
    v_gross_amount,
    'Recognize unearned revenue from OTA-collected booking',
    v_booking.created_by
  );

  UPDATE public.journal_entries
  SET status = 'posted'::public.journal_entry_status
  WHERE id = v_journal_entry_id;

  UPDATE public.financial_event_logs
  SET
    status = 'processed'::public.financial_event_status,
    journal_entry_id = v_journal_entry_id,
    processed_at = NOW(),
    error_message = NULL,
    updated_at = NOW()
  WHERE id = v_event_log_id;

  RETURN jsonb_build_object(
    'status', 'processed',
    'journal_entry_id', v_journal_entry_id,
    'event_log_id', v_event_log_id,
    'booking_id', v_booking.id
  );

EXCEPTION
  WHEN OTHERS THEN
    IF v_event_log_id IS NOT NULL THEN
      UPDATE public.financial_event_logs
      SET
        status = 'failed'::public.financial_event_status,
        error_message = SQLERRM,
        updated_at = NOW()
      WHERE id = v_event_log_id;
    END IF;

    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_ota_booking_import_accounting(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.handle_ota_booking_import_accounting_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.post_ota_booking_import_accounting(NEW.id);
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND (
    OLD.source IS DISTINCT FROM NEW.source
    OR OLD.ota_collects_payment IS DISTINCT FROM NEW.ota_collects_payment
    OR OLD.ota_gross_amount IS DISTINCT FROM NEW.ota_gross_amount
    OR OLD.external_id IS DISTINCT FROM NEW.external_id
    OR OLD.ota_last_sync_log_id IS DISTINCT FROM NEW.ota_last_sync_log_id
  ) THEN
    PERFORM public.post_ota_booking_import_accounting(NEW.id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ota_booking_import_accounting_after_write
  ON public.accommodation_bookings;

CREATE TRIGGER ota_booking_import_accounting_after_write
  AFTER INSERT OR UPDATE ON public.accommodation_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_ota_booking_import_accounting_trigger();

-- ============================================================
-- 6. OTA payout accounting
-- ============================================================
CREATE OR REPLACE FUNCTION public.post_accommodation_ota_payout_accounting(
  p_payout_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payout RECORD;
  v_event_log_id UUID;
  v_existing_event RECORD;
  v_bank_account_id UUID;
  v_receivable_account_id UUID;
  v_commission_account_id UUID;
  v_journal_entry_id UUID;
  v_allocated_gross NUMERIC(12, 2);
  v_allocated_commission NUMERIC(12, 2);
  v_allocated_net NUMERIC(12, 2);
BEGIN
  SELECT
    aop.id,
    aop.platform,
    aop.payout_reference,
    aop.gross_amount,
    aop.commission_amount,
    aop.net_amount,
    aop.currency,
    aop.received_at,
    aop.created_by,
    aop.sync_log_id,
    ap.id AS property_id,
    ap.name AS property_name,
    ap.outlet_id,
    o.company_id
  INTO v_payout
  FROM public.accommodation_ota_payouts aop
  JOIN public.accommodation_properties ap
    ON ap.id = aop.property_id
  JOIN public.outlets o
    ON o.id = ap.outlet_id
  WHERE aop.id = p_payout_id
  LIMIT 1;

  IF v_payout.id IS NULL THEN
    RAISE EXCEPTION 'Accommodation OTA payout % does not exist', p_payout_id;
  END IF;

  IF v_payout.platform <> 'booking_com'::public.ota_platform THEN
    RETURN jsonb_build_object(
      'status', 'ignored',
      'payout_id', v_payout.id,
      'reason', 'unsupported_platform'
    );
  END IF;

  SELECT
    COALESCE(SUM(gross_amount), 0)::NUMERIC(12, 2),
    COALESCE(SUM(commission_amount), 0)::NUMERIC(12, 2),
    COALESCE(SUM(net_amount), 0)::NUMERIC(12, 2)
  INTO
    v_allocated_gross,
    v_allocated_commission,
    v_allocated_net
  FROM public.accommodation_ota_payout_bookings
  WHERE payout_id = v_payout.id;

  INSERT INTO public.financial_event_logs (
    company_id,
    outlet_id,
    event_type,
    source_module,
    reference_type,
    reference_id,
    idempotency_key,
    status,
    payload,
    created_by
  )
  VALUES (
    v_payout.company_id,
    v_payout.outlet_id,
    'ota_payout_received',
    'booking_com'::public.journal_source_module,
    'accommodation_ota_payout',
    v_payout.id,
    'booking_com:payout:' || v_payout.id::text,
    'pending'::public.financial_event_status,
    jsonb_build_object(
      'payout_id', v_payout.id,
      'platform', v_payout.platform,
      'payout_reference', v_payout.payout_reference,
      'property_id', v_payout.property_id,
      'property_name', v_payout.property_name,
      'sync_log_id', v_payout.sync_log_id,
      'gross_amount', v_payout.gross_amount,
      'commission_amount', v_payout.commission_amount,
      'net_amount', v_payout.net_amount
    ),
    v_payout.created_by
  )
  ON CONFLICT (company_id, idempotency_key) DO NOTHING
  RETURNING id INTO v_event_log_id;

  IF v_event_log_id IS NULL THEN
    SELECT *
    INTO v_existing_event
    FROM public.financial_event_logs fel
    WHERE fel.company_id = v_payout.company_id
      AND fel.idempotency_key = 'booking_com:payout:' || v_payout.id::text
    LIMIT 1;

    IF v_existing_event.status = 'processed'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'processed',
        'journal_entry_id', v_existing_event.journal_entry_id,
        'event_log_id', v_existing_event.id,
        'payout_id', v_payout.id
      );
    END IF;

    IF v_existing_event.status = 'ignored'::public.financial_event_status THEN
      RETURN jsonb_build_object(
        'status', 'ignored',
        'event_log_id', v_existing_event.id,
        'payout_id', v_payout.id
      );
    END IF;

    v_event_log_id := v_existing_event.id;

    UPDATE public.financial_event_logs
    SET
      status = 'pending'::public.financial_event_status,
      error_message = NULL,
      processed_at = NULL,
      journal_entry_id = NULL,
      updated_at = NOW()
    WHERE id = v_event_log_id;
  END IF;

  IF v_allocated_gross > 0 THEN
    IF v_allocated_gross <> v_payout.gross_amount
       OR v_allocated_commission <> v_payout.commission_amount
       OR v_allocated_net <> v_payout.net_amount THEN
      RAISE EXCEPTION 'OTA payout allocation totals do not match payout totals.';
    END IF;
  END IF;

  v_bank_account_id := public.resolve_ota_payout_bank_account(v_payout.company_id);
  v_receivable_account_id := public.resolve_ota_receivable_account(v_payout.company_id, v_payout.platform);
  v_commission_account_id := public.resolve_ota_commission_expense_account(v_payout.company_id, v_payout.platform);

  IF v_bank_account_id IS NULL THEN
    RAISE EXCEPTION 'Main Bank Account (1010) is not configured for company %.', v_payout.company_id;
  END IF;

  IF v_receivable_account_id IS NULL THEN
    RAISE EXCEPTION 'OTA Receivables account (1130) is not configured for company %.', v_payout.company_id;
  END IF;

  IF v_commission_account_id IS NULL THEN
    RAISE EXCEPTION 'Booking.com Commission account is not configured for company %.', v_payout.company_id;
  END IF;

  INSERT INTO public.journal_entries (
    company_id,
    outlet_id,
    posting_scope,
    reference_type,
    reference_id,
    source_module,
    entry_date,
    memo,
    status,
    created_by
  )
  VALUES (
    v_payout.company_id,
    v_payout.outlet_id,
    'outlet'::public.journal_posting_scope,
    'accommodation_ota_payout',
    v_payout.id,
    'booking_com'::public.journal_source_module,
    v_payout.received_at::DATE,
    format(
      'Booking.com payout received for property %s (%s).',
      v_payout.property_name,
      v_payout.payout_reference
    ),
    'draft'::public.journal_entry_status,
    v_payout.created_by
  )
  RETURNING id INTO v_journal_entry_id;

  INSERT INTO public.journal_entry_lines (
    company_id,
    journal_entry_id,
    account_id,
    outlet_id,
    debit,
    credit,
    description,
    created_by
  )
  VALUES (
    v_payout.company_id,
    v_journal_entry_id,
    v_bank_account_id,
    v_payout.outlet_id,
    v_payout.net_amount,
    0,
    'Booking.com net payout received to bank',
    v_payout.created_by
  ), (
    v_payout.company_id,
    v_journal_entry_id,
    v_commission_account_id,
    v_payout.outlet_id,
    v_payout.commission_amount,
    0,
    'Booking.com commission expense recognized',
    v_payout.created_by
  ), (
    v_payout.company_id,
    v_journal_entry_id,
    v_receivable_account_id,
    v_payout.outlet_id,
    0,
    v_payout.gross_amount,
    'Clear Booking.com OTA receivable',
    v_payout.created_by
  );

  UPDATE public.journal_entries
  SET status = 'posted'::public.journal_entry_status
  WHERE id = v_journal_entry_id;

  UPDATE public.financial_event_logs
  SET
    status = 'processed'::public.financial_event_status,
    journal_entry_id = v_journal_entry_id,
    processed_at = NOW(),
    error_message = NULL,
    payload = COALESCE(payload, '{}'::jsonb)
      || jsonb_build_object(
        'allocated_gross_amount', v_allocated_gross,
        'allocated_commission_amount', v_allocated_commission,
        'allocated_net_amount', v_allocated_net
      ),
    updated_at = NOW()
  WHERE id = v_event_log_id;

  RETURN jsonb_build_object(
    'status', 'processed',
    'journal_entry_id', v_journal_entry_id,
    'event_log_id', v_event_log_id,
    'payout_id', v_payout.id
  );

EXCEPTION
  WHEN OTHERS THEN
    IF v_event_log_id IS NOT NULL THEN
      UPDATE public.financial_event_logs
      SET
        status = 'failed'::public.financial_event_status,
        error_message = SQLERRM,
        updated_at = NOW()
      WHERE id = v_event_log_id;
    END IF;

    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_accommodation_ota_payout_accounting(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.handle_accommodation_ota_payout_accounting_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.post_accommodation_ota_payout_accounting(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS accommodation_ota_payout_accounting_after_insert
  ON public.accommodation_ota_payouts;

CREATE TRIGGER accommodation_ota_payout_accounting_after_insert
  AFTER INSERT ON public.accommodation_ota_payouts
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_accommodation_ota_payout_accounting_trigger();

-- ============================================================
-- 7. OTA payout reconciliation view
-- ============================================================
DROP VIEW IF EXISTS public.booking_com_payout_reconciliation_view;

CREATE VIEW public.booking_com_payout_reconciliation_view
WITH (security_invoker = true) AS
SELECT
  aop.id AS payout_id,
  aop.property_id,
  ap.outlet_id,
  o.company_id,
  aop.platform,
  aop.payout_reference,
  aop.currency,
  aop.received_at,
  aop.gross_amount,
  aop.commission_amount,
  aop.net_amount,
  COALESCE(SUM(aopb.gross_amount), 0)::NUMERIC(12, 2) AS allocated_gross_amount,
  COALESCE(SUM(aopb.commission_amount), 0)::NUMERIC(12, 2) AS allocated_commission_amount,
  COALESCE(SUM(aopb.net_amount), 0)::NUMERIC(12, 2) AS allocated_net_amount,
  ROUND(aop.gross_amount - COALESCE(SUM(aopb.gross_amount), 0), 2) AS gross_difference,
  ROUND(aop.commission_amount - COALESCE(SUM(aopb.commission_amount), 0), 2) AS commission_difference,
  ROUND(aop.net_amount - COALESCE(SUM(aopb.net_amount), 0), 2) AS net_difference,
  COUNT(aopb.booking_id)::INT AS linked_bookings_count,
  aop.sync_log_id
FROM public.accommodation_ota_payouts aop
JOIN public.accommodation_properties ap
  ON ap.id = aop.property_id
JOIN public.outlets o
  ON o.id = ap.outlet_id
LEFT JOIN public.accommodation_ota_payout_bookings aopb
  ON aopb.payout_id = aop.id
WHERE aop.platform = 'booking_com'::public.ota_platform
GROUP BY
  aop.id,
  aop.property_id,
  ap.outlet_id,
  o.company_id,
  aop.platform,
  aop.payout_reference,
  aop.currency,
  aop.received_at,
  aop.gross_amount,
  aop.commission_amount,
  aop.net_amount,
  aop.sync_log_id;

GRANT SELECT ON public.booking_com_payout_reconciliation_view TO authenticated;
