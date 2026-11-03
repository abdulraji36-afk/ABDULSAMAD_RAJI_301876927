-- Create the same report table on the publisher and subscriber.
CREATE TABLE bilikis.stock_report (
  product_code text PRIMARY KEY,
  product_name text NOT NULL,
  unit text NOT NULL,
  current_stock numeric NOT NULL,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  refreshed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
