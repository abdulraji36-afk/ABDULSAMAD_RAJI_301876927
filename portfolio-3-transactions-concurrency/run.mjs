import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import pg from 'pg';

const { Client } = pg;
const databaseName = 'bilikis_portfolio3';
const connection = process.env.P3_DATABASE_URL;
assert.ok(connection, 'Set P3_DATABASE_URL to the local disposable PostgreSQL database.');
const url = new URL(connection);
assert.ok(
  ['postgres:', 'postgresql:'].includes(url.protocol)
    && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)
    && url.pathname === `/${databaseName}`
    && !url.search && !url.hash,
  `Use a loopback PostgreSQL connection to a fresh database named ${databaseName}.`,
);

const productCode = 'C_PET_50';
const customerCode = 'DEMO-CUS-001';
const here = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, here), 'utf8');
const clients = [];
const started = new Date().toISOString();
const begin = 'BEGIN ISOLATION LEVEL READ COMMITTED';

async function connect(label) {
  const client = new Client({
    connectionString: connection,
    application_name: `bilikis-p3-${label}`,
    connectionTimeoutMillis: 4000,
    statement_timeout: 15000,
    idle_in_transaction_session_timeout: 20000,
  });
  clients.push(client);
  await client.connect();
  return client;
}

async function row(client, sql, params = []) {
  const result = await client.query(sql, params);
  assert.equal(result.rows.length, 1);
  return result.rows[0];
}

async function stock(client) {
  const value = await row(client, 'SELECT current_stock FROM bilikis.current_stock_view WHERE product_code = $1', [productCode]);
  return Number(value.current_stock);
}

async function post(client, saleNo, quantity) {
  const result = await row(client, 'SELECT bilikis.p3_post_pet_sale($1, $2, $3, $4) AS id',
    [saleNo, customerCode, productCode, quantity]);
  return result.id;
}

async function snapshot(client, saleId) {
  const counts = await row(client, `SELECT
    (SELECT count(*)::int FROM bilikis.pet_sales WHERE id = $1) AS sales,
    (SELECT count(*)::int FROM bilikis.pet_sale_items WHERE pet_sale_id = $1) AS lines,
    (SELECT count(*)::int FROM bilikis.stock_movements
      WHERE source_table = 'pet_sales' AND source_id = $1) AS movements`, [saleId]);
  return { stock: await stock(client), ...counts };
}

async function expectError(operation, sqlstate) {
  try {
    await operation();
  } catch (error) {
    assert.equal(error.code, sqlstate, error.message);
    return { sqlstate: error.code, message: error.message };
  }
  assert.fail(`Expected SQLSTATE ${sqlstate}`);
}

async function observeWait(observer, blockedPid, blockingPid) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const wait = await row(observer, `SELECT wait_event_type, wait_event,
      pg_blocking_pids(pid) AS blocking_pids
      FROM pg_stat_activity WHERE pid = $1`, [blockedPid]);
    if (wait.wait_event_type === 'Lock' && wait.blocking_pids.includes(blockingPid)) return wait;
    await delay(25);
  }
  assert.fail('Session B did not wait on Session A within five seconds.');
}

