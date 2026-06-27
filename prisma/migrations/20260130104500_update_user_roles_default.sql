-- Migration: Update user roles and default to super
-- Created: 2026-01-30
-- Description: Adds admin and super_admin roles, updates default role to super, and updates handle_new_user function

-- Add new roles to user_role enum
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'admin';
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'super_admin';

-- Update default role in users table from 'waiter' to 'super'
ALTER TABLE users ALTER COLUMN role SET DEFAULT 'super';

-- Update the handle_new_user function to set default role to 'super'
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO users (id, email, first_name, last_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
    'super'::user_role
  );
  RETURN NEW;
END;
$$;
