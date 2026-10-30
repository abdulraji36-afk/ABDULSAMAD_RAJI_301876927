import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const here = new URL('./', import.meta.url);
const read = (path) => readFile(new URL(path, here), 'utf8');
export const month = ['2026-10-01', '2026-11-01'];

export async function projectSales() {
  const db = new PGlite();
  try {
    await db.exec(await read('../portfolio-1-database-design/sql/01-schema.sql'));
    await db.exec(await read('../portfolio-1-database-design/sql/02-seed.sql'));
    await db.exec(await read('../portfolio-2-query-optimisation/sql/catalogue-fixture.sql'));
    // Give the synthetic references short labels in this fresh Portfolio 4 fixture.
    await db.exec(`
      UPDATE bilikis.customers SET customer_code = substr(customer_code, 6) WHERE customer_code LIKE 'DEMO-%';
      UPDATE bilikis.pet_sales SET sales_no = substr(sales_no, 6) WHERE sales_no LIKE 'DEMO-%';
      UPDATE bilikis.rgb_sales SET sale_no = substr(sale_no, 6) WHERE sale_no LIKE 'DEMO-%';
      UPDATE bilikis.pet_dispatch_trips SET trip_no = substr(trip_no, 6) WHERE trip_no LIKE 'DEMO-%';
      UPDATE bilikis.rgb_dispatch_trips SET trip_no = substr(trip_no, 6) WHERE trip_no LIKE 'DEMO-%';
    `);
    const { rows: sales } = await db.query(await read('sql/project-sales.sql'));
    assert.deepEqual(sales.map((sale) => sale.sale_number), [
      'PET-001', 'PET-002', 'RGB-001', 'RGB-002',
    ]);
    assert.ok(sales.every((sale) => sale.line_items.length > 0));

    const querySource = (await read('../portfolio-2-query-optimisation/sql/queries.sql')).replaceAll('\r\n', '\n');
    const reports = querySource.split(/^-- report: /m);
    const statement = (name) => {
      const section = reports.find((report) => report.startsWith(name + '\n'));
      assert.ok(section, `Missing Portfolio 2 query: ${name}`);
      return section.slice(name.length + 1);
    };
    const { rows: totals } = await db.query(statement('sales-by-channel'), month);
    const { rows: shortages } = await db.query(statement('rgb-shortages'));
    const { rows: [engine] } = await db.query('SELECT version() AS version');
    return { sales, totals, shortages, engine: engine.version };
  } finally {
    await db.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { sales, totals, shortages } = await projectSales();
  console.log(JSON.stringify({ projectedSales: sales.length, sales, totals, shortages }, (_, value) =>
    typeof value === 'bigint' ? String(value) : value, 2));
}
