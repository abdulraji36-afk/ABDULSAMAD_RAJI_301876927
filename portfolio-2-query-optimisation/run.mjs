import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const here = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, here), 'utf8');
const sqlSource = await read('sql/queries.sql');
const markers = [...sqlSource.matchAll(/^-- report: ([a-z-]+)\s*$/gm)];
const queries = new Map(markers.map((marker, index) => [
  marker[1],
  sqlSource.slice(marker.index + marker[0].length, markers[index + 1]?.index).trim(),
]));
assert.equal(queries.size, 6);

const sampleMonth = ['2026-10-01', '2026-11-01'];
const correctnessCases = [
  ['low-stock', [50], [
    { product_code: 'F_PET_50', product_name: 'FANTA ORANGE 50CL X12 PET', unit: 'Packs', current_stock: '30' },
  ]],
  ['sales-by-channel', sampleMonth, [
    { channel: 'PET', sale_count: '2', recorded_sales_value: '30000' },
    { channel: 'RGB', sale_count: '2', recorded_sales_value: '140000' },
  ]],
  ['rgb-shortages', [], [
    { customer_code: 'DEMO-CUS-001', sale_no: 'DEMO-RGB-001', expected_empties: '12',
      initial_returns: '8', additional_returns: '2', outstanding: '2' },
  ]],
  ['stock-valuation', [], [
    { product_code: 'C_PET_50', product_name: 'COCA COLA LS 50CL X12 PET',
      unit: 'Packs', current_stock: '85', buying_cost: '1500', estimated_stock_value: '127500' },
    { product_code: 'C_RGB', product_name: 'COCA COLA ULTRA LS 50CL X24 RGB',
      unit: 'Crates', current_stock: '60', buying_cost: '6200', estimated_stock_value: '372000' },
    { product_code: 'F_PET_50', product_name: 'FANTA ORANGE 50CL X12 PET',
      unit: 'Packs', current_stock: '30', buying_cost: null, estimated_stock_value: null },
  ]],
  ['customer-pet-history', ['DEMO-CUS-001', ...sampleMonth], [
    { id: '00000000-0000-0000-0000-000000000401', sales_no: 'DEMO-PET-001', sale_date: '2026-10-05', payment_type: 'cash' },
  ]],
  ['product-movement-period', ['C_PET_50', ...sampleMonth], [
    { movement_count: '3', received: '100', issued: '15', net_movement: '85' },
  ]],
];

const benchmarkWindow = ['2026-07-01', '2026-11-01'];
const benchmarks = [
  { name: 'customer-pet-history', params: ['BENCH-CUS-0042', ...benchmarkWindow],
    table: 'pet_sales', index: 'p2_pet_sales_customer_date_idx' },
  { name: 'product-movement-period', params: ['C_PET_50', ...benchmarkWindow],
    table: 'stock_movements', index: 'p2_stock_movements_product_date_idx' },
];

const warmups = 2;
const samples = 7;
const started = new Date().toISOString();
const db = new PGlite();
const query = async (sql, params = []) => (await db.query(sql, params)).rows;
const runReport = (name, params) => query(queries.get(name), params);
const numericStrings = (rows) => rows.map((row) => Object.fromEntries(
  Object.entries(row).map(([column, value]) => [column, value === null ? null : String(value)]),
));

function planNodes(node) {
  return [node, ...(node.Plans ?? []).flatMap(planNodes)];
}

async function measure({ name, params, table, index }) {
  const plans = [];
  for (let run = 0; run < warmups + samples; run++) {
    const [row] = await query(`EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)\n${queries.get(name)}`, params);
    const value = row['QUERY PLAN'];
    const [plan] = typeof value === 'string' ? JSON.parse(value) : value;
    if (run >= warmups) plans.push(plan);
  }
  const executionMs = plans.map((plan) => plan['Execution Time']);
  const medianPlan = [...plans].sort((a, b) => a['Execution Time'] - b['Execution Time'])[Math.floor(samples / 2)];
  const nodes = planNodes(medianPlan.Plan);
  return {
    execution_ms: executionMs,
    median_ms: medianPlan['Execution Time'],
    shared_blocks: (medianPlan.Plan['Shared Hit Blocks'] ?? 0) + (medianPlan.Plan['Shared Read Blocks'] ?? 0),
    scan_nodes: nodes.filter((node) => node['Relation Name'] === table || node['Index Name'] === index)
      .map((node) => ({ type: node['Node Type'], index: node['Index Name'] ?? null, actual_rows: node['Actual Rows'] })),
    plan: medianPlan,
  };
}

