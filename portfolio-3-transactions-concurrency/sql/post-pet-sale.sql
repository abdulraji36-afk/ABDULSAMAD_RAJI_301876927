-- Load only into the disposable Portfolio 3 database.
-- The caller controls the transaction. Every stock issuer in this exercise
-- locks the same product row before reading and changing its stock.
CREATE FUNCTION bilikis.p3_post_pet_sale(
  p_sale_no text,
  p_customer_code text,
  p_product_code text,
  p_quantity integer
) RETURNS uuid
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  v_product_id uuid;
  v_customer_id uuid;
  v_price numeric;
  v_available numeric;
  v_sale_id uuid;
BEGIN
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'The Portfolio 3 stock routine requires READ COMMITTED';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR nullif(btrim(p_sale_no), '') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'A sale number and positive quantity are required';
  END IF;

  SELECT c.id INTO v_customer_id
  FROM bilikis.customers AS c
  WHERE c.customer_code = p_customer_code AND c.is_active
    AND c.customer_channel IN ('pet_only', 'both');
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Unknown or inactive PET customer';
  END IF;

  SELECT p.id, p.fixed_pet_price INTO v_product_id, v_price
  FROM bilikis.products AS p
  WHERE p.product_code = p_product_code AND p.is_active AND p.transaction_type = 'pet_sale'
  FOR UPDATE;
  IF NOT FOUND OR v_price IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Unknown, inactive, or unpriced PET product';
  END IF;

  -- Use a separate statement after acquiring the lock. In READ COMMITTED
  -- this query sees any stock change committed by the previous lock holder.
  SELECT coalesce(sum(m.qty_in - m.qty_out), 0) INTO v_available
  FROM bilikis.stock_movements AS m
  WHERE m.product_id = v_product_id;
  IF v_available < p_quantity THEN
    RAISE EXCEPTION USING ERRCODE = 'P3001',
      MESSAGE = format('Insufficient stock for %s: available %s, requested %s',
                       p_product_code, v_available, p_quantity);
  END IF;

  INSERT INTO bilikis.pet_sales
    (sales_no, transaction_date, customer_id, status, payment_type)
  VALUES (p_sale_no, CURRENT_DATE, v_customer_id, 'approved', 'cash')
  RETURNING id INTO v_sale_id;

  INSERT INTO bilikis.pet_sale_items
    (pet_sale_id, product_id, qty_out, approved_unit_price)
  VALUES (v_sale_id, v_product_id, p_quantity, v_price);

  INSERT INTO bilikis.stock_movements
    (product_id, movement_type, source_table, source_id, qty_in, qty_out, transaction_date)
  VALUES (v_product_id, 'pet_sale', 'pet_sales', v_sale_id, 0, p_quantity, CURRENT_DATE);

  RETURN v_sale_id;
END;
$$;
