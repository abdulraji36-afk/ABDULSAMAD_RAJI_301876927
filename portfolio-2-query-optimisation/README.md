# Portfolio 2 — Query Processing and Optimisation

Bilikis Store needs reports for stock levels, recorded sales, empty-container shortages, inventory value, customer history, and product movements. This portfolio runs those reports on the Portfolio 1 schema and measures two targeted indexes. [SQL queries](sql/queries.sql)

## Business queries

The six checks use the small Portfolio 1 fixture with three products from the supplied Bilikis catalogue. The product codes, names, sizes, and units come from the catalogue. All transactions, quantities, prices, and costs are synthetic. The date examples cover 1 October through 31 October 2026 using an inclusive start and exclusive end. [Catalogue fixture SQL](sql/catalogue-fixture.sql)

| Code | Catalogue name | Size | Unit |
|---|---|---:|---|
| `C_PET_50` | COCA COLA LS 50CL X12 PET | 50 cl | Packs |
| `F_PET_50` | FANTA ORANGE 50CL X12 PET | 50 cl | Packs |
| `C_RGB` | COCA COLA ULTRA LS 50CL X24 RGB | 50 cl | Crates |

| Report | Example input | Checked result |
|---|---|---|
| Low stock | Fewer than 50 units | `F_PET_50` has 30 packs |
| Sales by channel | October 2026 | PET has 2 sales valued at 30,000. RGB has 2 valued at 140,000 |
| RGB shortages | Dispatched or closed sales | `DEMO-RGB-001` has 2 empties outstanding after 8 initial and 2 additional returns |
| Stock valuation | All fixture products | Known values total 499,500. The 30 packs of `F_PET_50` have a pending cost |
| Customer PET history | `DEMO-CUS-001`, October 2026 | `DEMO-PET-001` on 5 October |
| Product movement | `C_PET_50`, October 2026 | 3 movements, 100 packs received, 15 issued, and a net increase of 85 |

The sales report counts distinct sales with priced lines. It excludes voided sales and uses approved PET sales and dispatched or closed RGB sales. The shortage report aggregates follow-up returns before joining to each dispatch assignment. Valuation leaves a missing buying cost as `NULL`.

## Index experiment

The benchmark adds 400 synthetic customers, 119 synthetic PET products, and 60,000 synthetic PET sales to the small fixture. The sales are distributed across the 119 new products and `C_PET_50`. The combined dataset contains **60,002 PET sales**, **60,002 PET sale lines**, and **57,519 stock movements**. A deterministic generator assigns dates, customers, products, and quantities. It records opening receipts and creates stock issues for approved sales. [Benchmark data SQL](sql/benchmark-fixture.sql)

Both measurements use the same input, data, and query text. The baseline keeps the schema's primary key and unique indexes. PostgreSQL collects statistics before the baseline. The indexed phase adds two B-tree indexes. Each phase runs two warm-ups and records the next seven executions with `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)`. The table uses the median execution time and the shared buffer accesses from its plan. Shared accesses count hits and reads at the root plan node. [Index SQL](sql/indexes.sql) · [PostgreSQL EXPLAIN reference](https://www.postgresql.org/docs/18/sql-explain.html)

| Query and inputs | Baseline access | Indexed access | Median execution before → after | Shared buffer accesses before → after |
|---|---|---|---:|---:|
| PET history for `BENCH-CUS-0042`, 1 July to 1 November 2026 | Sequential scan of `pet_sales`, then sort | Index scan in the requested order | 8.457 → 0.097 ms | 1,038 → 27 |
| Movement for `C_PET_50`, same dates | Sequential scan of `stock_movements` | Bitmap index scan and bitmap heap scan | 6.610 → 0.182 ms | 888 → 83 |

**Customer history.** The partial index starts with customer ID, then uses the date range and descending date and UUID order. Its predicate matches approved, non-voided sales. PostgreSQL can stop after the latest 20 matches and skips the baseline sort. The report returned the same ordered 20 sales in both phases. Buffer accesses fell by **97.4%**. The index uses about **3.25 MiB**.

**Product movement.** The composite index starts with product ID and narrows the lookup by date. PostgreSQL uses the bitmap to identify heap rows and aggregates the same **80 movements**, with 100 packs received, 403 issued, and a net movement of −303. Buffer accesses fell by **90.7%**. The index uses about **0.77 MiB**. [PostgreSQL multicolumn indexes](https://www.postgresql.org/docs/18/indexes-multicolumn.html)

The results describe selective queries in a warm, in-memory PGlite run with PostgreSQL 18.6. The timing samples vary, and query execution time excludes client and network latency. Broad queries may still favour sequential scans. The two indexes add storage and maintenance work to writes. [Actual results, timing samples, and before-and-after plans](evidence/results.json)

## Reproduce the results

Run from the project root with Node.js 20+ and npm. The runner loads the schema and fixtures into a fresh embedded database, checks all six report results, and verifies that the indexes preserve the two benchmark results.

```sh
npm ci
npm run verify:p2
```

Run `npm run --silent verify:p2 -- --json` to print the full measurements and plans.

Codex assisted with the SQL, validation runner, and analysis of the measured plans.
