# Portfolio 5 · Distributed and cloud database

## Bilikis cloud architecture

The Bilikis operations app uses Supabase Auth and hosted PostgreSQL for beverage sales, stock movements, dispatch and returnable containers. Its browser and server clients use the configured Supabase URL and publishable key. PostgreSQL is the source of truth for inventory. Stock-changing workflows and reads that must reflect a just-posted sale belong on the primary.

The [hosted API probe](evidence/cloud-probe.json) issued one anonymous GET for the catalogue code `C_PET_50`. Supabase returned HTTP 200 and an empty array. This verifies reachability and the response visible to that request. The probe made no writes and captured no credentials, project URL or live business records. Backup and read-replica settings for the hosted project were outside the probe's scope.

## Stock report design

The [stock projection](sql/stock-projection.sql) stores one row per product with its code, name, unit, current quantity, version and refresh timestamp. The primary derives the report from the inventory ledger. PostgreSQL logical replication sends the report table to a subscriber. Operational sale, customer and stock-movement tables stay on the publisher in this lab.

| Need | Design decision |
| --- | --- |
| Read-after-write consistency | Read the primary for stock checks and decisions that depend on the latest committed sale. |
| Reporting availability | Serve stock summaries from a subscriber when last-applied data is acceptable. Show the refresh time and monitor apply lag. An inactive logical slot can retain WAL on the publisher, so alert on both lag and retained WAL. |
| Recovery | Keep backups separate from replication. A data correction or accidental deletion can propagate to replicas. Define acceptable data loss and recovery time, then verify both with a restore drill. |
| Growth | A possible future shard key is warehouse ID, keeping each site's inventory and stock movements together. Transfers across sites need coordination and reconciliation. The lab uses a single writer and a reporting subscriber. |

Supabase's managed read replicas use asynchronous physical replication, so reads can lag the primary. The lab uses a table-level logical publication to demonstrate that trade-off with a smaller reporting dataset. Deployment and backup choices would depend on the project's plan, region and recovery targets.

## Replication exercise

The experiment uses two disposable PostgreSQL 18 instances on localhost with distinct cluster identifiers. It loads the existing Bilikis fixture and the supplied three-product catalogue subset. Sale quantities, customer records and inventory are synthetic.

1. Copy the three stock report rows to the subscriber. Both instances show 85 packs of `C_PET_50` at version 1.
2. Disable the subscription and post a 10-pack PET sale with the Portfolio 3 transaction function. The same primary transaction refreshes the stock report to 75 packs at version 2. The subscriber still returns 85 packs at version 1.
3. Re-enable the subscription. The subscriber applies the pending update and returns 75 packs at version 2. The runner drops the subscription and verifies that its publisher slot is removed.

| Checkpoint | Publisher | Subscriber |
| --- | ---: | ---: |
| Initial copy | 85 packs, v1 | 85 packs, v1 |
| Apply paused after sale | 75 packs, v2 | 85 packs, v1 |
| Apply resumed and caught up | 75 packs, v2 | 75 packs, v2 |

The paused stage demonstrates a stale but readable report. Its duration was induced for the experiment. It provides no production latency or failover measurement.

## Reproduce and inspect

From the repository root, install dependencies with Node.js 20 or newer and run the Windows PowerShell launcher with a PostgreSQL 18 `bin` directory containing `initdb.exe` and `pg_ctl.exe`.

```powershell
npm ci
.\portfolio-5-distributed-cloud\run-local.ps1 -PostgresBin "C:\Program Files\PostgreSQL\18\bin"
```

The [launcher](run-local.ps1) creates two fresh loopback clusters on temporary ports and stops them on exit. For existing **disposable** local clusters, use `npm run verify:p5` with `P5_PRIMARY_URL` and `P5_SUBSCRIBER_URL` set to fresh databases named `bilikis_p5_publisher` and `bilikis_p5_subscriber`. The publisher needs `wal_level=logical`, and the lab connections need permission to create the schema, publication and subscription. Use `-Json` with the launcher or `npm run verify:p5 -- --json` for structured output.

The [runner](run.mjs) checks the stock and version at each step. The [recorded results](evidence/results.json) include the database versions, timestamps and observations from both instances.

## References

- [PostgreSQL 18 logical replication](https://www.postgresql.org/docs/18/logical-replication.html)
- [Supabase Data API](https://supabase.com/docs/guides/api)
- [Supabase read replicas](https://supabase.com/docs/guides/platform/read-replicas)
- [Supabase database backups](https://supabase.com/docs/guides/platform/backups)
