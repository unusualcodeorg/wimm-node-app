-- Migration: Enforce accounting period rules
-- Created: 2026-05-18
-- Description:
--   - Prevents overlapping accounting periods for the same company/outlet scope
--   - Enforces accounting period open/close field behavior
--   - Prevents journal entries from being posted into closed or missing periods

-- ============================================================
-- 1. Accounting period overlap validation
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_accounting_period_non_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.accounting_periods ap
    WHERE ap.company_id = NEW.company_id
      AND ap.id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND ap.outlet_id IS NOT DISTINCT FROM NEW.outlet_id
      AND daterange(ap.period_start, ap.period_end, '[]')
          && daterange(NEW.period_start, NEW.period_end, '[]')
  ) THEN
    RAISE EXCEPTION
      'Accounting periods cannot overlap for the same company and outlet scope.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_accounting_period_non_overlap_before_write
  ON public.accounting_periods;
CREATE TRIGGER enforce_accounting_period_non_overlap_before_write
  BEFORE INSERT OR UPDATE ON public.accounting_periods
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_accounting_period_non_overlap();

-- ============================================================
-- 2. Accounting period lifecycle enforcement
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_accounting_period_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'closed'::public.accounting_period_status THEN
    IF NEW.closed_at IS NULL THEN
      NEW.closed_at := NOW();
    END IF;
  ELSE
    NEW.closed_at := NULL;
    NEW.closed_by := NULL;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'closed'::public.accounting_period_status
       AND NEW.status = 'open'::public.accounting_period_status THEN
      RAISE EXCEPTION
        'Closed accounting periods cannot be reopened directly.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_accounting_period_lifecycle_before_write
  ON public.accounting_periods;
CREATE TRIGGER enforce_accounting_period_lifecycle_before_write
  BEFORE INSERT OR UPDATE ON public.accounting_periods
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_accounting_period_lifecycle();

-- ============================================================
-- 3. Journal posting period validation
-- ============================================================
CREATE OR REPLACE FUNCTION public.validate_journal_entry_open_period()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_has_open_period BOOLEAN;
BEGIN
  IF NEW.status = 'posted'::public.journal_entry_status
     AND (
       TG_OP = 'INSERT'
       OR OLD.status IS DISTINCT FROM NEW.status
       OR NEW.entry_date IS DISTINCT FROM OLD.entry_date
       OR NEW.company_id IS DISTINCT FROM OLD.company_id
       OR NEW.outlet_id IS DISTINCT FROM OLD.outlet_id
     ) THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.accounting_periods ap
      WHERE ap.company_id = NEW.company_id
        AND ap.status = 'open'::public.accounting_period_status
        AND ap.period_start <= NEW.entry_date
        AND ap.period_end >= NEW.entry_date
        AND (ap.outlet_id IS NULL OR ap.outlet_id = NEW.outlet_id)
    )
    INTO v_has_open_period;

    IF NOT v_has_open_period THEN
      RAISE EXCEPTION
        'No open accounting period covers journal entry date % for this company/outlet context.',
        NEW.entry_date;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_journal_entry_open_period_before_posting
  ON public.journal_entries;
CREATE TRIGGER validate_journal_entry_open_period_before_posting
  BEFORE INSERT OR UPDATE ON public.journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_journal_entry_open_period();
