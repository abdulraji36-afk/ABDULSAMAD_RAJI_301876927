-- Append after loading the Portfolio 1 seed and catalogue-fixture.sql.
-- The real Coca-Cola PET SKU occupies slot 42. The other 119 slots are synthetic.
BEGIN;

INSERT INTO bilikis.customers
  (id, customer_code, customer_name, customer_type, customer_channel, created_at)
SELECT md5('p2-customer-' || n)::uuid,
       'BENCH-CUS-' || lpad(n::text, 4, '0'),
       'Benchmark Customer ' || n, 'retailer', 'pet_only',
       TIMESTAMPTZ '2024-12-31 00:00:00+00'
FROM generate_series(1, 400) AS g(n);

INSERT INTO bilikis.products
  (id, product_code, product_name, category, item_group, size_cl, unit,
   transaction_type, buying_cost, fixed_pet_price, created_at)
SELECT md5('p2-product-' || n)::uuid,
       'BENCH-PET-' || lpad(n::text, 4, '0'),
       'Benchmark Beverage ' || n, 'PET', 'Beverage', 50, 'pack',
       'pet_sale', 1200 + n, 1800 + n, TIMESTAMPTZ '2024-12-31 00:00:00+00'
FROM generate_series(1, 120) AS g(n)
WHERE n <> 42;

INSERT INTO bilikis.stock_in (id, stock_in_no, transaction_date, nbc_ref, created_at)
VALUES (md5('p2-stock-receipt')::uuid, 'BENCH-OPENING', DATE '2024-12-31',
        'BENCH-NBC-OPENING', TIMESTAMPTZ '2024-12-31 00:00:00+00');

INSERT INTO bilikis.stock_in_items (id, stock_in_id, product_id, qty_in, cost_price)
SELECT md5('p2-receipt-item-' || product_code)::uuid,
       md5('p2-stock-receipt')::uuid, id, 10000, buying_cost
FROM bilikis.products
WHERE product_code LIKE 'BENCH-PET-%' OR product_code = 'C_PET_50';

INSERT INTO bilikis.stock_movements
  (id, product_id, movement_type, source_table, source_id, qty_in, qty_out,
   transaction_date, created_at)
SELECT md5('p2-opening-' || i.product_id)::uuid, i.product_id, 'stock_in',
       'stock_in', i.stock_in_id, i.qty_in, 0, s.transaction_date, s.created_at
FROM bilikis.stock_in_items AS i
JOIN bilikis.stock_in AS s ON s.id = i.stock_in_id
WHERE s.stock_in_no = 'BENCH-OPENING';

WITH generated_sales AS (
  SELECT n, DATE '2025-01-01' + (n * 37 % 730) AS sale_date
  FROM generate_series(1, 60000) AS g(n)
)
INSERT INTO bilikis.pet_sales
  (id, request_no, sales_no, transaction_date, customer_id, status,
   payment_type, created_at, updated_at)
SELECT md5('p2-sale-' || n)::uuid,
       'BENCH-REQ-' || lpad(n::text, 6, '0'),
       'BENCH-PET-SALE-' || lpad(n::text, 6, '0'),
       sale_date, md5('p2-customer-' || (n % 400 + 1))::uuid,
       (CASE WHEN n % 23 = 0 THEN 'cancelled' ELSE 'approved' END)::bilikis.pet_sale_status,
       'transfer', sale_date::timestamptz, sale_date::timestamptz
FROM generated_sales;

INSERT INTO bilikis.pet_sale_items
  (id, pet_sale_id, product_id, qty_out, approved_unit_price, created_at)
SELECT md5('p2-line-' || g.n)::uuid, s.id, p.id, g.n % 9 + 1,
       p.fixed_pet_price, s.created_at
FROM generate_series(1, 60000) AS g(n)
JOIN bilikis.pet_sales AS s ON s.id = md5('p2-sale-' || g.n)::uuid
JOIN bilikis.products AS p ON p.id = CASE
  WHEN g.n * 17 % 120 + 1 = 42 THEN (SELECT id FROM bilikis.products WHERE product_code = 'C_PET_50')
  ELSE md5('p2-product-' || (g.n * 17 % 120 + 1))::uuid
END;

-- Cancelled sales stay in history and do not issue stock in this fixture.
INSERT INTO bilikis.stock_movements
  (id, product_id, movement_type, source_table, source_id, qty_in, qty_out,
   transaction_date, created_at)
SELECT md5('p2-issue-' || s.id)::uuid, i.product_id, 'pet_sale',
       'pet_sales', s.id, 0, i.qty_out, s.transaction_date, s.created_at
FROM bilikis.pet_sales AS s
JOIN bilikis.pet_sale_items AS i ON i.pet_sale_id = s.id
WHERE s.sales_no LIKE 'BENCH-PET-SALE-%' AND s.status = 'approved';

COMMIT;
