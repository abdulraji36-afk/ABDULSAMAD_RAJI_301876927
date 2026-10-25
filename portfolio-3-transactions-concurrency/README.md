# Portfolio 3 — Transactions and Concurrency

Bilikis must record a PET sale and its stock issue together. This exercise uses the Portfolio 1 schema, the real catalogue code `C_PET_50`, and synthetic sales and stock. [Stock sale function](sql/post-pet-sale.sql)

## Transaction results

The fixture starts with **85 packs** of Coca-Cola 50cl PET. The sale routine writes a sale header, one item, and one stock movement. The caller starts and ends the transaction.

| Test | Observed result |
|---|---|
| Commit a sale for 5 packs | The posting session saw all three pending rows and 80 packs. A separate session still saw 85 packs and zero new rows. After `COMMIT`, it saw all three rows and 80 packs. |
| Fail after posting a sale for 3 packs | A second insert with the same sale number failed with unique violation `23505`. A subsequent statement returned `25P02` because the transaction was aborted. After `ROLLBACK`, none of the three pending rows remained and stock was 80 packs. |

## Reproduce the exercise

Run from the repository root with Node.js 20+ and a fresh local PostgreSQL 18 database named `bilikis_portfolio3`. The verifier opens a sale session and an observer. It loads the schema, seed, and catalogue into the disposable database and checks the row counts and SQLSTATEs. The recorded run used a temporary PostgreSQL 18.6 server on Windows.

For example, with Docker running, create the disposable database and wait for `pg_isready` to report that it accepts connections. The example password is for this local lab. [PostgreSQL container documentation](https://github.com/docker-library/docs/blob/master/postgres/README.md)

```powershell
docker run --rm --name bilikis-p3 -d -p 127.0.0.1:55437:5432 -e POSTGRES_USER=portfolio_lab -e POSTGRES_PASSWORD=p3-lab-only -e POSTGRES_DB=bilikis_portfolio3 postgres:18
docker exec bilikis-p3 pg_isready -h 127.0.0.1 -U portfolio_lab -d bilikis_portfolio3
$env:P3_DATABASE_URL = 'postgresql://portfolio_lab:p3-lab-only@127.0.0.1:55437/bilikis_portfolio3'
npm ci
npm run verify:p3
docker stop bilikis-p3
```

Use a fresh disposable database for each run.
