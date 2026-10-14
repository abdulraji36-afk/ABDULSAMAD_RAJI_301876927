-- Execute each named SELECT separately with its bound parameters.
-- Date windows include the start date and exclude the end date.

-- report: low-stock
-- $1: stock threshold in each product's own unit.
SELECT product_code, product_name, unit, current_stock
FROM bilikis.current_stock_view
WHERE current_stock < $1::numeric
ORDER BY current_stock, product_code;

-- report: sales-by-channel
-- $1: start date. $2: end date.
-- Count sales with priced lines and use the recorded line values.
WITH priced_lines AS (
  SELECT 'PET' AS channel, s.id AS sale_id, i.line_total
  FROM bilikis.pet_sales AS s
  JOIN bilikis.pet_sale_items AS i ON i.pet_sale_id = s.id
  WHERE s.transaction_date >= $1::date AND s.transaction_date < $2::date
    AND s.status = 'approved' AND s.voided_at IS NULL
    AND i.approved_unit_price IS NOT NULL
  UNION ALL
  SELECT 'RGB', s.id, i.line_total
  FROM bilikis.rgb_sales AS s
  JOIN bilikis.rgb_sale_items AS i ON i.rgb_sale_id = s.id
  WHERE s.sale_date >= $1::date AND s.sale_date < $2::date
    AND s.status IN ('dispatched', 'closed') AND s.voided_at IS NULL
)
SELECT channel, count(DISTINCT sale_id)::integer AS sale_count,
       sum(line_total) AS recorded_sales_value
FROM priced_lines
GROUP BY channel
ORDER BY channel;

-- report: rgb-shortages
-- Group follow-ups before joining so each initial return is counted once.
WITH followups AS (
  SELECT dispatch_trip_sale_id, sum(quantity) AS additional_returns
  FROM bilikis.rgb_empty_return_followups
  GROUP BY dispatch_trip_sale_id
), balances AS (
  SELECT c.customer_code, s.sale_no, a.expected_empties,
         coalesce(a.actual_empties_returned, 0) AS initial_returns,
         coalesce(f.additional_returns, 0) AS additional_returns,
         a.expected_empties - coalesce(a.actual_empties_returned, 0)
           - coalesce(f.additional_returns, 0) AS outstanding
  FROM bilikis.rgb_dispatch_trip_sales AS a
  JOIN bilikis.rgb_sales AS s ON s.id = a.rgb_sale_id
  JOIN bilikis.customers AS c ON c.id = s.customer_id
  LEFT JOIN followups AS f ON f.dispatch_trip_sale_id = a.id
  WHERE s.status IN ('dispatched', 'closed') AND s.voided_at IS NULL
)
SELECT customer_code, sale_no, expected_empties, initial_returns,
       additional_returns, outstanding
FROM balances
WHERE outstanding > 0
ORDER BY outstanding DESC, sale_no NULLS LAST, customer_code;

-- report: stock-valuation
-- A missing buying cost leaves the valuation unknown.
SELECT p.product_code, p.product_name, stock.unit, stock.current_stock, p.buying_cost,
       stock.current_stock * p.buying_cost AS estimated_stock_value
FROM bilikis.current_stock_view AS stock
JOIN bilikis.products AS p ON p.id = stock.product_id
ORDER BY p.product_code;

-- report: customer-pet-history
-- $1: customer code. $2: start date. $3: end date.
-- The UUID breaks ties on a sale date, giving a stable top-20 order.
SELECT s.id, s.sales_no, s.transaction_date::text AS sale_date, s.payment_type
FROM bilikis.pet_sales AS s
WHERE s.customer_id = (
  SELECT id FROM bilikis.customers WHERE customer_code = $1::text
)
  AND s.status = 'approved' AND s.voided_at IS NULL
  AND s.transaction_date >= $2::date AND s.transaction_date < $3::date
ORDER BY s.transaction_date DESC, s.id DESC
LIMIT 20;

-- report: product-movement-period
-- $1: product code. $2: start date. $3: end date.
-- Net movement is the period change, rather than the all-time stock balance.
SELECT count(*)::integer AS movement_count,
       coalesce(sum(m.qty_in), 0) AS received,
       coalesce(sum(m.qty_out), 0) AS issued,
       coalesce(sum(m.qty_in - m.qty_out), 0) AS net_movement
FROM bilikis.stock_movements AS m
WHERE m.product_id = (
  SELECT id FROM bilikis.products WHERE product_code = $1::text
)
  AND m.transaction_date >= $2::date AND m.transaction_date < $3::date;
