-- Migration: Add manager role to user_role enum
-- Created: 2026-02-11
-- Description: Adds 'manager' value to user_role enum type.
--   Must be in its own migration (separate transaction) so the value
--   is available for use in subsequent migrations.

ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'manager';
