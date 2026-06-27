-- Migration: Add 'inventory' to access_control_area enum
-- Must be a separate migration so the new enum value is committed before
-- it is referenced in the inventory access-control seed migration.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'access_control_area'
      AND e.enumlabel = 'inventory'
  ) THEN
    ALTER TYPE public.access_control_area ADD VALUE 'inventory';
  END IF;
END;
$$;
