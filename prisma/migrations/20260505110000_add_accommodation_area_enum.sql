-- Migration: Add 'accommodation' to access_control_area enum
-- Created: 2026-05-05
-- Description:
--   Must be a separate migration so the new enum value is committed before
--   it is referenced in 20260505120000_create_accommodation_schema.sql.
--   PostgreSQL does not allow using a newly added enum value in the same
--   transaction where ALTER TYPE ... ADD VALUE was executed.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'access_control_area'
      AND e.enumlabel = 'accommodation'
  ) THEN
    ALTER TYPE public.access_control_area ADD VALUE 'accommodation';
  END IF;
END;
$$;
