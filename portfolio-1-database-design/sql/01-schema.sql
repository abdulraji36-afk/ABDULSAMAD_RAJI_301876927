-- Standalone portfolio model. Run once in a fresh disposable PostgreSQL database.
-- Public/auth schemas, live Supabase functions, RLS and external services are outside this model.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
CREATE SCHEMA bilikis;

-- Minimal local identity fixture, not a Supabase authentication implementation.
CREATE TABLE bilikis.auth_users (id uuid PRIMARY KEY);

CREATE TYPE bilikis.app_role AS ENUM ('admin', 'manager', 'storekeeper', 'sales_staff', 'delivery_staff');

CREATE TYPE bilikis.product_transaction_type AS ENUM ('pet_sale', 'rgb_trip');

CREATE TYPE bilikis.customer_channel AS ENUM ('pet_only', 'rgb_only', 'both');

CREATE TYPE bilikis.pet_sale_status AS ENUM ('draft', 'pending_approval', 'approved', 'rejected', 'cancelled');

CREATE TYPE bilikis.payment_type AS ENUM ('cash', 'transfer', 'credit');

CREATE TYPE bilikis.stock_movement_type AS ENUM ('stock_in', 'pet_sale', 'rgb_trip', 'adjustment');

CREATE TYPE bilikis.rgb_sale_status AS ENUM ('pending_dispatch', 'assigned', 'dispatched', 'closed', 'cancelled');

CREATE TYPE bilikis.rgb_dispatch_trip_status AS ENUM ('draft', 'dispatched', 'closed', 'cancelled');

CREATE TYPE bilikis.pet_dispatch_trip_status AS ENUM ('draft', 'dispatched', 'cancelled');

CREATE TYPE bilikis.dispatch_worker_group AS ENUM ('driver', 'worker');

CREATE TABLE bilikis.profiles (
  id uuid NOT NULL,
  full_name text,
  email text,
  role bilikis.app_role NOT NULL DEFAULT 'sales_staff'::bilikis.app_role,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES bilikis.auth_users(id)
);

CREATE TABLE bilikis.products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_code text NOT NULL UNIQUE,
  product_name text NOT NULL,
  category text NOT NULL,
  item_group text NOT NULL,
  size_cl numeric NOT NULL CHECK (size_cl > 0::numeric),
  unit text NOT NULL,
  transaction_type bilikis.product_transaction_type NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  fixed_rgb_price numeric CHECK (fixed_rgb_price IS NULL OR fixed_rgb_price >= 0::numeric),
  image_url text,
  buying_cost numeric CHECK (buying_cost IS NULL OR buying_cost >= 0::numeric),
  fixed_pet_price numeric CHECK (fixed_pet_price IS NULL OR fixed_pet_price >= 0::numeric),
  CONSTRAINT products_pkey PRIMARY KEY (id)
);

CREATE TABLE bilikis.customers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  customer_code text NOT NULL UNIQUE,
  customer_name text NOT NULL,
  customer_type text NOT NULL,
  customer_channel bilikis.customer_channel NOT NULL,
  phone text,
  area text,
  address text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT customers_pkey PRIMARY KEY (id),
  CONSTRAINT customers_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.stock_in (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  stock_in_no text UNIQUE,
  transaction_date date NOT NULL DEFAULT CURRENT_DATE,
  supplier_type text NOT NULL DEFAULT 'NBC'::text,
  nbc_ref text,
  remark text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT stock_in_pkey PRIMARY KEY (id),
  CONSTRAINT stock_in_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.stock_in_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  stock_in_id uuid NOT NULL,
  product_id uuid NOT NULL,
  qty_in numeric NOT NULL CHECK (qty_in > 0::numeric),
  cost_price numeric CHECK (cost_price >= 0::numeric),
  total_cost numeric GENERATED ALWAYS AS (qty_in * cost_price) STORED,
  CONSTRAINT stock_in_items_pkey PRIMARY KEY (id),
  CONSTRAINT stock_in_items_stock_in_id_fkey FOREIGN KEY (stock_in_id) REFERENCES bilikis.stock_in(id),
  CONSTRAINT stock_in_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES bilikis.products(id)
);

