-- Migration: Create subscription packages table
-- Created: 2026-01-30
-- Description: Creates a table to store subscription package information instead of hardcoding in the application

-- Create subscription packages table
CREATE TABLE subscription_packages (
  id subscription_package PRIMARY KEY,
  name TEXT NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  description TEXT,
  features JSONB NOT NULL DEFAULT '[]'::jsonb,
  stripe_price_id TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create index for active packages
CREATE INDEX idx_subscription_packages_active ON subscription_packages(is_active, display_order);

-- Create trigger for updated_at
CREATE TRIGGER update_subscription_packages_updated_at BEFORE UPDATE ON subscription_packages
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert default subscription packages
INSERT INTO subscription_packages (id, name, price, description, features, stripe_price_id, display_order) VALUES
  (
    'starter',
    'Starter',
    29.99,
    'Perfect for small businesses just getting started',
    '["1 Outlet", "Up to 5 Users", "Basic Menu Management", "Order Processing", "Email Support"]'::jsonb,
    'price_1SsgWDIKyBGPszbrFy8UOGoR',
    1
  ),
  (
    'professional',
    'Professional',
    49.99,
    'Great for growing businesses with multiple locations',
    '["Up to 3 Outlets", "Up to 20 Users", "Advanced Analytics", "AI Menu Extraction", "Priority Support"]'::jsonb,
    'price_1SsgXjIKyBGPszbrNucME6G4',
    2
  ),
  (
    'enterprise',
    'Enterprise',
    199.99,
    'Complete solution for large businesses with advanced needs',
    '["Unlimited Outlets", "Unlimited Users", "Advanced Analytics & Reports", "AI Menu Extraction", "Custom Integrations", "24/7 Premium Support"]'::jsonb,
    'price_1SsgZFIKyBGPszbrx5USqeqv',
    3
  );

-- Make the table publicly readable (no RLS needed for public access)
ALTER TABLE subscription_packages ENABLE ROW LEVEL SECURITY;

-- Create policy to allow everyone to read subscription packages
CREATE POLICY "Anyone can view active subscription packages"
  ON subscription_packages FOR SELECT
  USING (is_active = true);

-- Create policy to allow authenticated users to view all packages (including inactive)
CREATE POLICY "Authenticated users can view all subscription packages"
  ON subscription_packages FOR SELECT
  TO authenticated
  USING (true);

-- Grant select permission to anon and authenticated
GRANT SELECT ON subscription_packages TO anon, authenticated;
