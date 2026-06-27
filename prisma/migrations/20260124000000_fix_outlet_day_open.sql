-- Migration: Fix Outlet Day Open and Add Email Verification Support
-- Created: 2026-01-24
-- Description: Changes day_open to day_opened_at (DATE) and ensures users table supports verification

-- ============================================
-- 1. Fix outlets table: day_open -> day_opened_at
-- ============================================

-- First drop the old column and type
ALTER TABLE outlets DROP COLUMN day_open;
DROP TYPE IF EXISTS day_status;

-- Add new column for day_opened_at
-- Default value is today's date
ALTER TABLE outlets ADD COLUMN day_opened_at DATE DEFAULT CURRENT_DATE;

-- ============================================
-- 2. Update functions/triggers if necessary
-- ============================================

-- If appropriate, we can ensure that we clean up any other artifacts.
-- Since we are moving to standard Supabase Auth OTP, the users table stays as is (auth.users handles the verification status).