CREATE TABLE bilikis.pet_sales (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  request_no text UNIQUE,
  sales_no text UNIQUE,
  transaction_date date NOT NULL DEFAULT CURRENT_DATE,
  customer_id uuid NOT NULL,
  status bilikis.pet_sale_status NOT NULL DEFAULT 'draft'::bilikis.pet_sale_status,
  payment_type bilikis.payment_type NOT NULL,
  remark text,
  requested_by uuid,
  requested_at timestamp with time zone,
  approved_by uuid,
  approved_at timestamp with time zone,
  approval_note text,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  voided_from_status text,
  CONSTRAINT pet_sales_pkey PRIMARY KEY (id),
  CONSTRAINT pet_sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES bilikis.customers(id),
  CONSTRAINT pet_sales_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES bilikis.profiles(id),
  CONSTRAINT pet_sales_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES bilikis.profiles(id),
  CONSTRAINT pet_sales_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.pet_sale_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  pet_sale_id uuid NOT NULL,
  product_id uuid NOT NULL,
  qty_out numeric NOT NULL CHECK (qty_out > 0::numeric),
  approved_unit_price numeric,
  line_total numeric GENERATED ALWAYS AS (COALESCE(approved_unit_price, (0)::numeric) * qty_out) STORED,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT pet_sale_items_pkey PRIMARY KEY (id),
  CONSTRAINT pet_sale_items_pet_sale_id_fkey FOREIGN KEY (pet_sale_id) REFERENCES bilikis.pet_sales(id),
  CONSTRAINT pet_sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES bilikis.products(id)
);

CREATE TABLE bilikis.empty_exchanges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  exchange_no text UNIQUE,
  transaction_date date NOT NULL DEFAULT CURRENT_DATE,
  nbc_delivery_ref text,
  rgb_cases_delivered integer CHECK (rgb_cases_delivered >= 0),
  empties_taken_by_nbc integer NOT NULL CHECK (empties_taken_by_nbc >= 0),
  received_by text,
  remark text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT empty_exchanges_pkey PRIMARY KEY (id),
  CONSTRAINT empty_exchanges_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.stock_movements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  movement_type bilikis.stock_movement_type NOT NULL,
  source_table text NOT NULL,
  source_id uuid NOT NULL,
  qty_in numeric NOT NULL DEFAULT 0,
  qty_out numeric NOT NULL DEFAULT 0,
  unit_cost numeric,
  unit_price numeric,
  transaction_date date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  created_by uuid,
  CONSTRAINT stock_movements_pkey PRIMARY KEY (id),
  CONSTRAINT stock_movements_product_id_fkey FOREIGN KEY (product_id) REFERENCES bilikis.products(id),
  CONSTRAINT stock_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.audit_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  old_values jsonb,
  new_values jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT audit_logs_pkey PRIMARY KEY (id),
  CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.document_sequences (
  sequence_key text NOT NULL,
  sequence_date date NOT NULL,
  last_value integer NOT NULL DEFAULT 0,
  CONSTRAINT document_sequences_pkey PRIMARY KEY (sequence_key, sequence_date)
);

CREATE TABLE bilikis.empty_opening_balance (
  id boolean NOT NULL DEFAULT true CHECK (id = true),
  opening_empties integer NOT NULL DEFAULT 0 CHECK (opening_empties >= 0),
  note text,
  updated_by uuid,
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT empty_opening_balance_pkey PRIMARY KEY (id),
  CONSTRAINT empty_opening_balance_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.rgb_sales (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  sale_no text UNIQUE,
  sale_date date NOT NULL DEFAULT CURRENT_DATE,
  customer_id uuid NOT NULL,
  status bilikis.rgb_sale_status NOT NULL DEFAULT 'pending_dispatch'::bilikis.rgb_sale_status,
  remark text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  voided_from_status text,
  CONSTRAINT rgb_sales_pkey PRIMARY KEY (id),
  CONSTRAINT rgb_sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES bilikis.customers(id),
  CONSTRAINT rgb_sales_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id),
  CONSTRAINT rgb_sales_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.rgb_sale_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  rgb_sale_id uuid NOT NULL,
  product_id uuid NOT NULL,
  qty_out numeric NOT NULL CHECK (qty_out > 0::numeric),
  price_per_crate numeric NOT NULL CHECK (price_per_crate >= 0::numeric),
  line_total numeric GENERATED ALWAYS AS (qty_out * price_per_crate) STORED,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT rgb_sale_items_pkey PRIMARY KEY (id),
  CONSTRAINT rgb_sale_items_rgb_sale_id_fkey FOREIGN KEY (rgb_sale_id) REFERENCES bilikis.rgb_sales(id),
  CONSTRAINT rgb_sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES bilikis.products(id)
);

