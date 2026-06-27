-- Migration: Initial Schema for SmartPOS Cloud
-- Created: 2026-01-23
-- Description: Creates core tables for companies, outlets, users, and billing

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create ENUM types
CREATE TYPE business_type AS ENUM ('restaurant_bar', 'retail', 'other');
CREATE TYPE user_role AS ENUM ('super', 'waiter', 'cashier', 'receptionist', 'accountant', 'kds');
CREATE TYPE subscription_package AS ENUM ('starter', 'professional', 'enterprise');
CREATE TYPE subscription_status AS ENUM ('active', 'trialing', 'past_due', 'canceled', 'incomplete');

-- Companies table (with numeric ID)
CREATE TABLE companies (
  id BIGSERIAL PRIMARY KEY,
  business_name TEXT NOT NULL,
  business_type business_type NOT NULL,
  country TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Outlets table
CREATE TABLE outlets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id BIGINT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Users table (extends auth.users)
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  role user_role NOT NULL DEFAULT 'waiter',
  company_id BIGINT REFERENCES companies(id) ON DELETE CASCADE,
  outlet_id UUID REFERENCES outlets(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Billing records table
CREATE TABLE billing_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  outlet_id UUID NOT NULL REFERENCES outlets(id) ON DELETE CASCADE,
  package subscription_package NOT NULL,
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  trial_ends_at TIMESTAMPTZ,
  subscription_status subscription_status NOT NULL DEFAULT 'trialing',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX idx_outlets_company_id ON outlets(company_id);
CREATE INDEX idx_users_company_id ON users(company_id);
CREATE INDEX idx_users_outlet_id ON users(outlet_id);
CREATE INDEX idx_billing_outlet_id ON billing_records(outlet_id);

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at
CREATE TRIGGER update_companies_updated_at BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_outlets_updated_at BEFORE UPDATE ON outlets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_billing_records_updated_at BEFORE UPDATE ON billing_records
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create function to create a new company and return its ID
CREATE OR REPLACE FUNCTION create_company(
  p_business_name TEXT,
  p_business_type TEXT,
  p_country TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id BIGINT;
BEGIN
  INSERT INTO companies (business_name, business_type, country)
  VALUES (p_business_name, p_business_type::business_type, p_country)
  RETURNING id INTO v_company_id;

  RETURN v_company_id;
END;
$$;

-- Create function to automatically create user profile after signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO users (id, email, first_name, last_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'last_name', '')
  );
  RETURN NEW;
END;
$$;

-- Create trigger to automatically create user profile
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Row Level Security (RLS) Policies

-- Enable RLS on all tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE outlets ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_records ENABLE ROW LEVEL SECURITY;

-- Companies policies
CREATE POLICY "Users can view their own company"
  ON companies FOR SELECT
  USING (id IN (
    SELECT company_id FROM users WHERE id = auth.uid()
  ));

CREATE POLICY "Super users can update their company"
  ON companies FOR UPDATE
  USING (id IN (
    SELECT company_id FROM users WHERE id = auth.uid() AND role = 'super'
  ));

-- Outlets policies
CREATE POLICY "Users can view outlets from their company"
  ON outlets FOR SELECT
  USING (company_id IN (
    SELECT company_id FROM users WHERE id = auth.uid()
  ));

CREATE POLICY "Super users can manage outlets"
  ON outlets FOR ALL
  USING (company_id IN (
    SELECT company_id FROM users WHERE id = auth.uid() AND role = 'super'
  ));

-- Users policies
CREATE POLICY "Users can view their own profile"
  ON users FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "Users can view colleagues from same company"
  ON users FOR SELECT
  USING (company_id IN (
    SELECT company_id FROM users WHERE id = auth.uid()
  ));

CREATE POLICY "Super users can manage users in their company"
  ON users FOR ALL
  USING (company_id IN (
    SELECT company_id FROM users WHERE id = auth.uid() AND role = 'super'
  ));

-- Billing records policies
CREATE POLICY "Super users can view billing for their outlets"
  ON billing_records FOR SELECT
  USING (outlet_id IN (
    SELECT o.id FROM outlets o
    JOIN users u ON u.company_id = o.company_id
    WHERE u.id = auth.uid() AND u.role = 'super'
  ));

CREATE POLICY "Super users can manage billing"
  ON billing_records FOR ALL
  USING (outlet_id IN (
    SELECT o.id FROM outlets o
    JOIN users u ON u.company_id = o.company_id
    WHERE u.id = auth.uid() AND u.role = 'super'
  ));

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
