-- Project the priced, posted sales from the same fixture used in Portfolio 2.
WITH followups AS (
  SELECT dispatch_trip_sale_id, sum(quantity) AS returned
  FROM bilikis.rgb_empty_return_followups
  GROUP BY dispatch_trip_sale_id
), sale_headers AS (
  SELECT 'PET' AS channel, s.id, s.sales_no AS sale_number, s.transaction_date AS sale_date,
         c.customer_code, s.status::text, CASE WHEN t.id IS NOT NULL THEN
           jsonb_build_object('tripNumber', t.trip_no, 'tripStatus', t.status)
         END AS dispatch
  FROM bilikis.pet_sales AS s
  JOIN bilikis.customers AS c ON c.id = s.customer_id
  LEFT JOIN bilikis.pet_dispatch_trip_sales AS a ON a.pet_sale_id = s.id
  LEFT JOIN bilikis.pet_dispatch_trips AS t ON t.id = a.dispatch_trip_id
  WHERE s.status = 'approved' AND s.voided_at IS NULL AND s.sales_no IS NOT NULL
  UNION ALL
  SELECT 'RGB', s.id, s.sale_no, s.sale_date, c.customer_code, s.status::text,
         CASE WHEN t.id IS NOT NULL THEN jsonb_build_object(
           'tripNumber', t.trip_no, 'tripStatus', t.status,
           'expectedEmpties', a.expected_empties,
           'initialReturns', coalesce(a.actual_empties_returned, 0),
           'followupReturns', coalesce(f.returned, 0)
         ) END
  FROM bilikis.rgb_sales AS s
  JOIN bilikis.customers AS c ON c.id = s.customer_id
  LEFT JOIN bilikis.rgb_dispatch_trip_sales AS a ON a.rgb_sale_id = s.id
  LEFT JOIN bilikis.rgb_dispatch_trips AS t ON t.id = a.dispatch_trip_id
  LEFT JOIN followups AS f ON f.dispatch_trip_sale_id = a.id
  WHERE s.status IN ('dispatched', 'closed') AND s.voided_at IS NULL AND s.sale_no IS NOT NULL
), priced_lines AS (
  SELECT 'PET' AS channel, id, pet_sale_id AS sale_id, product_id,
         qty_out AS quantity, approved_unit_price AS unit_price
  FROM bilikis.pet_sale_items
  WHERE approved_unit_price IS NOT NULL
  UNION ALL
  SELECT 'RGB', id, rgb_sale_id, product_id, qty_out, price_per_crate
  FROM bilikis.rgb_sale_items
)
SELECT h.channel, h.id::text AS source_id, h.sale_number, h.sale_date::text,
       h.customer_code, h.status, h.dispatch,
       jsonb_agg(jsonb_build_object(
         'productCode', p.product_code, 'productName', p.product_name, 'unit', p.unit,
         'quantity', l.quantity::text, 'unitPrice', l.unit_price::text
       ) ORDER BY l.id) AS line_items
FROM sale_headers AS h
JOIN priced_lines AS l ON l.channel = h.channel AND l.sale_id = h.id
JOIN bilikis.products AS p ON p.id = l.product_id
GROUP BY h.channel, h.id, h.sale_number, h.sale_date, h.customer_code, h.status, h.dispatch
ORDER BY h.channel, h.sale_number;
