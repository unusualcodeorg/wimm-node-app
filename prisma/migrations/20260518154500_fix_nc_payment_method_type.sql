-- Migration: Fix NC payment method type
-- Created: 2026-05-18
-- Description:
--   - Adds non_chargeable to payment_method_type enum

-- ============================================================
-- 1. Extend payment method type enum
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'payment_method_type'
      AND e.enumlabel = 'non_chargeable'
  ) THEN
    ALTER TYPE public.payment_method_type
      ADD VALUE 'non_chargeable';
  END IF;
END;
$$;
