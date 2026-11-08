# Bilikis Store Database Portfolio

[GitHub repository](https://github.com/abdulraji36-afk/Raji_Abdulsamad_301876927)

Final report ([Markdown](Final%20Documentation.md) · [PDF](Final%20Documentation.pdf)) · [Full ER diagram (PNG)](portfolio-1-database-design/diagrams/full-schema.png)

## Selected organisation

The selected organisation is Bilikis Store, a beverage distribution business. Its operations app manages sales, inventory and deliveries for drinks in plastic (PET) and returnable glass (RGB) bottles. Sales staff, storekeepers, delivery staff, managers and administrators use the database through the app.

The database stores products, customers, staff profiles, stock receipts and movements, sales and line items, dispatch trips, empty-container returns and audit logs. It supports receiving stock, requesting and approving PET sales, assigning orders to trips, recording returns, checking outstanding empties, and reporting on stock and sales.

The app uses Next.js, Supabase Auth, and PostgreSQL. This portfolio adapts the app’s database schema and uses three products from the Bilikis catalogue. The customer records, sales, stock quantities, and dispatch activity are synthetic.

## The five portfolios

1. [Database design and modelling](portfolio-1-database-design/README.md) explains how the schema connects products, customers, sales, stock movements, and dispatch. The verifier passed 34 checks. [Validation evidence](portfolio-1-database-design/evidence/validation-screenshot.png)
2. [Query processing and optimisation](portfolio-2-query-optimisation/README.md) runs six business reports and compares two queries before and after indexing. In the local benchmark, the median customer history query fell from 8.457 ms to 0.097 ms. [Query evidence](portfolio-2-query-optimisation/evidence/query-optimisation-screenshot.png)
3. [Transactions and concurrency](portfolio-3-transactions-concurrency/README.md) tests commit, rollback, and two sales competing for the same stock. A product lock ensured only one of the two 50-pack sales committed. [Transaction evidence](portfolio-3-transactions-concurrency/evidence/transactions-screenshot.png)
4. [NoSQL modelling](portfolio-4-nosql/README.md) stores sale items and dispatch details together in MongoDB. The sales totals and outstanding empties matched the PostgreSQL reports. [MongoDB evidence](portfolio-4-nosql/evidence/nosql-screenshot.png)
5. [Distributed and cloud databases](portfolio-5-distributed-cloud/README.md) shows a stock report falling behind on a local PostgreSQL replica and catching up when replication resumes. It also documents a read-only Supabase API check. [Replication evidence](portfolio-5-distributed-cloud/evidence/replication-screenshot.png)

## Run the checks

With Node.js 20 or newer, run these commands from the repository root.

```sh
npm ci
npm run verify:p1
npm run verify:p2
```

Portfolios 3–5 include their own PostgreSQL or MongoDB setup instructions. The final report includes the individual reflection, references, and AI-use declaration.
