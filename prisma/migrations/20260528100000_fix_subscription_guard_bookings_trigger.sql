-- accommodation_bookings has no outlet_id; it links via property_id →
-- accommodation_properties.outlet_id → outlets.company_id.
-- The previous trigger incorrectly used enforce_subscription_write_access_by_outlet()
-- which reads NEW.outlet_id and therefore always raised "record has no field outlet_id".

CREATE OR REPLACE FUNCTION enforce_subscription_write_access_by_property()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id BIGINT;
BEGIN
  SELECT get_company_id_for_outlet(ap.outlet_id)
    INTO v_company_id
    FROM accommodation_properties ap
   WHERE ap.id = NEW.property_id;

  IF v_company_id IS NOT NULL AND NOT company_subscription_allows_writes(v_company_id) THEN
    RAISE EXCEPTION 'subscription_paused: Your subscription has been paused due to a payment issue. Please update your payment method to continue.'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subscription_guard_bookings ON accommodation_bookings;
CREATE TRIGGER trg_subscription_guard_bookings
  BEFORE INSERT ON accommodation_bookings
  FOR EACH ROW
  EXECUTE FUNCTION enforce_subscription_write_access_by_property();
