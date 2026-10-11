import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Optional file-URL override lets an existing, matching local installation be reused.
// Normal usage after npm ci imports the pinned project dependency.
const { PGlite } = await import(process.env.BILIKIS_PGLITE_MODULE || '@electric-sql/pglite');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const base = 'portfolio-1-database-design/';
const read = (path) => readFile(resolve(root, path), 'utf8');
const jsonOutput = process.argv.includes('--json');
const checks = [];
const outputs = {};
const started = new Date().toISOString();
const db = new PGlite();
let fatal;
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const rows = async (sql, params = []) => (await db.query(sql, params)).rows;
const scalar = async (sql, params = []) => Object.values((await rows(sql, params))[0])[0];
async function check(name, run) {
  try {
    const details = await run();
    checks.push({ name, status: 'pass', ...(details ? { details } : {}) });
    if (!jsonOutput) console.log(`PASS ${name}`);
  } catch (error) {
    checks.push({ name, status: 'fail', error: error.message, sqlstate: error.code });
    throw error;
  }
}
async function rejects(name, sql, params, expectedCode) {
  return check(name, async () => {
    await db.exec('BEGIN');
    let actual;
    try {
      await db.query(sql, params);
    } catch (error) {
      actual = { sqlstate: error.code, message: error.message };
    } finally {
      await db.exec('ROLLBACK');
    }
    assert.equal(actual?.sqlstate, expectedCode, `Expected SQLSTATE ${expectedCode}; received ${JSON.stringify(actual)}`);
    return { sql, parameters: params, expected_sqlstate: expectedCode, observed: actual };
  });
}

