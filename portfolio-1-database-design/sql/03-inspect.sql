-- Run after 01-schema.sql and 02-seed.sql. Read-only inspection.
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'bilikis' AND table_type = 'BASE TABLE' ORDER BY table_name;

SELECT tc.table_name, tc.constraint_name, tc.constraint_type
FROM information_schema.table_constraints tc
WHERE tc.table_schema = 'bilikis' ORDER BY tc.table_name, tc.constraint_name;

SELECT table_name, column_name, data_type, is_nullable, is_generated, generation_expression
FROM information_schema.columns WHERE table_schema = 'bilikis'
ORDER BY table_name, ordinal_position;

SELECT product_code, total_in, total_out, current_stock
FROM bilikis.current_stock_view ORDER BY product_code;

SELECT c.customer_code, rs.sale_no, a.expected_empties, a.actual_empties_returned,
       coalesce(f.followup_returned, 0) AS followup_returned,
       a.expected_empties - coalesce(a.actual_empties_returned, 0) - coalesce(f.followup_returned, 0) AS outstanding
FROM bilikis.rgb_dispatch_trip_sales a
JOIN bilikis.rgb_sales rs ON rs.id = a.rgb_sale_id
JOIN bilikis.customers c ON c.id = rs.customer_id
LEFT JOIN (
  SELECT dispatch_trip_sale_id, sum(quantity) AS followup_returned
  FROM bilikis.rgb_empty_return_followups GROUP BY dispatch_trip_sale_id
) f ON f.dispatch_trip_sale_id = a.id
WHERE rs.voided_at IS NULL AND rs.status <> 'cancelled'
ORDER BY rs.sale_no;
