-- Migration: Create notifications table
-- Created: 2026-01-30
-- Description: Creates notifications table for user notifications including billing alerts

-- Enable UUID extension (in case it's not already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- Create notification_type enum
CREATE TYPE notification_type AS ENUM (
  'billing_upcoming_invoice',
  'billing_payment_succeeded',
  'billing_payment_failed',
  'billing_subscription_created',
  'billing_subscription_updated',
  'billing_subscription_canceled',
  'billing_trial_ending',
  'billing_trial_ended',
  'system_announcement',
  'user_invited',
  'outlet_created'
);

-- Create notification_priority enum
CREATE TYPE notification_priority AS ENUM ('low', 'medium', 'high', 'urgent');

-- Create notifications table
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id BIGINT NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  type notification_type NOT NULL,
  priority notification_priority NOT NULL DEFAULT 'medium',
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  metadata JSONB,
  is_read BOOLEAN NOT NULL DEFAULT false,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_company_id ON notifications(company_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);

-- Create composite index for common queries
CREATE INDEX idx_notifications_user_unread ON notifications(user_id, is_read, created_at DESC);

-- Create trigger for updated_at
CREATE TRIGGER update_notifications_updated_at BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view their own notifications
CREATE POLICY "Users can view their own notifications"
  ON notifications FOR SELECT
  USING (user_id = auth.uid());

-- Users can update their own notifications (mark as read)
CREATE POLICY "Users can update their own notifications"
  ON notifications FOR UPDATE
  USING (user_id = auth.uid());

-- Super users can create notifications for users in their company
CREATE POLICY "Super users can create company notifications"
  ON notifications FOR INSERT
  WITH CHECK (company_id IN (
    SELECT company_id FROM users WHERE id = auth.uid() AND role = 'super'
  ));

-- Function to create notification for all company users
CREATE OR REPLACE FUNCTION create_company_notification(
  p_company_id BIGINT,
  p_type notification_type,
  p_priority notification_priority,
  p_title TEXT,
  p_message TEXT,
  p_metadata JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Insert notification for all users in the company
  INSERT INTO notifications (user_id, company_id, type, priority, title, message, metadata)
  SELECT
    u.id,
    p_company_id,
    p_type,
    p_priority,
    p_title,
    p_message,
    p_metadata
  FROM users u
  WHERE u.company_id = p_company_id;
END;
$$;

-- Function to create notification for a specific user
CREATE OR REPLACE FUNCTION create_user_notification(
  p_user_id UUID,
  p_company_id BIGINT,
  p_type notification_type,
  p_priority notification_priority,
  p_title TEXT,
  p_message TEXT,
  p_metadata JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notification_id UUID;
BEGIN
  INSERT INTO notifications (user_id, company_id, type, priority, title, message, metadata)
  VALUES (p_user_id, p_company_id, p_type, p_priority, p_title, p_message, p_metadata)
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

-- Function to mark notification as read
CREATE OR REPLACE FUNCTION mark_notification_read(p_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE notifications
  SET is_read = true, read_at = NOW()
  WHERE id = p_notification_id AND user_id = auth.uid();
END;
$$;

-- Function to mark all notifications as read for a user
CREATE OR REPLACE FUNCTION mark_all_notifications_read()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE notifications
  SET is_read = true, read_at = NOW()
  WHERE user_id = auth.uid() AND is_read = false;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION create_company_notification(BIGINT, notification_type, notification_priority, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION create_user_notification(UUID, BIGINT, notification_type, notification_priority, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_notification_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read() TO authenticated;
