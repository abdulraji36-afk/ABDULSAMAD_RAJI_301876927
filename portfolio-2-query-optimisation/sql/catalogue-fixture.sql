-- Apply after the Portfolio 1 seed in the disposable Portfolio 2 database.
-- Catalogue codes, names, sizes and units are from the supplied three-row export.
-- The seed supplies the example prices, costs, transactions and quantities.
UPDATE bilikis.products AS p
SET product_code = catalogue.product_code,
    product_name = catalogue.product_name,
    size_cl = catalogue.size_cl,
    unit = catalogue.unit
FROM (VALUES
  ('DEMO-PET-50', 'C_PET_50', 'COCA COLA LS 50CL X12 PET', 50, 'Packs'),
  ('DEMO-PET-60', 'F_PET_50', 'FANTA ORANGE 50CL X12 PET', 50, 'Packs'),
  ('DEMO-RGB-35', 'C_RGB', 'COCA COLA ULTRA LS 50CL X24 RGB', 50, 'Crates')
) AS catalogue (seed_code, product_code, product_name, size_cl, unit)
WHERE p.product_code = catalogue.seed_code;