CREATE TABLE bilikis.rgb_dispatch_trips (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_no text UNIQUE,
  dispatch_date date NOT NULL DEFAULT CURRENT_DATE,
  driver_name text NOT NULL,
  truck_info text NOT NULL,
  status bilikis.rgb_dispatch_trip_status NOT NULL DEFAULT 'draft'::bilikis.rgb_dispatch_trip_status,
  remark text,
  dispatched_at timestamp with time zone,
  closed_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT rgb_dispatch_trips_pkey PRIMARY KEY (id),
  CONSTRAINT rgb_dispatch_trips_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.rgb_dispatch_trip_sales (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  dispatch_trip_id uuid NOT NULL,
  rgb_sale_id uuid NOT NULL UNIQUE,
  expected_empties integer NOT NULL CHECK (expected_empties >= 0),
  actual_empties_returned integer CHECK (actual_empties_returned >= 0),
  returned_at timestamp with time zone,
  remark text,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT rgb_dispatch_trip_sales_pkey PRIMARY KEY (id),
  CONSTRAINT rgb_dispatch_trip_sales_dispatch_trip_id_fkey FOREIGN KEY (dispatch_trip_id) REFERENCES bilikis.rgb_dispatch_trips(id),
  CONSTRAINT rgb_dispatch_trip_sales_rgb_sale_id_fkey FOREIGN KEY (rgb_sale_id) REFERENCES bilikis.rgb_sales(id)
);

CREATE TABLE bilikis.pet_dispatch_trips (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  trip_no text UNIQUE,
  dispatch_date date NOT NULL DEFAULT CURRENT_DATE,
  driver_name text NOT NULL,
  truck_info text NOT NULL,
  status bilikis.pet_dispatch_trip_status NOT NULL DEFAULT 'draft'::bilikis.pet_dispatch_trip_status,
  remark text,
  dispatched_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT pet_dispatch_trips_pkey PRIMARY KEY (id),
  CONSTRAINT pet_dispatch_trips_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.pet_dispatch_trip_sales (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  dispatch_trip_id uuid NOT NULL,
  pet_sale_id uuid NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT pet_dispatch_trip_sales_pkey PRIMARY KEY (id),
  CONSTRAINT pet_dispatch_trip_sales_dispatch_trip_id_fkey FOREIGN KEY (dispatch_trip_id) REFERENCES bilikis.pet_dispatch_trips(id),
  CONSTRAINT pet_dispatch_trip_sales_pet_sale_id_fkey FOREIGN KEY (pet_sale_id) REFERENCES bilikis.pet_sales(id)
);

CREATE TABLE bilikis.empty_adjustments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  adjustment_date date NOT NULL DEFAULT CURRENT_DATE,
  adjustment_type text NOT NULL CHECK (adjustment_type = ANY (ARRAY['purchase'::text, 'correction_add'::text, 'correction_remove'::text, 'damaged_or_lost'::text])),
  quantity_delta integer NOT NULL CHECK (quantity_delta <> 0),
  source_name text,
  note text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT empty_adjustments_pkey PRIMARY KEY (id),
  CONSTRAINT empty_adjustments_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.dispatch_workers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  worker_name text NOT NULL CHECK (length(TRIM(BOTH FROM worker_name)) >= 2),
  worker_group bilikis.dispatch_worker_group NOT NULL,
  phone text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT dispatch_workers_pkey PRIMARY KEY (id),
  CONSTRAINT dispatch_workers_created_by_fkey FOREIGN KEY (created_by) REFERENCES bilikis.auth_users(id)
);

CREATE TABLE bilikis.rgb_empty_return_followups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  dispatch_trip_sale_id uuid NOT NULL,
  quantity integer NOT NULL CHECK (quantity > 0),
  received_date date NOT NULL DEFAULT (timezone('Africa/Lagos'::text, now()))::date,
  remark text,
  recorded_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT rgb_empty_return_followups_pkey PRIMARY KEY (id),
  CONSTRAINT rgb_empty_return_followups_dispatch_trip_sale_id_fkey FOREIGN KEY (dispatch_trip_sale_id) REFERENCES bilikis.rgb_dispatch_trip_sales(id),
  CONSTRAINT rgb_empty_return_followups_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES bilikis.profiles(id)
);

