import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import pg from 'pg';

const reportCode = 'C_PET_50';
const projection = './sql/stock-projection.sql';

function readUrl(variable) {
  const value = process.env[variable] ?? '';
  return URL.canParse(value) ? new URL(value) : null;
}

function labUrl(variable, database) {
  const url = readUrl(variable);
  assert(url && ['postgres:', 'postgresql:'].includes(url.protocol)
    && url.hostname === '127.0.0.1' && url.port
    && url.pathname === '/' + database && !url.search && !url.hash,
  `${variable} must point to the dedicated local ${database} database.`);
  return url;
}

async function executeFile(client, relativePath) {
  const sql = await readFile(new URL(relativePath, import.meta.url), 'utf8');
  await client.query(sql);
}

async function report(client) {
  const { rows } = await client.query(
    `SELECT product_code, product_name, unit, current_stock::text, version, refreshed_at
     FROM bilikis.stock_report ORDER BY product_code`);
  return { row_count: rows.length, product: rows.find(row => row.product_code === reportCode) ?? null };
}

async function until(check, description) {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    const result = await check();
    if (result) return result;
    await delay(100);
  }
  throw new Error(`Timed out waiting for ${description}.`);
}

async function postSale(primary) {
  await primary.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try {
    await primary.query(
      'SELECT bilikis.p3_post_pet_sale($1, $2, $3, $4)',
      ['P5-STOCK-ISSUE', 'DEMO-CUS-001', reportCode, 10]);
    const result = await primary.query(
      `UPDATE bilikis.stock_report AS report
       SET current_stock = stock.current_stock, version = report.version + 1, refreshed_at = clock_timestamp()
       FROM bilikis.current_stock_view AS stock
       WHERE report.product_code = stock.product_code AND report.product_code = $1`, [reportCode]);
    assert.equal(result.rowCount, 1);
    await primary.query('COMMIT');
  } catch (error) {
    await primary.query('ROLLBACK');
    throw error;
  }
}

