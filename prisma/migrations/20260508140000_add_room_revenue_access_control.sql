-- ============================================================
-- Migration: Add room revenue report access control
-- ============================================================
INSERT INTO access_controls (code, name, description, area, sort_order)
VALUES (
  'accommodation.reports.room_revenue',
  'View room revenue report',
  'Allows the user to view the room-by-room daily revenue matrix report.',
  'accommodation',
  259
)
ON CONFLICT (code) DO NOTHING;
