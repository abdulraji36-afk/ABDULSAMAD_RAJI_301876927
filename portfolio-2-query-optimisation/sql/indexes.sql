-- Apply after collecting baseline plans in the same disposable database.
-- Customer equality, date range, and descending order for the top-20 history.
CREATE INDEX p2_pet_sales_customer_date_idx
ON bilikis.pet_sales (customer_id, transaction_date DESC, id DESC)
WHERE status = 'approved' AND voided_at IS NULL;

-- Product equality followed by the bounded ledger date range.
CREATE INDEX p2_stock_movements_product_date_idx
ON bilikis.stock_movements (product_id, transaction_date);