async function run() {
  const started = new Date().toISOString();
  const primaryUrl = labUrl('P5_PRIMARY_URL', 'bilikis_p5_publisher');
  const subscriberUrl = labUrl('P5_SUBSCRIBER_URL', 'bilikis_p5_subscriber');
  assert.notEqual(primaryUrl.port, subscriberUrl.port, 'Use two distinct PostgreSQL listeners.');

  const primary = new pg.Client({ connectionString: primaryUrl.href, connectionTimeoutMillis: 5000 });
  const subscriber = new pg.Client({ connectionString: subscriberUrl.href, connectionTimeoutMillis: 5000 });
  let subscribed = false;
  try {
    const connections = await Promise.allSettled([primary.connect(), subscriber.connect()]);
    for (const connection of connections) {
      if (connection.status === 'rejected') throw connection.reason;
    }
    const identify = `SELECT system_identifier::text, current_setting('server_version') AS version,
      current_setting('wal_level') AS wal_level, to_regnamespace('bilikis') IS NULL AS clean
      FROM pg_control_system()`;
    const [publisherInfo, subscriberInfo] = (await Promise.all([
      primary.query(identify), subscriber.query(identify),
    ])).map(result => result.rows[0]);
    assert.notEqual(publisherInfo.system_identifier, subscriberInfo.system_identifier,
      'Publisher and subscriber must be separate clusters.');
    assert(publisherInfo.clean && subscriberInfo.clean, 'Use fresh disposable databases.');
    assert.equal(publisherInfo.wal_level, 'logical');

    await executeFile(primary, '../portfolio-1-database-design/sql/01-schema.sql');
    await executeFile(primary, '../portfolio-1-database-design/sql/02-seed.sql');
    await executeFile(primary, '../portfolio-2-query-optimisation/sql/catalogue-fixture.sql');
    await executeFile(primary, '../portfolio-3-transactions-concurrency/sql/post-pet-sale.sql');
    await subscriber.query('CREATE SCHEMA bilikis');
    await executeFile(primary, projection);
    await executeFile(subscriber, projection);
    await primary.query(`INSERT INTO bilikis.stock_report (product_code, product_name, unit, current_stock)
      SELECT product_code, product_name, unit, current_stock FROM bilikis.current_stock_view`);
    await primary.query('CREATE PUBLICATION p5_stock_publication FOR TABLE bilikis.stock_report');
    await subscriber.query(`CREATE SUBSCRIPTION p5_stock_subscription
      CONNECTION ${subscriber.escapeLiteral(primaryUrl.href)} PUBLICATION p5_stock_publication`);
    subscribed = true;

    await until(async () => {
      const { rowCount } = await subscriber.query(
        `SELECT 1 FROM pg_subscription_rel WHERE srrelid = 'bilikis.stock_report'::regclass AND srsubstate = 'r'`);
      return rowCount === 1;
    }, 'the initial table copy');

    const initial = { primary: await report(primary), subscriber: await report(subscriber) };
    assert.equal(initial.primary.row_count, 3);
    assert.equal(initial.primary.product.current_stock, '85');
    assert.equal(initial.primary.product.version, 1);
    assert.deepEqual(initial.subscriber, initial.primary);

    await subscriber.query('ALTER SUBSCRIPTION p5_stock_subscription DISABLE');
    await until(async () => {
      const { rowCount } = await subscriber.query(
        `SELECT 1 FROM pg_stat_subscription WHERE subname = 'p5_stock_subscription' AND pid IS NOT NULL`);
      return rowCount === 0;
    }, 'the subscription worker to stop');

    await postSale(primary);
    const paused = { primary: await report(primary), subscriber: await report(subscriber) };
    assert.equal(paused.primary.row_count, 3);
    assert.equal(paused.primary.product.current_stock, '75');
    assert.equal(paused.primary.product.version, 2);
    assert.deepEqual(paused.subscriber, initial.subscriber);

    await subscriber.query('ALTER SUBSCRIPTION p5_stock_subscription ENABLE');
    const caughtUp = { primary: await report(primary), subscriber: await until(async () => {
      const snapshot = await report(subscriber);
      return snapshot.product?.version === 2 ? snapshot : null;
    }, 'the subscriber to apply version 2') };
    assert.deepEqual(caughtUp.primary, paused.primary);
    assert.deepEqual(caughtUp.subscriber, caughtUp.primary);

    await subscriber.query('DROP SUBSCRIPTION p5_stock_subscription');
    subscribed = false;
    const slot = await primary.query("SELECT 1 FROM pg_replication_slots WHERE slot_name = 'p5_stock_subscription'");
    assert.equal(slot.rowCount, 0);

    return {
      started_at_utc: started, finished_at_utc: new Date().toISOString(),
      publisher_version: publisherInfo.version, subscriber_version: subscriberInfo.version,
      separate_clusters_verified: true, sale_quantity: 10,
      replicated_table: 'bilikis.stock_report',
      publication: 'p5_stock_publication', subscription: 'p5_stock_subscription',
      initial, apply_paused: paused, caught_up: caughtUp, replication_slot_removed: true,
    };
  } finally {
    try {
      if (subscribed) await subscriber.query('DROP SUBSCRIPTION p5_stock_subscription');
    } finally {
      await Promise.allSettled([subscriber.end(), primary.end()]);
    }
  }
}

try {
  const results = await run();
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(results, null, 2));
  } else {
    console.log('PostgreSQL logical replication verified across two clusters.');
    console.table([
      ['Initial copy', results.initial],
      ['Apply paused', results.apply_paused],
      ['Caught up', results.caught_up],
    ].map(([stage, row]) => ({
      stage,
      primary: row.primary.product.current_stock,
      subscriber: row.subscriber.product.current_stock,
      subscriber_version: row.subscriber.product.version,
    })));
  }
} catch (error) {
  let message = error.message;
  for (const variable of ['P5_PRIMARY_URL', 'P5_SUBSCRIBER_URL']) {
    const url = readUrl(variable);
    if (url?.password) message = message.replaceAll(url.password, '[redacted]');
  }
  console.error(message);
  process.exitCode = 1;
}
