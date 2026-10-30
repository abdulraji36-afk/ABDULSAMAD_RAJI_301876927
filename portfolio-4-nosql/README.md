# Portfolio 4 — NoSQL and Advanced Data Models

The Bilikis sale detail screen needs the sale, its items, and its dispatch information together. The SQL projection prepares the relational fixture for a MongoDB `sales` collection. The product codes and names come from the Bilikis catalogue. The customers, sale amounts, and dispatch activity are synthetic.

## Sales document

| Field | Model choice |
|---|---|
| `_id` | Stable key combining the sales channel and sale number, such as `RGB:RGB-001` |
| `sourceSaleId`, `customerCode` | References to the PostgreSQL sale and customer. Their ownership stays in PostgreSQL |
| `channel`, `status`, `saleDate` | Sale metadata. MongoDB stores the date as a BSON date at midnight UTC |
| `lineItems[]` | Embedded product code, catalogue label at import, unit, quantity, and the price recorded on the sale line. Quantity and unit price use BSON Decimal128 |
| `dispatch` | Optional embedded trip summary. RGB sales also carry expected empties, initial returns, and the sum of follow-up returns |

Items belong to one sale and are usually read with it. Embedding lets the application fetch them in a single document read. The snapshot repeats catalogue labels and trip details across documents, so a later catalogue edit or return requires a refresh policy. Individual follow-up events stay in PostgreSQL and the projection stores their total. [MongoDB embedding guidance](https://www.mongodb.com/docs/manual/data-modeling/embedding/)

## Relational projection

The SQL groups the priced lines of each eligible sale and totals RGB follow-ups before joining them to dispatch assignments. The projector loads the Portfolio 1 fixture, applies the Portfolio 2 catalogue entries, and gives the synthetic references short labels such as `RGB-001`. It runs the original Portfolio 2 sales and shortage reports on the same fixture and projects four sales for October 2026. [Projection SQL](sql/project-sales.sql)

Run the projection alone from the repository root with Node.js 20+.

```sh
npm ci
node portfolio-4-nosql/project-sales.mjs
```
