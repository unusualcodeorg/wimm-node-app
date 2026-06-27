-- Add optional TIN number, phone, and receipt footnote fields to outlets
ALTER TABLE outlets
  ADD COLUMN IF NOT EXISTS tin_number TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS phone TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS receipt_footnote TEXT DEFAULT NULL;