CREATE TABLE bilikis.telegram_notification_settings (
  id boolean NOT NULL DEFAULT true CHECK (id),
  instant_enabled boolean NOT NULL DEFAULT false,
  daily_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT telegram_notification_settings_pkey PRIMARY KEY (id)
);

CREATE TABLE bilikis.telegram_notification_outbox (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  notification_type text NOT NULL CHECK (notification_type = ANY (ARRAY['instant'::text, 'daily'::text])),
  event_type text NOT NULL,
  audit_log_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'dead'::text])),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  locked_at timestamp with time zone,
  locked_by text,
  sent_at timestamp with time zone,
  telegram_message_id bigint,
  last_error text,
  created_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamp with time zone NOT NULL DEFAULT timezone('utc'::text, now()),
  CONSTRAINT telegram_notification_outbox_pkey PRIMARY KEY (id),
  CONSTRAINT telegram_notification_outbox_audit_log_id_fkey FOREIGN KEY (audit_log_id) REFERENCES bilikis.audit_logs(id)
);

CREATE TABLE bilikis.product_display_order (
  id boolean NOT NULL DEFAULT true CHECK (id),
  product_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  CONSTRAINT product_display_order_pkey PRIMARY KEY (id)
);


-- Restore damaged NOT VALID checks using the application's reference migration.
ALTER TABLE bilikis.stock_in ADD CONSTRAINT stock_in_nbc_ref_required
  CHECK (nullif(btrim(nbc_ref), '') IS NOT NULL) NOT VALID;
ALTER TABLE bilikis.empty_exchanges ADD CONSTRAINT empty_exchanges_nbc_delivery_ref_required
  CHECK (nullif(btrim(nbc_delivery_ref), '') IS NOT NULL) NOT VALID;
-- Additional table-level checks present in application migration sources.
ALTER TABLE bilikis.stock_movements ADD CONSTRAINT stock_movement_direction_check
  CHECK ((qty_in >= 0 AND qty_out >= 0) AND NOT (qty_in = 0 AND qty_out = 0));


alter table bilikis.pet_sales
  add constraint pet_sales_void_metadata_check check (
    (
      voided_at is null
      and voided_by is null
      and void_reason is null
      and voided_from_status is null
    )
    or (
      voided_at is not null
      and status = 'cancelled'
      and char_length(btrim(coalesce(void_reason, ''))) >= 10
      and nullif(btrim(voided_from_status), '') is not null
    )
  );

alter table bilikis.rgb_sales
  add constraint rgb_sales_void_metadata_check check (
    (
      voided_at is null
      and voided_by is null
      and void_reason is null
      and voided_from_status is null
    )
    or (
      voided_at is not null
      and status = 'cancelled'
      and char_length(btrim(coalesce(void_reason, ''))) >= 10
      and nullif(btrim(voided_from_status), '') is not null
    )
  );


CREATE OR REPLACE VIEW bilikis.current_stock_view AS
SELECT p.id AS product_id, p.product_code, p.product_name, p.category, p.unit,
       coalesce(sum(sm.qty_in), 0) AS total_in,
       coalesce(sum(sm.qty_out), 0) AS total_out,
       coalesce(sum(sm.qty_in), 0) - coalesce(sum(sm.qty_out), 0) AS current_stock
FROM bilikis.products p
LEFT JOIN bilikis.stock_movements sm ON sm.product_id = p.id
GROUP BY p.id, p.product_code, p.product_name, p.category, p.unit;
COMMIT;
