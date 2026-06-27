-- Migration: Reclassify NC payment method
-- Created: 2026-05-18
-- Description:
--   - Reclassifies NC payment method from clearing to non_chargeable

UPDATE public.payment_methods
SET type = 'non_chargeable'::public.payment_method_type
WHERE upper(name) = 'NC';
