-- inventory_stock_transfers: allow deleting drafts only
CREATE POLICY "Users can delete draft stock transfers in their company"
  ON public.inventory_stock_transfers
  FOR DELETE
  USING (
    company_id = get_auth_user_company_id()
    AND status = 'draft'::stock_transfer_status
  );

-- inventory_stock_adjustments: allow deleting drafts only
CREATE POLICY "Users can delete draft stock adjustments in their company"
  ON public.inventory_stock_adjustments
  FOR DELETE
  USING (
    company_id = get_auth_user_company_id()
    AND status = 'draft'::stock_adjustment_status
  );

-- supplier_payments: intentionally no DELETE policy
-- RLS is enabled so all deletes are blocked by default — correct for financial records
