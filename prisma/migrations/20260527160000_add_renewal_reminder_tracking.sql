-- Add renewal_reminder_sent_at to billing_records to track when the
-- 10-day pre-renewal email was last sent. This is distinct from
-- last_payment_reminder_sent_at which tracks past-due recovery reminders.

ALTER TABLE billing_records
  ADD COLUMN IF NOT EXISTS renewal_reminder_sent_at TIMESTAMPTZ;

COMMENT ON COLUMN billing_records.renewal_reminder_sent_at IS
  'Timestamp of the most recent upcoming-renewal reminder email (sent ~10 days before current_period_end). Reset to NULL when a new billing period starts.';

-- Index for efficient CRON scan
CREATE INDEX IF NOT EXISTS idx_billing_records_renewal_reminder
  ON billing_records (current_period_end, renewal_reminder_sent_at)
  WHERE subscription_status IN ('active', 'trialing');
