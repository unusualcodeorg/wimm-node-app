-- Migration: Add payment method type classification
-- Created: 2026-05-18
-- Description:
--   - Adds payment_method_type enum
--   - Extends global payment_methods with type classification
--   - Backfills existing payment methods with default types

-- ============================================================
-- 1. Payment method type enum
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type
    WHERE typname = 'payment_method_type'
  ) THEN
    CREATE TYPE public.payment_method_type AS ENUM (
      'cash',
      'bank',
      'card',
      'mobile_money',
      'credit',
      'check',
      'clearing',
      'status'
    );
  END IF;
END;
$$;

-- ============================================================
-- 2. Extend payment_methods
-- ============================================================
ALTER TABLE public.payment_methods
  ADD COLUMN IF NOT EXISTS type public.payment_method_type;

UPDATE public.payment_methods
SET type = CASE upper(name)
  WHEN 'CASH' THEN 'cash'::public.payment_method_type
  WHEN 'CARD' THEN 'card'::public.payment_method_type
  WHEN 'MOBILE MONEY' THEN 'mobile_money'::public.payment_method_type
  WHEN 'CHECK' THEN 'check'::public.payment_method_type
  WHEN 'EFT' THEN 'bank'::public.payment_method_type
  WHEN 'CREDIT' THEN 'credit'::public.payment_method_type
  WHEN 'NC' THEN 'clearing'::public.payment_method_type
  WHEN 'CANCELLED' THEN 'status'::public.payment_method_type
  WHEN 'PENDING' THEN 'status'::public.payment_method_type
  WHEN 'OPEN' THEN 'status'::public.payment_method_type
  ELSE 'clearing'::public.payment_method_type
END
WHERE type IS NULL;

ALTER TABLE public.payment_methods
  ALTER COLUMN type SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payment_methods_type
  ON public.payment_methods(type);
