-- Migration: Enforce journal entry lifecycle
-- Created: 2026-05-18
-- Description:
--   - Defines valid journal entry status transitions
--   - Prevents direct edits to posted, voided, and reversed journal entries
--   - Treats draft as editable, voided as cancelled-before-posting, and reversed as final

-- ============================================================
-- 1. Lifecycle enforcement trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_journal_entry_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'draft'::public.journal_entry_status THEN
    IF NEW.status NOT IN (
      'draft'::public.journal_entry_status,
      'posted'::public.journal_entry_status,
      'voided'::public.journal_entry_status
    ) THEN
      RAISE EXCEPTION
        'Invalid journal entry transition from draft to %.',
        NEW.status;
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.status = 'posted'::public.journal_entry_status THEN
    IF NEW.status NOT IN (
      'posted'::public.journal_entry_status,
      'reversed'::public.journal_entry_status
    ) THEN
      RAISE EXCEPTION
        'Posted journal entries can only remain posted or move to reversed.';
    END IF;

    IF NEW.status = 'posted'::public.journal_entry_status THEN
      IF ROW(
        NEW.company_id,
        NEW.outlet_id,
        NEW.reference_type,
        NEW.reference_id,
        NEW.source_module,
        NEW.entry_date,
        NEW.memo,
        NEW.created_by,
        NEW.created_at
      ) IS DISTINCT FROM ROW(
        OLD.company_id,
        OLD.outlet_id,
        OLD.reference_type,
        OLD.reference_id,
        OLD.source_module,
        OLD.entry_date,
        OLD.memo,
        OLD.created_by,
        OLD.created_at
      ) THEN
        RAISE EXCEPTION
          'Posted journal entries cannot be edited directly.';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.status = 'voided'::public.journal_entry_status THEN
    IF NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION
        'Voided journal entries are final and cannot be edited.';
    END IF;

    RETURN NEW;
  END IF;

  IF OLD.status = 'reversed'::public.journal_entry_status THEN
    IF NEW IS DISTINCT FROM OLD THEN
      RAISE EXCEPTION
        'Reversed journal entries are final and cannot be edited.';
    END IF;

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_journal_entry_lifecycle_before_update
  ON public.journal_entries;
CREATE TRIGGER enforce_journal_entry_lifecycle_before_update
  BEFORE UPDATE ON public.journal_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_journal_entry_lifecycle();
