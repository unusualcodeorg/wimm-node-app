-- ============================================================
-- Migration: Seed accounting access controls
-- ============================================================

INSERT INTO public.access_controls (code, name, description, area, sort_order)
VALUES
  (
    'accounting.view_accounts',
    'View chart of accounts',
    'Allows the user to view the company chart of accounts and account balances.',
    'accounting',
    280
  ),
  (
    'accounting.manage_accounts',
    'Manage chart of accounts',
    'Allows the user to create, edit, and deactivate chart of accounts records.',
    'accounting',
    290
  ),
  (
    'accounting.view_journals',
    'View journal entries',
    'Allows the user to view manual and automated accounting journal entries.',
    'accounting',
    300
  ),
  (
    'accounting.post_journals',
    'Post journal entries',
    'Allows the user to post balanced draft journal entries into the ledger.',
    'accounting',
    310
  ),
  (
    'accounting.reverse_journals',
    'Reverse journal entries',
    'Allows the user to reverse posted journal entries using the reversal workflow.',
    'accounting',
    320
  ),
  (
    'accounting.close_periods',
    'Close accounting periods',
    'Allows the user to close open accounting periods and lock new postings.',
    'accounting',
    330
  ),
  (
    'accounting.view_reports',
    'View accounting reports',
    'Allows the user to view ledgers, trial balances, and other accounting reports.',
    'accounting',
    340
  ),
  (
    'accounting.export_reports',
    'Export accounting reports',
    'Allows the user to export accounting reports for sharing or offline analysis.',
    'accounting',
    350
  ),
  (
    'accounting.manage_tax_rates',
    'Manage tax rates',
    'Allows the user to configure accounting tax rates and tax account mappings.',
    'accounting',
    360
  ),
  (
    'accounting.manage_payment_mappings',
    'Manage payment mappings',
    'Allows the user to configure payment method to account mapping rules.',
    'accounting',
    370
  )
ON CONFLICT (code) DO UPDATE
SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  area = EXCLUDED.area,
  sort_order = EXCLUDED.sort_order;
