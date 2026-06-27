-- Migration: Add 'accounting' to access_control_area enum
-- Created: 2026-05-19
-- Description:
--   Must be a separate migration so the new enum value is committed before
--   it is referenced in later access-control seed migrations.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'access_control_area'
      AND e.enumlabel = 'accounting'
  ) THEN
    ALTER TYPE public.access_control_area ADD VALUE 'accounting';
  END IF;
END;
$$;
