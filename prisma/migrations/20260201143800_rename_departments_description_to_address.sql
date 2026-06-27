-- Migration: Rename description to address in departments table
-- Created: 2026-02-01
-- Description: Changes the 'description' field to 'address' for more accurate naming

ALTER TABLE departments RENAME COLUMN description TO address;

-- Update any comments or constraints that reference the old column name
COMMENT ON COLUMN departments.address IS 'The location or address for this department (e.g., Kitchen Station 1, Bar Counter)';
