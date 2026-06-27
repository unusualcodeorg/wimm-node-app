-- Migration: Enforce booking balance must be fully paid before checkout
-- Created: 2026-05-28
-- Description:
--   Staff were able to check out guests regardless of whether the accommodation
--   booking fee had been settled.  This adds a BEFORE UPDATE trigger that blocks
--   the status transition to 'checked_out' whenever total_amount > amount_paid.
--
--   Outstanding restaurant/POS bills (linked via client_id) do NOT block checkout
--   — only the accommodation fee itself is checked here.
--
--   The frontend error pipeline already displays trigger exceptions as toast
--   notifications (accommodationService → throw new Error(error.message) →
--   useUpdateBookingStatus onError → apiError(err.message)), so no frontend
--   changes are required.

CREATE OR REPLACE FUNCTION public.enforce_accommodation_checkout_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_balance NUMERIC(12, 2);
BEGIN
  -- Only run when transitioning into checked_out
  IF NEW.status = 'checked_out'::public.accommodation_booking_status
     AND OLD.status IS DISTINCT FROM NEW.status THEN

    v_balance := COALESCE(NEW.total_amount, 0) - COALESCE(NEW.amount_paid, 0);

    IF v_balance > 0 THEN
      RAISE EXCEPTION
        'Cannot check out: booking has an outstanding balance of % %. Please collect the remaining payment before proceeding.',
        v_balance,
        COALESCE(NEW.currency, 'UGX');
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_accommodation_checkout_balance_before_update
  ON public.accommodation_bookings;

CREATE TRIGGER enforce_accommodation_checkout_balance_before_update
  BEFORE UPDATE ON public.accommodation_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_accommodation_checkout_balance();