let inFlight;
try {
  const observer = await connect('observer');
  const a = await connect('a');
  const b = await connect('b');
  const setup = await row(observer, `SELECT version() AS engine, current_database() AS database,
    to_regnamespace('bilikis') IS NULL AS fresh`);
  assert.equal(setup.database, databaseName);
  assert.equal(setup.fresh, true, 'Start with a fresh disposable database.');
  await observer.query(await read('../portfolio-1-database-design/sql/01-schema.sql'));
  await observer.query(await read('../portfolio-1-database-design/sql/02-seed.sql'));
  await observer.query(await read('../portfolio-2-query-optimisation/sql/catalogue-fixture.sql'));
  await observer.query(await read('sql/post-pet-sale.sql'));
  const product = await row(observer, 'SELECT product_code, product_name, unit FROM bilikis.products WHERE product_code = $1', [productCode]);
  const initial = await stock(observer);
  assert.equal(initial, 85);

  // COMMIT: all three writes become visible together to another connection.
  await a.query(begin);
  const committedId = await post(a, 'P3-COMMIT', 5);
  const commitInside = await snapshot(a, committedId);
  const commitBefore = await snapshot(observer, committedId);
  assert.deepEqual(commitInside, { stock: 80, sales: 1, lines: 1, movements: 1 });
  assert.deepEqual(commitBefore, { stock: 85, sales: 0, lines: 0, movements: 0 });
  await a.query('COMMIT');
  const commitAfter = await snapshot(observer, committedId);
  assert.deepEqual(commitAfter, commitInside);

  // ROLLBACK: a duplicate sale number aborts a transaction with earlier writes.
  await a.query(begin);
  const rolledBackId = await post(a, 'P3-ROLLBACK', 3);
  const rollbackInside = await snapshot(a, rolledBackId);
  assert.deepEqual(rollbackInside, { stock: 77, sales: 1, lines: 1, movements: 1 });
  const duplicate = await expectError(() => post(a, 'P3-ROLLBACK', 1), '23505');
  const aborted = await expectError(() => a.query('SELECT 1'), '25P02');
  await a.query('ROLLBACK');
  const rollbackAfter = await snapshot(observer, rolledBackId);
  assert.deepEqual(rollbackAfter, { stock: 80, sales: 0, lines: 0, movements: 0 });

  // CONCURRENCY: two different server sessions each try to sell 50 of 80 packs.
  await a.query(begin);
  await b.query(begin);
  const sessionInfo = 'SELECT pg_backend_pid() AS pid, current_setting(\'transaction_isolation\') AS isolation';
  const sessionA = await row(a, sessionInfo);
  const sessionB = await row(b, sessionInfo);
  assert.notEqual(sessionA.pid, sessionB.pid);
  assert.equal(sessionA.isolation, 'read committed');
  assert.equal(sessionB.isolation, 'read committed');
  const winnerId = await post(a, 'P3-CONCURRENT-A', 50);
  const aUncommittedStock = await stock(a);
  const bBeforeCommit = await stock(b);
  assert.equal(aUncommittedStock, 30);
  assert.equal(bBeforeCommit, 80);

  // Attach the rejection handler before observing the waiting query.
  inFlight = expectError(() => post(b, 'P3-CONCURRENT-B', 50), 'P3001')
    .then((error) => ({ error }), (failure) => ({ failure }));
  const wait = await observeWait(observer, sessionB.pid, sessionA.pid);
  await a.query('COMMIT');
  const outcome = await inFlight;
  if (outcome.failure) throw outcome.failure;
  assert.match(outcome.error.message, /available 30, requested 50/);
  await b.query('ROLLBACK');
  const finalWinner = await snapshot(observer, winnerId);
  assert.deepEqual(finalWinner, { stock: 30, sales: 1, lines: 1, movements: 1 });
  const finalCounts = await row(observer, `SELECT
    (SELECT count(*)::int FROM bilikis.pet_sales) AS all_pet_sales,
    (SELECT count(*)::int FROM bilikis.pet_sale_items) AS all_pet_lines,
    (SELECT count(*)::int FROM bilikis.stock_movements) AS all_movements,
    (SELECT count(*)::int FROM bilikis.pet_sales WHERE sales_no = 'P3-CONCURRENT-B') AS rejected_sales`);
  assert.deepEqual(finalCounts, { all_pet_sales: 4, all_pet_lines: 4, all_movements: 9, rejected_sales: 0 });

  const evidence = {
    started_at_utc: started,
    finished_at_utc: new Date().toISOString(),
    engine: setup.engine,
    product,
    commit: { sale_no: 'P3-COMMIT', quantity: 5, inside: commitInside, observer_before: commitBefore, observer_after: commitAfter },
    rollback: { sale_no: 'P3-ROLLBACK', quantity: 3, inside: rollbackInside, duplicate, aborted, observer_after: rollbackAfter },
    concurrency: { session_a: sessionA, session_b: sessionB, quantity_per_session: 50,
      a_stock_before_commit: aUncommittedStock, b_stock_before_commit: bBeforeCommit,
      observed_wait: wait, b_error_after_a_commit: outcome.error, winner: finalWinner, final_counts: finalCounts },
  };
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(evidence, null, 2));
  } else {
    console.log(`COMMIT passed: stock ${initial} → ${commitAfter.stock}, all three records saved.`);
    console.log(`ROLLBACK passed: ${duplicate.sqlstate} → ${aborted.sqlstate}, stock restored to ${rollbackAfter.stock}.`);
    console.log(`Concurrency passed: session ${sessionB.pid} waited for ${sessionA.pid} (${wait.wait_event_type}/${wait.wait_event}).`);
    console.log(`Session B received ${outcome.error.sqlstate}, with ${finalWinner.stock} packs remaining.`);
  }
} finally {
  // Closing session A releases its lock even if the wait check failed.
  for (const client of clients) await client.end();
}
