-- Trigger: fire send-credit-settlement-email edge function after a CREDIT order settlement
-- Relies on public.invoke_internal_edge_function (vault secrets: project_url, service_role_key)
-- and pg_net (both already enabled in this project).

CREATE OR REPLACE FUNCTION public.handle_credit_settlement_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, net, vault
AS $$
DECLARE
  v_payment_method_name TEXT;
  v_client_id           UUID;
  v_client_email        TEXT;
  v_outlet_id           UUID;
BEGIN
  -- Only proceed for CREDIT settlements
  SELECT name INTO v_payment_method_name
  FROM payment_methods
  WHERE id = NEW.payment_method_id
  LIMIT 1;

  IF v_payment_method_name IS DISTINCT FROM 'CREDIT' THEN
    RETURN NEW;
  END IF;

  -- Get the order's outlet and client (with email)
  SELECT o.outlet_id, o.client_id, c.email
  INTO v_outlet_id, v_client_id, v_client_email
  FROM orders o
  LEFT JOIN clients c ON c.id = o.client_id
  WHERE o.id = NEW.order_id;

  -- Skip if no client or no email
  IF v_client_id IS NULL OR v_client_email IS NULL OR trim(v_client_email) = '' THEN
    RETURN NEW;
  END IF;

  -- Invoke edge function asynchronously via pg_net (fire-and-forget)
  PERFORM public.invoke_internal_edge_function(
    'send-credit-settlement-email',
    jsonb_build_object(
      'order_id',  NEW.order_id::text,
      'outlet_id', v_outlet_id::text
    )
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Non-fatal: log and continue so the settlement is never blocked
    RAISE WARNING 'credit_settlement_email trigger error: %', SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS credit_settlement_email_trigger ON public.order_settlements;

CREATE TRIGGER credit_settlement_email_trigger
  AFTER INSERT ON public.order_settlements
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_credit_settlement_email();
