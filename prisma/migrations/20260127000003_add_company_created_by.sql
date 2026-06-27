-- Migration: Add created_by column to companies
-- Created: 2026-01-27
-- Description: Adds a 'created_by' column to track the user who created the company.
--              Defaults to the currently authenticated user (auth.uid()).

ALTER TABLE companies
ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) DEFAULT auth.uid();

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_companies_created_by ON companies(created_by);
