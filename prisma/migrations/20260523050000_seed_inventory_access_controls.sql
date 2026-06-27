-- Migration: Seed inventory access controls
-- Phase 4: Inventory Access Controls

INSERT INTO public.access_controls (code, name, description, area, sort_order)
VALUES
  (
    'inventory.page_access',
    'Access inventory module',
    'Allows the user to open the inventory management area.',
    'inventory',
    380
  ),
  (
    'inventory.items_view',
    'View inventory items',
    'Allows the user to view the company inventory item catalogue.',
    'inventory',
    390
  ),
  (
    'inventory.items_manage',
    'Manage inventory items',
    'Allows the user to create, edit, and deactivate inventory items.',
    'inventory',
    400
  ),
  (
    'inventory.suppliers_view',
    'View suppliers',
    'Allows the user to view the company supplier list.',
    'inventory',
    410
  ),
  (
    'inventory.suppliers_manage',
    'Manage suppliers',
    'Allows the user to create, edit, and deactivate suppliers.',
    'inventory',
    420
  ),
  (
    'inventory.invoices_view',
    'View supplier invoices',
    'Allows the user to view supplier purchase invoices.',
    'inventory',
    430
  ),
  (
    'inventory.invoices_manage',
    'Manage supplier invoices',
    'Allows the user to create and edit draft supplier invoices.',
    'inventory',
    440
  ),
  (
    'inventory.invoices_post',
    'Post supplier invoices',
    'Allows the user to post draft supplier invoices to stock and accounting.',
    'inventory',
    450
  ),
  (
    'inventory.payments_view',
    'View supplier payments',
    'Allows the user to view recorded supplier payments.',
    'inventory',
    460
  ),
  (
    'inventory.payments_record',
    'Record supplier payments',
    'Allows the user to record new payments against supplier invoices.',
    'inventory',
    470
  ),
  (
    'inventory.stock_view',
    'View stock levels',
    'Allows the user to view stock balances, locations, and movement history.',
    'inventory',
    480
  ),
  (
    'inventory.stock_adjust',
    'Adjust stock',
    'Allows the user to record stock adjustments and wastage.',
    'inventory',
    490
  ),
  (
    'inventory.stock_transfer',
    'Transfer stock',
    'Allows the user to create stock transfers between locations.',
    'inventory',
    500
  ),
  (
    'inventory.recipes_view',
    'View recipes',
    'Allows the user to view inventory recipes linked to menu items.',
    'inventory',
    510
  ),
  (
    'inventory.recipes_manage',
    'Manage recipes',
    'Allows the user to create, edit, and delete inventory recipes.',
    'inventory',
    520
  ),
  (
    'inventory.reports_view',
    'View inventory reports',
    'Allows the user to view stock valuation and inventory movement reports.',
    'inventory',
    530
  )
ON CONFLICT (code) DO UPDATE
SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  area        = EXCLUDED.area,
  sort_order  = EXCLUDED.sort_order;
