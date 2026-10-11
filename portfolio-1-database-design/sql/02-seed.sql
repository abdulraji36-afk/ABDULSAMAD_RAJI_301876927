-- Deterministic synthetic fixtures; no real customer, employee or payment data.
-- Run once after 01-schema.sql in a fresh disposable database.
BEGIN;
SET LOCAL TIME ZONE 'UTC';

INSERT INTO bilikis.auth_users VALUES
('00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000002');
INSERT INTO bilikis.profiles (id, full_name, email, role) VALUES
('00000000-0000-0000-0000-000000000001', 'Demo Administrator', 'admin@example.invalid', 'admin'),
('00000000-0000-0000-0000-000000000002', 'Demo Storekeeper', 'staff@example.invalid', 'storekeeper');

INSERT INTO bilikis.products
(id, product_code, product_name, category, item_group, size_cl, unit, transaction_type, buying_cost, fixed_pet_price, fixed_rgb_price) VALUES
('00000000-0000-0000-0000-000000000101', 'DEMO-PET-50', 'Demo Cola PET 50cl', 'PET', 'Beverage', 50, 'pack', 'pet_sale', 1500, 2000, NULL),
('00000000-0000-0000-0000-000000000102', 'DEMO-RGB-35', 'Demo Cola RGB 35cl', 'RGB', 'Beverage', 35, 'crate', 'rgb_trip', 6200, NULL, 7000),
('00000000-0000-0000-0000-000000000103', 'DEMO-PET-60', 'Demo Orange PET 60cl', 'PET', 'Beverage', 60, 'pack', 'pet_sale', NULL, 2500, NULL);
INSERT INTO bilikis.customers
(id, customer_code, customer_name, customer_type, customer_channel, area, created_by) VALUES
('00000000-0000-0000-0000-000000000201', 'DEMO-CUS-001', 'Demo Customer A', 'retailer', 'both', 'Demo Area A', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000202', 'DEMO-CUS-002', 'Demo Customer B', 'retailer', 'both', 'Demo Area B', '00000000-0000-0000-0000-000000000002');

INSERT INTO bilikis.stock_in (id, stock_in_no, transaction_date, nbc_ref, created_by) VALUES
('00000000-0000-0000-0000-000000000301', 'DEMO-STK-001', '2026-10-01', 'DEMO-NBC-001', '00000000-0000-0000-0000-000000000002');
INSERT INTO bilikis.stock_in_items (id, stock_in_id, product_id, qty_in, cost_price) VALUES
('00000000-0000-0000-0000-000000000311', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000101', 100, 1500),
('00000000-0000-0000-0000-000000000312', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000102', 80, 6200),
('00000000-0000-0000-0000-000000000313', '00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000103', 30, NULL);

INSERT INTO bilikis.pet_sales
(id, request_no, sales_no, transaction_date, customer_id, status, payment_type, requested_by, requested_at, approved_by, approved_at) VALUES
('00000000-0000-0000-0000-000000000401', 'DEMO-REQ-001', 'DEMO-PET-001', '2026-10-05', '00000000-0000-0000-0000-000000000201', 'approved', 'cash', '00000000-0000-0000-0000-000000000002', '2026-10-05T08:00:00Z', '00000000-0000-0000-0000-000000000001', '2026-10-05T08:01:00Z'),
('00000000-0000-0000-0000-000000000402', 'DEMO-REQ-002', 'DEMO-PET-002', '2026-10-05', '00000000-0000-0000-0000-000000000202', 'approved', 'transfer', '00000000-0000-0000-0000-000000000002', '2026-10-05T09:00:00Z', '00000000-0000-0000-0000-000000000001', '2026-10-05T09:01:00Z');
INSERT INTO bilikis.pet_sale_items (id, pet_sale_id, product_id, qty_out, approved_unit_price) VALUES
('00000000-0000-0000-0000-000000000411', '00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000101', 10, 2000),
('00000000-0000-0000-0000-000000000412', '00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000101', 5, 2000);
INSERT INTO bilikis.pet_dispatch_trips
(id, trip_no, dispatch_date, driver_name, truck_info, status, dispatched_at, created_by) VALUES
('00000000-0000-0000-0000-000000000701', 'DEMO-PDT-001', '2026-10-06', 'Demo Driver', 'Demo Truck 01', 'dispatched', '2026-10-06T08:00:00Z', '00000000-0000-0000-0000-000000000002');
INSERT INTO bilikis.pet_dispatch_trip_sales (id, dispatch_trip_id, pet_sale_id) VALUES
('00000000-0000-0000-0000-000000000711', '00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-000000000401'),
('00000000-0000-0000-0000-000000000712', '00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-000000000402');

INSERT INTO bilikis.rgb_sales (id, sale_no, sale_date, customer_id, status, created_by) VALUES
('00000000-0000-0000-0000-000000000501', 'DEMO-RGB-001', '2026-10-07', '00000000-0000-0000-0000-000000000201', 'closed', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000502', 'DEMO-RGB-002', '2026-10-07', '00000000-0000-0000-0000-000000000202', 'closed', '00000000-0000-0000-0000-000000000002');
INSERT INTO bilikis.rgb_sale_items (id, rgb_sale_id, product_id, qty_out, price_per_crate) VALUES
('00000000-0000-0000-0000-000000000511', '00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000102', 12, 7000),
('00000000-0000-0000-0000-000000000512', '00000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-000000000102', 8, 7000);
INSERT INTO bilikis.rgb_dispatch_trips
(id, trip_no, dispatch_date, driver_name, truck_info, status, dispatched_at, closed_at, created_by) VALUES
('00000000-0000-0000-0000-000000000601', 'DEMO-RDT-001', '2026-10-08', 'Demo Driver', 'Demo Truck 01', 'closed', '2026-10-08T08:00:00Z', '2026-10-08T18:00:00Z', '00000000-0000-0000-0000-000000000002');
INSERT INTO bilikis.rgb_dispatch_trip_sales
(id, dispatch_trip_id, rgb_sale_id, expected_empties, actual_empties_returned, returned_at) VALUES
('00000000-0000-0000-0000-000000000611', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000501', 12, 8, '2026-10-08T18:00:00Z'),
('00000000-0000-0000-0000-000000000612', '00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000502', 8, 8, '2026-10-08T18:00:00Z');
INSERT INTO bilikis.rgb_empty_return_followups
(id, dispatch_trip_sale_id, quantity, received_date, recorded_by) VALUES
('00000000-0000-0000-0000-000000000621', '00000000-0000-0000-0000-000000000611', 2, '2026-10-09', '00000000-0000-0000-0000-000000000001');
INSERT INTO bilikis.empty_opening_balance (id, opening_empties, note, updated_by) VALUES
(true, 40, 'Synthetic opening baseline', '00000000-0000-0000-0000-000000000001');
INSERT INTO bilikis.empty_exchanges
(id, exchange_no, transaction_date, nbc_delivery_ref, rgb_cases_delivered, empties_taken_by_nbc, created_by) VALUES
('00000000-0000-0000-0000-000000000801', 'DEMO-EX-001', '2026-10-10', 'DEMO-NBC-EX-001', 0, 10, '00000000-0000-0000-0000-000000000002');
INSERT INTO bilikis.empty_adjustments
(id, adjustment_date, adjustment_type, quantity_delta, source_name, note, created_by) VALUES
('00000000-0000-0000-0000-000000000811', '2026-10-10', 'purchase', 5, 'Demo supplier', 'Synthetic purchase of empty containers', '00000000-0000-0000-0000-000000000001');
INSERT INTO bilikis.dispatch_workers (id, worker_name, worker_group, created_by) VALUES
('00000000-0000-0000-0000-000000000821', 'Demo Driver', 'driver', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000822', 'Demo Loader', 'worker', '00000000-0000-0000-0000-000000000001');

-- Explicit fixture movements. No production stock triggers are assumed here.
INSERT INTO bilikis.stock_movements
(id, product_id, movement_type, source_table, source_id, qty_in, qty_out, transaction_date, created_by) VALUES
('00000000-0000-0000-0000-000000000901', '00000000-0000-0000-0000-000000000101', 'stock_in', 'stock_in', '00000000-0000-0000-0000-000000000301', 100, 0, '2026-10-01', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000902', '00000000-0000-0000-0000-000000000102', 'stock_in', 'stock_in', '00000000-0000-0000-0000-000000000301', 80, 0, '2026-10-01', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000903', '00000000-0000-0000-0000-000000000103', 'stock_in', 'stock_in', '00000000-0000-0000-0000-000000000301', 30, 0, '2026-10-01', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000904', '00000000-0000-0000-0000-000000000101', 'pet_sale', 'pet_sales', '00000000-0000-0000-0000-000000000401', 0, 10, '2026-10-05', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000905', '00000000-0000-0000-0000-000000000101', 'pet_sale', 'pet_sales', '00000000-0000-0000-0000-000000000402', 0, 5, '2026-10-05', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000906', '00000000-0000-0000-0000-000000000102', 'rgb_trip', 'rgb_sales', '00000000-0000-0000-0000-000000000501', 0, 12, '2026-10-07', '00000000-0000-0000-0000-000000000002'),
('00000000-0000-0000-0000-000000000907', '00000000-0000-0000-0000-000000000102', 'rgb_trip', 'rgb_sales', '00000000-0000-0000-0000-000000000502', 0, 8, '2026-10-07', '00000000-0000-0000-0000-000000000002');
INSERT INTO bilikis.audit_logs (id, user_id, action, entity_type, entity_id, old_values, new_values) VALUES
('00000000-0000-0000-0000-000000001001', '00000000-0000-0000-0000-000000000001', 'synthetic_example', 'rgb_sales', '00000000-0000-0000-0000-000000000501', '{"status":"dispatched"}', '{"status":"closed"}');
INSERT INTO bilikis.document_sequences (sequence_key, sequence_date, last_value) VALUES
('pet_sale', '2026-10-05', 2), ('rgb_sale', '2026-10-07', 2);
INSERT INTO bilikis.telegram_notification_settings (id, instant_enabled, daily_enabled) VALUES (true, false, false);
INSERT INTO bilikis.telegram_notification_outbox
(id, event_key, notification_type, event_type, audit_log_id, payload) VALUES
('00000000-0000-0000-0000-000000001011', 'DEMO-EVENT-001', 'instant', 'synthetic_example', '00000000-0000-0000-0000-000000001001', '{"synthetic":true,"sale_no":"DEMO-RGB-001"}');
INSERT INTO bilikis.product_display_order (id, product_ids) VALUES
(true, ARRAY['00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000103']::uuid[]);
COMMIT;
