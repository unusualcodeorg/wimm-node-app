-- Migration: Create accommodation schema
-- Created: 2026-05-05
-- Description:
--   - Adds 'accommodation' to access_control_area enum
--   - Creates accommodation_booking_status, accommodation_meal_plan, accommodation_sync_status enums
--   - Extends clients table with accommodation-specific fields
--   - Creates: accommodation_properties, accommodation_room_types, accommodation_rooms,
--              accommodation_rate_plans, accommodation_bookings, accommodation_booking_rooms,
--              accommodation_booking_events, accommodation_sync_logs
--   - Seeds 6 new access_controls rows
--   - Updates get_auth_user_effective_access_controls() with receptionist auto-grants

-- ============================================================
-- 1. New ENUMs
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'accommodation_booking_status'
  ) THEN
    CREATE TYPE public.accommodation_booking_status AS ENUM (
      'confirmed',
      'checked_in',
      'checked_out',
      'cancelled',
      'no_show'
    );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'accommodation_meal_plan'
  ) THEN
    CREATE TYPE public.accommodation_meal_plan AS ENUM (
      'room_only',
      'breakfast',
      'half_board',
      'full_board'
    );
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'accommodation_sync_status'
  ) THEN
    CREATE TYPE public.accommodation_sync_status AS ENUM (
      'pending',
      'success',
      'failed'
    );
  END IF;
END;
$$;

-- ============================================================
-- 3. Extend clients table with accommodation fields
-- ============================================================
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS nationality          TEXT,
  ADD COLUMN IF NOT EXISTS date_of_birth        DATE,
  ADD COLUMN IF NOT EXISTS id_type              TEXT,
  ADD COLUMN IF NOT EXISTS id_number            TEXT,
  ADD COLUMN IF NOT EXISTS accommodation_notes  TEXT;

