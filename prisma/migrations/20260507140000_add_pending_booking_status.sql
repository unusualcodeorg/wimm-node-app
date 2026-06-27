-- Migration: add 'pending' value to accommodation_booking_status enum.
--
-- IMPORTANT: PostgreSQL does NOT allow using a newly added enum value
-- within the same transaction that added it (error 55P04). The column
-- DEFAULT assignment is therefore moved to the NEXT migration file
-- (20260507160000) so it runs after this transaction has committed.
--
-- NOTE: ADD VALUE is idempotent with IF NOT EXISTS (Postgres 9.6+).

ALTER TYPE public.accommodation_booking_status
  ADD VALUE IF NOT EXISTS 'pending' BEFORE 'confirmed';
