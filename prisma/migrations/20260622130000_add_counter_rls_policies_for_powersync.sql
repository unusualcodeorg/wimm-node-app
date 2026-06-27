-- RLS policies for outlet_order_counters and outlet_kot_counters
--
-- Background: PowerSync uploads local counter increments via the Supabase REST
-- API (PATCH operations in supabaseConnector.ts). Both tables have RLS enabled
-- but had no UPDATE policy, so every PATCH silently updated 0 rows. The server
-- counter never advanced, causing the next order/KOT creation to re-generate
-- the same counter value and collide with the existing row in Supabase.
--
-- Fix: grant SELECT + UPDATE to authenticated users scoped to their own outlet.

-- ── outlet_order_counters ─────────────────────────────────────────────────────

CREATE POLICY "Users can view their outlet order counter"
  ON public.outlet_order_counters
  FOR SELECT
  TO authenticated
  USING (
    outlet_id IN (
      SELECT outlet_id FROM public.users WHERE id = auth.uid()
    )
  );

CREATE POLICY "Users can update their outlet order counter"
  ON public.outlet_order_counters
  FOR UPDATE
  TO authenticated
  USING (
    outlet_id IN (
      SELECT outlet_id FROM public.users WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    outlet_id IN (
      SELECT outlet_id FROM public.users WHERE id = auth.uid()
    )
  );

-- ── outlet_kot_counters ───────────────────────────────────────────────────────

CREATE POLICY "Users can view their outlet kot counter"
  ON public.outlet_kot_counters
  FOR SELECT
  TO authenticated
  USING (
    outlet_id IN (
      SELECT outlet_id FROM public.users WHERE id = auth.uid()
    )
  );

CREATE POLICY "Users can update their outlet kot counter"
  ON public.outlet_kot_counters
  FOR UPDATE
  TO authenticated
  USING (
    outlet_id IN (
      SELECT outlet_id FROM public.users WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    outlet_id IN (
      SELECT outlet_id FROM public.users WHERE id = auth.uid()
    )
  );