try {
  await db.exec("SET TIME ZONE 'UTC'");
  const [{ version }] = await query('SELECT version()');
  await db.exec(await read('../portfolio-1-database-design/sql/01-schema.sql'));
  await db.exec(await read('../portfolio-1-database-design/sql/02-seed.sql'));
  await db.exec(await read('sql/catalogue-fixture.sql'));

  const reports = [];
  for (const [name, params, expected] of correctnessCases) {
    const rows = await runReport(name, params);
    assert.deepEqual(numericStrings(rows), expected, name);
    reports.push({ name, params, rows });
  }

  await db.exec(await read('sql/benchmark-fixture.sql'));
  await db.exec('ANALYZE bilikis.customers, bilikis.products, bilikis.pet_sales, bilikis.stock_movements');
  const [dataset] = await query(`SELECT
    (SELECT count(*)::integer FROM bilikis.customers) AS customers,
    (SELECT count(*)::integer FROM bilikis.products) AS products,
    (SELECT count(*)::integer FROM bilikis.pet_sales) AS pet_sales,
    (SELECT count(*)::integer FROM bilikis.pet_sale_items) AS pet_sale_items,
    (SELECT count(*)::integer FROM bilikis.stock_movements) AS stock_movements`);
  assert.deepEqual(dataset, { customers: 402, products: 122, pet_sales: 60002,
    pet_sale_items: 60002, stock_movements: 57519 });

  const comparisons = [];
  for (const spec of benchmarks) {
    const rows = await runReport(spec.name, spec.params);
    assert.ok(rows.length > 0 && (spec.name !== 'product-movement-period' || rows[0].movement_count > 0),
      `Benchmark must select actual rows: ${spec.name}`);
    const before = await measure(spec);
    assert.ok(before.scan_nodes.some((node) => node.type === 'Seq Scan'), `Baseline scan missing: ${spec.name}`);
    comparisons.push({ ...spec, rows, before });
  }

  // Keep the data and query text fixed. These two indexes are the only change.
  await db.exec(await read('sql/indexes.sql'));
  for (const comparison of comparisons) {
    const rows = await runReport(comparison.name, comparison.params);
    assert.deepEqual(rows, comparison.rows, `Index changed results: ${comparison.name}`);
    comparison.after = await measure(comparison);
    assert.ok(comparison.after.scan_nodes.some((node) => node.index === comparison.index),
      `Planner did not choose the measured index: ${comparison.index}`);
    const [{ bytes }] = await query('SELECT pg_relation_size($1::regclass)::integer AS bytes', [`bilikis.${comparison.index}`]);
    comparison.index_bytes = bytes;
    comparison.same_results = true;
  }

  const report = {
    started_at_utc: started,
    finished_at_utc: new Date().toISOString(),
    engine: version,
    node: process.version,
    dataset,
    measurement: { warmup_runs_per_phase: warmups, measured_runs_per_phase: samples,
      shared_blocks: 'Shared Hit Blocks plus Shared Read Blocks at the root plan node' },
    reports,
    benchmarks: comparisons,
  };
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(report, (_, value) => typeof value === 'bigint' ? String(value) : value, 2));
  } else {
    console.log(`${reports.length}/${correctnessCases.length} report checks passed.`);
    for (const { name, before, after } of comparisons) {
      console.log(`${name}: ${before.median_ms.toFixed(3)} ms → ${after.median_ms.toFixed(3)} ms, ${before.shared_blocks} → ${after.shared_blocks} shared blocks. Results match.`);
    }
  }
} finally {
  await db.close();
}
