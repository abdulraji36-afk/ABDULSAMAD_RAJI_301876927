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

const db = new PGlite();
const query = async (sql, params = []) => (await db.query(sql, params)).rows;
const runReport = (name, params) => query(queries.get(name), params);
const numericStrings = (rows) => rows.map((row) => Object.fromEntries(
  Object.entries(row).map(([column, value]) => [column, value === null ? null : String(value)]),
));

try {
  await db.exec("SET TIME ZONE 'UTC'");
  await db.exec(await read('../portfolio-1-database-design/sql/01-schema.sql'));
  await db.exec(await read('../portfolio-1-database-design/sql/02-seed.sql'));
  await db.exec(await read('sql/catalogue-fixture.sql'));

  const reports = [];
  for (const [name, params, expected] of correctnessCases) {
    const rows = await runReport(name, params);
    assert.deepEqual(numericStrings(rows), expected, name);
    reports.push({ name, params, rows });
  }

  console.log(`${reports.length}/${correctnessCases.length} report checks passed.`);
} finally {
  await db.close();
}
