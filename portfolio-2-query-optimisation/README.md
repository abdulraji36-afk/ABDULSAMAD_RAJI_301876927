# Portfolio 2 — Query Processing and Optimisation

Bilikis Store needs reports for stock levels, recorded sales, empty-container shortages, inventory value, customer history, and product movements. This portfolio runs those reports on the Portfolio 1 schema and checks the results against known fixture values. [SQL queries](sql/queries.sql)

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

## Run the reports

From the repository root, run the following with Node.js 20+ and npm. The verifier loads the fixture in a fresh embedded database and checks the six reports.

```sh
npm ci
npm run verify:p2
```
