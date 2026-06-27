-- Migration: Create reverse journal entry RPC
-- Created: 2026-05-18
-- Description:
--   - Adds reverse_journal_entry RPC for atomic journal reversal
--   - Creates reversing lines, posts the reversal entry, and marks the original as reversed

CREATE OR REPLACE FUNCTION public.reverse_journal_entry(
  p_company_id BIGINT,
  p_journal_entry_id UUID,
  p_reversal_date DATE DEFAULT CURRENT_DATE,
  p_memo TEXT DEFAULT NULL
)
RETURNS public.journal_entries
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_company_id BIGINT;
  v_original_entry public.journal_entries;
  v_reversal_entry public.journal_entries;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_user_company_id := public.get_auth_user_company_id();
  IF v_user_company_id IS NULL THEN
    RAISE EXCEPTION 'Unable to resolve company for current user';
  END IF;

  IF v_user_company_id <> p_company_id THEN
    RAISE EXCEPTION 'Journal entry is not accessible for the current user';
  END IF;

  SELECT je.*
  INTO v_original_entry
  FROM public.journal_entries je
  WHERE je.company_id = p_company_id
    AND je.id = p_journal_entry_id
  FOR UPDATE;

  IF v_original_entry.id IS NULL THEN
    RAISE EXCEPTION 'Journal entry % does not exist', p_journal_entry_id;
  END IF;

  IF v_original_entry.status <> 'posted'::public.journal_entry_status THEN
    RAISE EXCEPTION 'Only posted journal entries can be reversed';
  END IF;

  IF v_original_entry.reversed_by_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Journal entry % has already been reversed', p_journal_entry_id;
  END IF;

  INSERT INTO public.journal_entries (
    company_id,
    outlet_id,
    posting_scope,
    reference_type,
    reference_id,
    source_module,
    entry_date,
    memo,
    status,
    created_by
  )
  VALUES (
    v_original_entry.company_id,
    v_original_entry.outlet_id,
    v_original_entry.posting_scope,
    v_original_entry.reference_type,
    v_original_entry.reference_id,
    v_original_entry.source_module,
    p_reversal_date,
    COALESCE(
      NULLIF(BTRIM(p_memo), ''),
      'Reversal of journal entry ' || v_original_entry.id::TEXT
    ),
    'draft'::public.journal_entry_status,
    v_user_id
  )
  RETURNING *
  INTO v_reversal_entry;

  INSERT INTO public.journal_entry_lines (
    company_id,
    journal_entry_id,
    account_id,
    outlet_id,
    debit,
    credit,
    description,
    created_by
  )
  SELECT
    jel.company_id,
    v_reversal_entry.id,
    jel.account_id,
    jel.outlet_id,
    jel.credit,
    jel.debit,
    CASE
      WHEN jel.description IS NULL OR BTRIM(jel.description) = '' THEN
        'Reversal line for journal entry ' || v_original_entry.id::TEXT
      ELSE
        'Reversal: ' || jel.description
    END,
    v_user_id
  FROM public.journal_entry_lines jel
  WHERE jel.company_id = p_company_id
    AND jel.journal_entry_id = p_journal_entry_id;

  UPDATE public.journal_entries
  SET
    reversal_of_journal_entry_id = v_original_entry.id,
    status = 'posted'::public.journal_entry_status
  WHERE company_id = p_company_id
    AND id = v_reversal_entry.id
  RETURNING *
  INTO v_reversal_entry;

  UPDATE public.journal_entries
  SET
    status = 'reversed'::public.journal_entry_status,
    reversed_by_journal_entry_id = v_reversal_entry.id,
    reversed_at = NOW(),
    reversed_by = v_user_id
  WHERE company_id = p_company_id
    AND id = v_original_entry.id;

  RETURN v_reversal_entry;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reverse_journal_entry(BIGINT, UUID, DATE, TEXT) TO authenticated;
