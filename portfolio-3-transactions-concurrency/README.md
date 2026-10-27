# Portfolio 3 — Transactions and Concurrency

Bilikis must record a PET sale and its stock issue together. Two staff sessions might each see enough stock to place an order, so they need a shared way to reserve the available balance. This exercise uses the Portfolio 1 schema, the real catalogue code `C_PET_50`, and synthetic sales and stock. [Stock sale function](sql/post-pet-sale.sql)

## Transaction results

The fixture starts with **85 packs** of Coca-Cola 50cl PET. The sale routine writes a sale header, one item, and one stock movement. The caller starts and ends the transaction.

| Test | Observed result |
|---|---|
| Commit a sale for 5 packs | The posting session saw all three pending rows and 80 packs. A separate session still saw 85 packs and zero new rows. After `COMMIT`, it saw all three rows and 80 packs. |
| Fail after posting a sale for 3 packs | A second insert with the same sale number failed with unique violation `23505`. A subsequent statement returned `25P02` because the transaction was aborted. After `ROLLBACK`, none of the three pending rows remained and stock was 80 packs. |
| Competing sales of 50 packs each | Session B waited on Session A. A committed its sale, and B's stock check found 30 packs available for its 50-pack request. B received `P3001` and rolled back. Exactly one competing sale was saved. |

## Two sessions under READ COMMITTED

| Step | Session A | Session B | Observer |
|---|---|---|---|
| 1 | Begins and locks the product with `FOR UPDATE`. Posts a sale for 50 packs | Begins | Sees 80 committed packs |
| 2 | Sees 30 packs in its own transaction | Reads 80 packs and then tries to post its own sale for 50 | `pg_blocking_pids` identifies A as B's blocker. The wait is `Lock / transactionid` |
| 3 | Commits and releases the lock | Takes the lock and reads the committed stock in a fresh statement inside the sale function | Sees 30 packs |
| 4 | Sale, line, and movement persist | Receives `P3001` and rolls back | Confirms 30 packs and zero rows for B's sale |

The routine locks the product row before it checks the movement ledger. Its separate stock query inside the `VOLATILE` function gets a fresh snapshot under `READ COMMITTED` after the lock becomes available. The observed 80 packs in B before A commits show isolation from A's pending movement. The `P3001` message after A commits records the updated balance of 30. [PostgreSQL transaction isolation](https://www.postgresql.org/docs/18/transaction-iso.html) · [Row locks](https://www.postgresql.org/docs/18/explicit-locking.html) · [Function snapshots](https://www.postgresql.org/docs/18/xfunc-volatility.html)

The stock rule depends on each competing issue for this SKU acquiring the same product lock before checking availability. The exercise function requires `READ COMMITTED`. A larger operation that locks multiple products should acquire those locks in a consistent order. An insufficient-stock error requires a revised quantity or replenishment before retrying.

## Reproduce the exercise

Run from the repository root with Node.js 20+ and a fresh local PostgreSQL 18 database named `bilikis_portfolio3`. The verifier opens two sale sessions and an observer. It loads the schema, seed, and catalogue into the disposable database and checks the row counts, SQLSTATEs, and lock wait. The recorded run used a temporary PostgreSQL 18.6 server on Windows.

For example, with Docker running, create the disposable database and wait for `pg_isready` to report that it accepts connections. The example password is for this local lab. [PostgreSQL container documentation](https://github.com/docker-library/docs/blob/master/postgres/README.md)

```powershell
docker run --rm --name bilikis-p3 -d -p 127.0.0.1:55437:5432 -e POSTGRES_USER=portfolio_lab -e POSTGRES_PASSWORD=p3-lab-only -e POSTGRES_DB=bilikis_portfolio3 postgres:18
docker exec bilikis-p3 pg_isready -h 127.0.0.1 -U portfolio_lab -d bilikis_portfolio3
$env:P3_DATABASE_URL = 'postgresql://portfolio_lab:p3-lab-only@127.0.0.1:55437/bilikis_portfolio3'
npm ci
npm run verify:p3
docker stop bilikis-p3
```

Use a fresh database for each run. Run `npm run --silent verify:p3 -- --json` to capture the observations as JSON. [Recorded transaction results](evidence/results.json)

![Screenshot of commit, rollback, and two-session lock evidence](evidence/transactions-screenshot.png)

Codex assisted with the SQL, verifier, and analysis of the observed transaction results.