-- ============================================================
-- 4. accommodation_properties
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_properties (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id           UUID NOT NULL REFERENCES public.outlets(id) ON DELETE CASCADE,
  name                TEXT NOT NULL,
  address             TEXT,
  timezone            TEXT NOT NULL DEFAULT 'UTC',
  currency            TEXT NOT NULL DEFAULT 'UGX',
  check_in_time       TIME NOT NULL DEFAULT '14:00',
  check_out_time      TIME NOT NULL DEFAULT '11:00',
  cancellation_policy TEXT,
  created_by          UUID NOT NULL REFERENCES public.users(id) DEFAULT auth.uid(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accommodation_properties_outlet_unique UNIQUE (outlet_id)
);

CREATE INDEX IF NOT EXISTS idx_accommodation_properties_outlet_id
  ON public.accommodation_properties(outlet_id);

DROP TRIGGER IF EXISTS update_accommodation_properties_updated_at
  ON public.accommodation_properties;
CREATE TRIGGER update_accommodation_properties_updated_at
  BEFORE UPDATE ON public.accommodation_properties
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 5. accommodation_room_types
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_room_types (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id  UUID NOT NULL REFERENCES public.accommodation_properties(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  description  TEXT,
  capacity     INT NOT NULL DEFAULT 2,
  base_price   NUMERIC(12, 2) NOT NULL DEFAULT 0,
  amenities    JSONB NOT NULL DEFAULT '[]',
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_by   UUID NOT NULL REFERENCES public.users(id) DEFAULT auth.uid(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_accommodation_room_types_property_id
  ON public.accommodation_room_types(property_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_accommodation_room_types_property_name_unique
  ON public.accommodation_room_types(property_id, lower(name));

DROP TRIGGER IF EXISTS update_accommodation_room_types_updated_at
  ON public.accommodation_room_types;
CREATE TRIGGER update_accommodation_room_types_updated_at
  BEFORE UPDATE ON public.accommodation_room_types
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 6. accommodation_rooms
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_rooms (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id   UUID NOT NULL REFERENCES public.accommodation_properties(id) ON DELETE CASCADE,
  room_type_id  UUID NOT NULL REFERENCES public.accommodation_room_types(id) ON DELETE RESTRICT,
  room_number   TEXT NOT NULL,
  floor         TEXT,
  notes         TEXT,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_by    UUID NOT NULL REFERENCES public.users(id) DEFAULT auth.uid(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_accommodation_rooms_property_number_unique
  ON public.accommodation_rooms(property_id, room_number);
CREATE INDEX IF NOT EXISTS idx_accommodation_rooms_property_id
  ON public.accommodation_rooms(property_id);
CREATE INDEX IF NOT EXISTS idx_accommodation_rooms_room_type_id
  ON public.accommodation_rooms(room_type_id);

DROP TRIGGER IF EXISTS update_accommodation_rooms_updated_at
  ON public.accommodation_rooms;
CREATE TRIGGER update_accommodation_rooms_updated_at
  BEFORE UPDATE ON public.accommodation_rooms
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 7. accommodation_rate_plans
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_rate_plans (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id         UUID NOT NULL REFERENCES public.accommodation_properties(id) ON DELETE CASCADE,
  name                TEXT NOT NULL,
  description         TEXT,
  meal_plan           public.accommodation_meal_plan,
  cancellation_policy TEXT,
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_by          UUID NOT NULL REFERENCES public.users(id) DEFAULT auth.uid(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_accommodation_rate_plans_property_name_unique
  ON public.accommodation_rate_plans(property_id, lower(name));
CREATE INDEX IF NOT EXISTS idx_accommodation_rate_plans_property_id
  ON public.accommodation_rate_plans(property_id);

DROP TRIGGER IF EXISTS update_accommodation_rate_plans_updated_at
  ON public.accommodation_rate_plans;
CREATE TRIGGER update_accommodation_rate_plans_updated_at
  BEFORE UPDATE ON public.accommodation_rate_plans
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 8. accommodation_bookings
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_bookings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id   UUID NOT NULL REFERENCES public.accommodation_properties(id) ON DELETE RESTRICT,
  client_id     UUID NOT NULL REFERENCES public.clients(id) ON DELETE RESTRICT,

  -- OTA-ready (Phase 1: source = 'internal', external_id = NULL)
  source        TEXT NOT NULL DEFAULT 'internal',
  external_id   TEXT,

  -- Stay
  check_in      DATE NOT NULL,
  check_out     DATE NOT NULL,
  adults        INT NOT NULL DEFAULT 1,
  children      INT NOT NULL DEFAULT 0,

  -- Financials
  total_amount  NUMERIC(12, 2) NOT NULL DEFAULT 0,
  amount_paid   NUMERIC(12, 2) NOT NULL DEFAULT 0,
  currency      TEXT NOT NULL DEFAULT 'UGX',

  -- Lifecycle (current state; full history in accommodation_booking_events)
  status        public.accommodation_booking_status NOT NULL DEFAULT 'confirmed',

  -- Misc
  notes         TEXT,
  raw_payload   JSONB,
  created_by    UUID REFERENCES public.users(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT accommodation_bookings_external_source_unique UNIQUE (external_id, source),
  CONSTRAINT accommodation_bookings_dates_check CHECK (check_out > check_in)
);

CREATE INDEX IF NOT EXISTS idx_accommodation_bookings_property_id
  ON public.accommodation_bookings(property_id);
CREATE INDEX IF NOT EXISTS idx_accommodation_bookings_client_id
  ON public.accommodation_bookings(client_id);
CREATE INDEX IF NOT EXISTS idx_accommodation_bookings_status
  ON public.accommodation_bookings(property_id, status);
CREATE INDEX IF NOT EXISTS idx_accommodation_bookings_dates
  ON public.accommodation_bookings(property_id, check_in, check_out);

DROP TRIGGER IF EXISTS update_accommodation_bookings_updated_at
  ON public.accommodation_bookings;
CREATE TRIGGER update_accommodation_bookings_updated_at
  BEFORE UPDATE ON public.accommodation_bookings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- 9. accommodation_booking_rooms
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_booking_rooms (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id      UUID NOT NULL REFERENCES public.accommodation_bookings(id) ON DELETE CASCADE,
  room_id         UUID NOT NULL REFERENCES public.accommodation_rooms(id) ON DELETE RESTRICT,
  room_type_id    UUID NOT NULL REFERENCES public.accommodation_room_types(id) ON DELETE RESTRICT,
  price_per_night NUMERIC(12, 2) NOT NULL,
  nights          INT NOT NULL,
  subtotal        NUMERIC(12, 2) NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT accommodation_booking_rooms_booking_room_unique UNIQUE (booking_id, room_id)
);

CREATE INDEX IF NOT EXISTS idx_accommodation_booking_rooms_booking_id
  ON public.accommodation_booking_rooms(booking_id);
CREATE INDEX IF NOT EXISTS idx_accommodation_booking_rooms_room_id
  ON public.accommodation_booking_rooms(room_id);

-- ============================================================
-- 10. accommodation_booking_events (immutable audit trail)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_booking_events (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id   UUID NOT NULL REFERENCES public.accommodation_bookings(id) ON DELETE CASCADE,
  from_status  public.accommodation_booking_status,  -- NULL on initial creation
  to_status    public.accommodation_booking_status NOT NULL,
  triggered_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT DEFAULT auth.uid(),
  notes        TEXT,
  metadata     JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_accommodation_booking_events_booking_id
  ON public.accommodation_booking_events(booking_id, created_at DESC);

-- ============================================================
-- 11. Trigger: auto-record booking status changes to events table
-- ============================================================
CREATE OR REPLACE FUNCTION public.track_accommodation_booking_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.accommodation_booking_events (
      booking_id, from_status, to_status, triggered_by
    ) VALUES (
      NEW.id,
      NULL,
      NEW.status,
      COALESCE(auth.uid(), NEW.created_by)
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.accommodation_booking_events (
      booking_id, from_status, to_status, triggered_by
    ) VALUES (
      NEW.id,
      OLD.status,
      NEW.status,
      COALESCE(auth.uid(), NEW.created_by)
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS track_accommodation_booking_status_trigger
  ON public.accommodation_bookings;
CREATE TRIGGER track_accommodation_booking_status_trigger
  AFTER INSERT OR UPDATE ON public.accommodation_bookings
  FOR EACH ROW EXECUTE FUNCTION public.track_accommodation_booking_status();

-- ============================================================
-- 12. accommodation_sync_logs
-- ============================================================
CREATE TABLE IF NOT EXISTS public.accommodation_sync_logs (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id  UUID REFERENCES public.accommodation_properties(id) ON DELETE SET NULL,
  type         TEXT NOT NULL,
  status       public.accommodation_sync_status NOT NULL DEFAULT 'pending',
  payload      JSONB,
  error        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_accommodation_sync_logs_property_id
  ON public.accommodation_sync_logs(property_id, created_at DESC);

-- ============================================================
-- 13. RLS helper functions
-- ============================================================

-- Returns TRUE if the authenticated user's company owns the given property
CREATE OR REPLACE FUNCTION public.auth_user_can_access_accommodation_property(p_property_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.accommodation_properties ap
    JOIN public.outlets o ON o.id = ap.outlet_id
    WHERE ap.id = p_property_id
      AND o.company_id = public.get_auth_user_company_id()
  );
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_access_accommodation_property(UUID) TO authenticated;

-- Returns TRUE for roles that can write accommodation records
CREATE OR REPLACE FUNCTION public.auth_user_can_manage_accommodation()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_auth_user_role() IN (
    'super'::public.user_role,
    'admin'::public.user_role,
    'super_admin'::public.user_role,
    'manager'::public.user_role,
    'receptionist'::public.user_role
  );
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_manage_accommodation() TO authenticated;

-- Returns TRUE for roles that can delete accommodation records
CREATE OR REPLACE FUNCTION public.auth_user_can_delete_accommodation()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_auth_user_role() IN (
    'super'::public.user_role,
    'admin'::public.user_role,
    'super_admin'::public.user_role
  );
$$;

GRANT EXECUTE ON FUNCTION public.auth_user_can_delete_accommodation() TO authenticated;

-- ============================================================
-- 14. Enable RLS
-- ============================================================
ALTER TABLE public.accommodation_properties    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_room_types    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_rooms         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_rate_plans    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_bookings      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_booking_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_booking_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accommodation_sync_logs     ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 15. RLS policies: accommodation_properties
-- ============================================================
DROP POLICY IF EXISTS "Users can view their company accommodation properties"
  ON public.accommodation_properties;
CREATE POLICY "Users can view their company accommodation properties"
  ON public.accommodation_properties FOR SELECT
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id = public.get_auth_user_company_id()
    )
  );

DROP POLICY IF EXISTS "Managers can manage accommodation properties"
  ON public.accommodation_properties;
CREATE POLICY "Managers can manage accommodation properties"
  ON public.accommodation_properties FOR ALL
  TO authenticated
  USING (
    outlet_id IN (
      SELECT o.id FROM public.outlets o
      WHERE o.company_id = public.get_auth_user_company_id()
    )
    AND public.auth_user_can_manage_accommodation()
  );

-- ============================================================
-- 16. RLS policies: accommodation_room_types
-- ============================================================
DROP POLICY IF EXISTS "Users can view room types in their company"
  ON public.accommodation_room_types;
CREATE POLICY "Users can view room types in their company"
  ON public.accommodation_room_types FOR SELECT
  TO authenticated
  USING (public.auth_user_can_access_accommodation_property(property_id));

DROP POLICY IF EXISTS "Managers can manage room types"
  ON public.accommodation_room_types;
CREATE POLICY "Managers can manage room types"
  ON public.accommodation_room_types FOR INSERT
  TO authenticated
  WITH CHECK (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Managers can update room types"
  ON public.accommodation_room_types;
CREATE POLICY "Managers can update room types"
  ON public.accommodation_room_types FOR UPDATE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Admins can delete room types"
  ON public.accommodation_room_types;
CREATE POLICY "Admins can delete room types"
  ON public.accommodation_room_types FOR DELETE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_delete_accommodation()
  );

-- ============================================================
-- 17. RLS policies: accommodation_rooms
-- ============================================================
DROP POLICY IF EXISTS "Users can view rooms in their company"
  ON public.accommodation_rooms;
CREATE POLICY "Users can view rooms in their company"
  ON public.accommodation_rooms FOR SELECT
  TO authenticated
  USING (public.auth_user_can_access_accommodation_property(property_id));

DROP POLICY IF EXISTS "Managers can insert rooms"
  ON public.accommodation_rooms;
CREATE POLICY "Managers can insert rooms"
  ON public.accommodation_rooms FOR INSERT
  TO authenticated
  WITH CHECK (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Managers can update rooms"
  ON public.accommodation_rooms;
CREATE POLICY "Managers can update rooms"
  ON public.accommodation_rooms FOR UPDATE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Admins can delete rooms"
  ON public.accommodation_rooms;
CREATE POLICY "Admins can delete rooms"
  ON public.accommodation_rooms FOR DELETE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_delete_accommodation()
  );

-- ============================================================
-- 18. RLS policies: accommodation_rate_plans
-- ============================================================
DROP POLICY IF EXISTS "Users can view rate plans in their company"
  ON public.accommodation_rate_plans;
CREATE POLICY "Users can view rate plans in their company"
  ON public.accommodation_rate_plans FOR SELECT
  TO authenticated
  USING (public.auth_user_can_access_accommodation_property(property_id));

DROP POLICY IF EXISTS "Managers can insert rate plans"
  ON public.accommodation_rate_plans;
CREATE POLICY "Managers can insert rate plans"
  ON public.accommodation_rate_plans FOR INSERT
  TO authenticated
  WITH CHECK (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Managers can update rate plans"
  ON public.accommodation_rate_plans;
CREATE POLICY "Managers can update rate plans"
  ON public.accommodation_rate_plans FOR UPDATE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Admins can delete rate plans"
  ON public.accommodation_rate_plans;
CREATE POLICY "Admins can delete rate plans"
  ON public.accommodation_rate_plans FOR DELETE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_delete_accommodation()
  );

-- ============================================================
-- 19. RLS policies: accommodation_bookings
-- ============================================================
DROP POLICY IF EXISTS "Users can view bookings in their company"
  ON public.accommodation_bookings;
CREATE POLICY "Users can view bookings in their company"
  ON public.accommodation_bookings FOR SELECT
  TO authenticated
  USING (public.auth_user_can_access_accommodation_property(property_id));

DROP POLICY IF EXISTS "Managers can insert bookings"
  ON public.accommodation_bookings;
CREATE POLICY "Managers can insert bookings"
  ON public.accommodation_bookings FOR INSERT
  TO authenticated
  WITH CHECK (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Managers can update bookings"
  ON public.accommodation_bookings;
CREATE POLICY "Managers can update bookings"
  ON public.accommodation_bookings FOR UPDATE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_manage_accommodation()
  );

DROP POLICY IF EXISTS "Admins can delete bookings"
  ON public.accommodation_bookings;
CREATE POLICY "Admins can delete bookings"
  ON public.accommodation_bookings FOR DELETE
  TO authenticated
  USING (
    public.auth_user_can_access_accommodation_property(property_id)
    AND public.auth_user_can_delete_accommodation()
  );

-- ============================================================
-- 20. RLS policies: accommodation_booking_rooms
-- ============================================================
DROP POLICY IF EXISTS "Users can view booking rooms in their company"
  ON public.accommodation_booking_rooms;
CREATE POLICY "Users can view booking rooms in their company"
  ON public.accommodation_booking_rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accommodation_bookings b
      WHERE b.id = booking_id
        AND public.auth_user_can_access_accommodation_property(b.property_id)
    )
  );

DROP POLICY IF EXISTS "Managers can insert booking rooms"
  ON public.accommodation_booking_rooms;
CREATE POLICY "Managers can insert booking rooms"
  ON public.accommodation_booking_rooms FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.accommodation_bookings b
      WHERE b.id = booking_id
        AND public.auth_user_can_access_accommodation_property(b.property_id)
    )
    AND public.auth_user_can_manage_accommodation()
  );

-- ============================================================
-- 21. RLS policies: accommodation_booking_events
-- ============================================================
DROP POLICY IF EXISTS "Users can view booking events in their company"
  ON public.accommodation_booking_events;
CREATE POLICY "Users can view booking events in their company"
  ON public.accommodation_booking_events FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.accommodation_bookings b
      WHERE b.id = booking_id
        AND public.auth_user_can_access_accommodation_property(b.property_id)
    )
  );

DROP POLICY IF EXISTS "Managers can insert booking events"
  ON public.accommodation_booking_events;
CREATE POLICY "Managers can insert booking events"
  ON public.accommodation_booking_events FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.accommodation_bookings b
      WHERE b.id = booking_id
        AND public.auth_user_can_access_accommodation_property(b.property_id)
    )
    AND public.auth_user_can_manage_accommodation()
  );

-- ============================================================
-- 22. RLS policies: accommodation_sync_logs
-- ============================================================
DROP POLICY IF EXISTS "Managers can view sync logs in their company"
  ON public.accommodation_sync_logs;
CREATE POLICY "Managers can view sync logs in their company"
  ON public.accommodation_sync_logs FOR SELECT
  TO authenticated
  USING (
    property_id IS NULL
    OR public.auth_user_can_access_accommodation_property(property_id)
  );

-- ============================================================
-- 23. Seed access_controls for accommodation area
-- ============================================================
INSERT INTO public.access_controls (code, name, description, area, sort_order)
VALUES
  (
    'accommodation.page.access',
    'Access accommodation',
    'Allows the user to open the accommodation module.',
    'accommodation',
    210
  ),
  (
    'accommodation.rooms.manage',
    'Manage rooms',
    'Allows the user to create, update, and deactivate room types and individual rooms.',
    'accommodation',
    220
  ),
  (
    'accommodation.bookings.create',
    'Create bookings',
    'Allows the user to create new reservations.',
    'accommodation',
    230
  ),
  (
    'accommodation.bookings.manage',
    'Manage bookings',
    'Allows the user to modify, check in, check out, and cancel reservations.',
    'accommodation',
    240
  ),
  (
    'accommodation.reports.view',
    'View accommodation reports',
    'Allows the user to view occupancy and revenue reports.',
    'accommodation',
    250
  ),
  (
    'accommodation.settings.manage',
    'Manage property settings',
    'Allows the user to configure property details and rate plans.',
    'accommodation',
    260
  )
ON CONFLICT (code) DO UPDATE
SET
  name        = EXCLUDED.name,
  description = EXCLUDED.description,
  area        = EXCLUDED.area,
  sort_order  = EXCLUDED.sort_order,
  updated_at  = NOW();

-- ============================================================
-- 24. Update get_auth_user_effective_access_controls()
--     to auto-grant receptionist accommodation controls
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_auth_user_effective_access_controls()
RETURNS TABLE (
  id          UUID,
  code        TEXT,
  name        TEXT,
  description TEXT,
  area        public.access_control_area,
  sort_order  INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH auth_user AS (
    SELECT
      u.id,
      u.role,
      u.outlet_id,
      o.company_id
    FROM public.users u
    LEFT JOIN public.outlets o ON o.id = u.outlet_id
    WHERE u.id = auth.uid()
    LIMIT 1
  ),
  -- Super / admin / super_admin get every control
  unrestricted_controls AS (
    SELECT ac.id, ac.code, ac.name, ac.description, ac.area, ac.sort_order
    FROM public.access_controls ac
    WHERE EXISTS (
      SELECT 1 FROM auth_user au
      WHERE au.role IN (
        'super'::public.user_role,
        'admin'::public.user_role,
        'super_admin'::public.user_role
      )
    )
  ),
  -- Controls explicitly assigned via policies
  assigned_controls AS (
    SELECT DISTINCT ac.id, ac.code, ac.name, ac.description, ac.area, ac.sort_order
    FROM auth_user au
    JOIN public.role_policy_assignments rpa
      ON rpa.company_id = au.company_id
     AND rpa.outlet_id  = au.outlet_id
     AND rpa.role       = au.role
    JOIN public.access_policy_controls apc
      ON apc.policy_id = rpa.policy_id
    JOIN public.access_controls ac
      ON ac.id = apc.access_control_id
  ),
  -- Receptionists automatically receive core accommodation controls
  receptionist_controls AS (
    SELECT ac.id, ac.code, ac.name, ac.description, ac.area, ac.sort_order
    FROM public.access_controls ac
    WHERE EXISTS (
      SELECT 1 FROM auth_user au
      WHERE au.role = 'receptionist'::public.user_role
    )
    AND ac.code IN (
      'accommodation.page.access',
      'accommodation.bookings.create',
      'accommodation.bookings.manage'
    )
  )
  SELECT DISTINCT e.id, e.code, e.name, e.description, e.area, e.sort_order
  FROM (
    SELECT * FROM unrestricted_controls
    UNION ALL
    SELECT * FROM assigned_controls
    UNION ALL
    SELECT * FROM receptionist_controls
  ) AS e
  ORDER BY e.sort_order, e.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_auth_user_effective_access_controls() TO authenticated;

-- ============================================================
-- 25. Grants
-- ============================================================
GRANT SELECT ON public.accommodation_properties     TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.accommodation_room_types     TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.accommodation_rooms          TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.accommodation_rate_plans     TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.accommodation_bookings       TO authenticated;
GRANT SELECT, INSERT ON public.accommodation_booking_rooms          TO authenticated;
GRANT SELECT, INSERT ON public.accommodation_booking_events         TO authenticated;
GRANT SELECT ON public.accommodation_sync_logs                      TO authenticated;
GRANT INSERT, UPDATE ON public.accommodation_properties             TO authenticated;