const sqlFiles = ['sql/01-schema.sql', 'sql/02-seed.sql', 'sql/03-inspect.sql'].map((x) => base + x);
const sqlSources = await Promise.all(sqlFiles.map(read));
const pkg = JSON.parse(await read('package.json'));
let engine;
try {
  await db.exec("SET TIME ZONE 'UTC'");
  engine = await scalar('SELECT version()');
  await check('Schema creates successfully in a fresh embedded PostgreSQL database', async () => {
    await db.exec(sqlSources[0]);
  });
  await check('Synthetic fixtures insert successfully', async () => { await db.exec(sqlSources[1]); });
  await check('All read-only inspection queries execute', async () => {
    outputs.inspection_results = (await db.exec(sqlSources[2])).map((x) => x.rows);
  });
  const expected = JSON.parse(await read('scripts/schema-expectations.json'));
  await check('Exactly 24 application tables plus the identity fixture exist', async () => {
    outputs.tables = await rows("SELECT table_name FROM information_schema.tables WHERE table_schema='bilikis' AND table_type='BASE TABLE' ORDER BY table_name");
    assert.deepEqual(outputs.tables.map((x) => x.table_name), ['auth_users', ...Object.keys(expected.nullableByTable)].sort());
    assert.equal(outputs.tables.length, 25);
  });
  await check('Every application table has synthetic data', async () => {
    outputs.row_counts = {};
    for (const { table_name: table } of outputs.tables) {
      // Identifiers come from catalogue data, not user input; still quote defensively.
      const quoted = '"' + table.replaceAll('"', '""') + '"';
      const count = Number(await scalar(`SELECT count(*) FROM bilikis.${quoted}`));
      outputs.row_counts[table] = count;
      assert.ok(count > 0, `${table} needs fixture rows`);
    }
  });
  await check('209 application columns match the documented names and nullability', async () => {
    const actual = await rows("SELECT table_name, column_name, is_nullable FROM information_schema.columns WHERE table_schema='bilikis' AND table_name <> 'auth_users' AND table_name <> 'current_stock_view' ORDER BY table_name, ordinal_position");
    assert.equal(actual.length, 209);
    for (const row of actual) {
      const columns = expected.nullableByTable[row.table_name];
      assert.ok(Object.hasOwn(columns, row.column_name), `${row.table_name}.${row.column_name} missing from expected schema`);
      assert.equal(row.is_nullable === 'YES', columns[row.column_name], `${row.table_name}.${row.column_name}`);
    }
  });
  await check('All 32 foreign keys match the complete ER model', async () => {
    const actual = await rows(`SELECT child.relname AS child, a.attname AS column, parent.relname AS parent, pa.attname AS parent_column
      FROM pg_constraint c
      JOIN pg_class child ON child.oid=c.conrelid
      JOIN pg_namespace n ON n.oid=child.relnamespace
      JOIN pg_class parent ON parent.oid=c.confrelid
      JOIN pg_attribute a ON a.attrelid=child.oid AND a.attnum=c.conkey[1]
      JOIN pg_attribute pa ON pa.attrelid=parent.oid AND pa.attnum=c.confkey[1]
      WHERE n.nspname='bilikis' AND c.contype='f'`);
    const key = (x) => `${x.child}.${x.column}->${x.parent}.${x.parent_column}`;
    assert.equal(actual.length, 32);
    assert.deepEqual(actual.map(key).sort(), [...expected.foreignKeys].sort());
    outputs.foreign_keys = actual;
  });
  await check('All 10 enum types match the documented labels', async () => {
    const actual = await rows("SELECT t.typname, e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='bilikis' ORDER BY t.typname, e.enumsortorder");
    const grouped = {};
    for (const r of actual) (grouped[r.typname] ??= []).push(r.enumlabel);
    assert.deepEqual(grouped, expected.enums);
  });
  await check('Stock fixture balances reconcile independently to 85, 30 and 60', async () => {
    outputs.stock = await rows('SELECT product_code, total_in, total_out, current_stock FROM bilikis.current_stock_view ORDER BY product_code');
    assert.deepEqual(outputs.stock.map((x) => [x.product_code, Number(x.current_stock)]), [['DEMO-PET-50', 85], ['DEMO-PET-60', 30], ['DEMO-RGB-35', 60]]);
  });
  await check('Generated receipt totals preserve pending NULL cost', async () => {
    outputs.receipt_totals = await rows('SELECT id, total_cost FROM bilikis.stock_in_items ORDER BY id');
    assert.deepEqual(outputs.receipt_totals.map((x) => x.total_cost === null ? null : Number(x.total_cost)), [150000, 496000, null]);
  });
  await check('Generated PET and RGB totals match known fixture amounts', async () => {
    assert.equal(Number(await scalar('SELECT sum(line_total) FROM bilikis.pet_sale_items')), 30000);
    assert.equal(Number(await scalar('SELECT sum(line_total) FROM bilikis.rgb_sale_items')), 140000);
  });
  await check('Generated total recalculates when quantity changes', async () => {
    await db.exec('BEGIN');
    try {
      await db.query('UPDATE bilikis.rgb_sale_items SET qty_out=3 WHERE id=$1', [id(511)]);
      assert.equal(Number(await scalar('SELECT line_total FROM bilikis.rgb_sale_items WHERE id=$1', [id(511)])), 21000);
    } finally { await db.exec('ROLLBACK'); }
  });
  await check('Return shortage includes follow-ups without duplicating initial returns', async () => {
    outputs.shortages = await rows(`SELECT a.id, a.expected_empties - coalesce(a.actual_empties_returned,0) - coalesce(f.qty,0) AS outstanding
      FROM bilikis.rgb_dispatch_trip_sales a LEFT JOIN (
        SELECT dispatch_trip_sale_id, sum(quantity) AS qty FROM bilikis.rgb_empty_return_followups GROUP BY dispatch_trip_sale_id
      ) f ON f.dispatch_trip_sale_id=a.id ORDER BY a.id`);
    assert.deepEqual(outputs.shortages.map((x) => Number(x.outstanding)), [2, 0]);
    // The fixtures contain no voided/cancelled sales. This is not a historical report implementation.
    const balance = await scalar(`SELECT
      (SELECT opening_empties FROM bilikis.empty_opening_balance)
      + (SELECT sum(actual_empties_returned) FROM bilikis.rgb_dispatch_trip_sales)
      + (SELECT sum(quantity) FROM bilikis.rgb_empty_return_followups)
      + (SELECT sum(quantity_delta) FROM bilikis.empty_adjustments)
      - (SELECT sum(empties_taken_by_nbc) FROM bilikis.empty_exchanges)`);
    assert.equal(Number(balance), 53);
    outputs.fixture_empty_balance = Number(balance);
  });
  await check('NBC reference checks retain NOT VALID metadata', async () => {
    const r = await rows("SELECT conname, convalidated FROM pg_constraint WHERE connamespace='bilikis'::regnamespace AND conname IN ('stock_in_nbc_ref_required','empty_exchanges_nbc_delivery_ref_required') ORDER BY conname");
    assert.equal(r.length, 2);
    assert.ok(r.every((x) => x.convalidated === false));
  });
  await rejects('Orphan sale item is rejected', 'INSERT INTO bilikis.pet_sale_items (pet_sale_id,product_id,qty_out) VALUES ($1,$2,1)', [id(9999), id(101)], '23503');
  await rejects('Duplicate product code is rejected', 'UPDATE bilikis.products SET product_code=$1 WHERE id=$2', ['DEMO-PET-50', id(102)], '23505');
  await rejects('Nonpositive receipt quantity is rejected', 'UPDATE bilikis.stock_in_items SET qty_in=0 WHERE id=$1', [id(311)], '23514');
  await rejects('Negative RGB price is rejected', 'UPDATE bilikis.rgb_sale_items SET price_per_crate=-1 WHERE id=$1', [id(511)], '23514');
  await rejects('Mandatory customer FK rejects NULL', 'UPDATE bilikis.pet_sales SET customer_id=NULL WHERE id=$1', [id(401)], '23502');
  await rejects('Invalid role enum is rejected', 'UPDATE bilikis.profiles SET role=$1 WHERE id=$2', ['not_a_role', id(2)], '22P02');
  await rejects('Blank new receipt reference is rejected despite NOT VALID', 'INSERT INTO bilikis.stock_in (nbc_ref) VALUES ($1)', ['   '], '23514');
  await rejects('Missing new exchange reference is rejected despite NOT VALID', 'INSERT INTO bilikis.empty_exchanges (empties_taken_by_nbc) VALUES (1)', [], '23514');
  await rejects('Zero-direction stock movement is rejected', 'INSERT INTO bilikis.stock_movements (product_id,movement_type,source_table,source_id) VALUES ($1,$2,$3,$4)', [id(101), 'adjustment', 'fixture', id(301)], '23514');
  await rejects('Negative stock movement quantity is rejected', 'UPDATE bilikis.stock_movements SET qty_in=-1 WHERE id=$1', [id(901)], '23514');
  await rejects('Duplicate RGB assignment of a sale is rejected', 'INSERT INTO bilikis.rgb_dispatch_trip_sales (dispatch_trip_id,rgb_sale_id,expected_empties) VALUES ($1,$2,1)', [id(601), id(501)], '23505');
  await rejects('Duplicate PET assignment of a sale is rejected', 'INSERT INTO bilikis.pet_dispatch_trip_sales (dispatch_trip_id,pet_sale_id) VALUES ($1,$2)', [id(701), id(401)], '23505');
  await rejects('Invalid follow-up quantity is rejected', 'UPDATE bilikis.rgb_empty_return_followups SET quantity=0 WHERE id=$1', [id(621)], '23514');
  await rejects('Singleton false key is rejected', 'INSERT INTO bilikis.empty_opening_balance (id) VALUES (false)', [], '23514');
  await rejects('Duplicate singleton true key is rejected', 'INSERT INTO bilikis.empty_opening_balance (id) VALUES (true)', [], '23505');
  await rejects('Duplicate composite sequence key is rejected', 'INSERT INTO bilikis.document_sequences VALUES ($1,$2,9)', ['pet_sale', '2026-10-05'], '23505');
  await rejects('Generated totals cannot be overwritten manually', 'UPDATE bilikis.stock_in_items SET total_cost=1 WHERE id=$1', [id(311)], '428C9');
  await rejects('Inconsistent void metadata is rejected', 'UPDATE bilikis.rgb_sales SET voided_at=now() WHERE id=$1', [id(501)], '23514');
  await rejects('Duplicate outbox event key is rejected', 'INSERT INTO bilikis.telegram_notification_outbox (event_key,notification_type,event_type) VALUES ($1,$2,$3)', ['DEMO-EVENT-001', 'instant', 'fixture'], '23505');
  await check('Fixture state is unchanged after rejected operations and temporary updates', async () => {
    assert.equal(Number(await scalar('SELECT qty_out FROM bilikis.rgb_sale_items WHERE id=$1', [id(511)])), 12);
    assert.equal(Number(await scalar('SELECT count(*) FROM bilikis.stock_in')), 1);
    assert.equal(Number(await scalar('SELECT sum(line_total) FROM bilikis.rgb_sale_items')), 140000);
  });
} catch (error) {
  fatal = { message: error.message, sqlstate: error.code, stack: error.stack };
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await db.close();
}
const report = {
  status: fatal ? 'fail' : 'pass',
  started_at_utc: started,
  finished_at_utc: new Date().toISOString(),
  engine,
  node_version: process.version,
  pglite_version_expected: pkg.devDependencies['@electric-sql/pglite'],
  dependency_source: process.env.BILIKIS_PGLITE_MODULE ? 'Existing local PGlite installation via environment override' : 'Project dependency installed from package-lock.json',
  input_sha256: Object.fromEntries(sqlFiles.map((path, i) => [path, createHash('sha256').update(sqlSources[i]).digest('hex')])),
  checks,
  outputs,
  limitations: ['Embedded single-client PostgreSQL; no multi-session concurrency evidence', 'No live Supabase connection or RLS/Auth validation', 'Small synthetic correctness dataset; no benchmark claims', 'No production trigger/RPC or Telegram delivery validation'],
  ...(fatal ? { fatal } : {}),
};
if (jsonOutput) {
  console.log(JSON.stringify(report, null, 2));
} else {
  const passed = checks.filter((check) => check.status === 'pass').length;
  console.log(`${report.status.toUpperCase()}: ${passed}/${checks.length} checks`);
}
