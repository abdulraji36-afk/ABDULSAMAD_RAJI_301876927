import assert from 'node:assert/strict';
import { BSON, Decimal128, MongoClient } from 'mongodb';
import { month, projectSales } from './project-sales.mjs';

const databaseName = 'bilikis_portfolio4';
const connection = process.env.P4_MONGODB_URL;
assert.ok(connection, 'Set P4_MONGODB_URL to the disposable MongoDB server.');
const url = new URL(connection);
assert.ok(url.protocol === 'mongodb:'
  && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)
  && url.pathname === `/${databaseName}` && !url.search && !url.hash,
`Use a loopback MongoDB connection to a fresh database named ${databaseName}.`);

const saleSchema = {
  bsonType: 'object',
  required: ['_id', 'channel', 'saleNumber', 'customerCode', 'saleDate', 'status', 'lineItems'],
  properties: {
    _id: { bsonType: 'string' },
    channel: { enum: ['PET', 'RGB'] },
    saleNumber: { bsonType: 'string' },
    customerCode: { bsonType: 'string' },
    saleDate: { bsonType: 'date' },
    status: { enum: ['approved', 'dispatched', 'closed', 'draft'] },
    sourceSaleId: { bsonType: 'string' },
    lineItems: {
      bsonType: 'array',
      minItems: 1,
      items: {
        bsonType: 'object',
        required: ['productCode', 'productName', 'unit', 'quantity', 'unitPrice'],
        properties: {
          productCode: { bsonType: 'string' },
          productName: { bsonType: 'string' },
          unit: { bsonType: 'string' },
          quantity: { bsonType: 'decimal', minimum: 0, exclusiveMinimum: true },
          unitPrice: { bsonType: 'decimal', minimum: 0 },
        },
      },
    },
    dispatch: {
      bsonType: 'object',
      properties: {
        tripNumber: { bsonType: ['string', 'null'] },
        tripStatus: { bsonType: 'string' },
        expectedEmpties: { bsonType: 'int', minimum: 0 },
        initialReturns: { bsonType: 'int', minimum: 0 },
        followupReturns: { bsonType: 'int', minimum: 0 },
      },
    },
  },
};

const decimal = (value) => Decimal128.fromString(value);
const date = (value) => new Date(`${value}T00:00:00.000Z`);
const started = new Date().toISOString();
const projection = await projectSales();
const documents = projection.sales.map((row) => ({
  _id: `${row.channel}:${row.sale_number}`,
  sourceSaleId: row.source_id,
  channel: row.channel,
  saleNumber: row.sale_number,
  saleDate: date(row.sale_date),
  customerCode: row.customer_code,
  status: row.status,
  lineItems: row.line_items.map((line) => ({
    ...line, quantity: decimal(line.quantity), unitPrice: decimal(line.unitPrice),
  })),
  ...(row.dispatch ? { dispatch: row.dispatch } : {}),
}));

const client = new MongoClient(connection, { serverSelectionTimeoutMS: 5000, connectTimeoutMS: 5000 });
try {
  await client.connect();
  const db = client.db(databaseName);
  assert.equal((await db.listCollections().toArray()).length, 0, 'Start with an empty Portfolio 4 database.');
  const buildInfo = await db.command({ buildInfo: 1 });
  const sales = await db.createCollection('sales', { validator: { $jsonSchema: saleSchema } });
  const indexName = await sales.createIndex({ customerCode: 1, saleDate: -1, _id: 1 }, { name: 'customer_sales_history' });
  const inserted = await sales.insertMany(documents);
  assert.equal(inserted.insertedCount, 4);

  const customerSales = await sales.find({
    customerCode: 'CUS-001',
    saleDate: { $gte: date(month[0]), $lt: date(month[1]) },
  }).sort({ saleDate: -1, _id: 1 }).toArray();
  assert.deepEqual(customerSales.map((sale) => sale._id), ['RGB:RGB-001', 'PET:PET-001']);
  assert.equal(customerSales[0].lineItems[0].productCode, 'C_RGB');

  const draft = {
    _id: 'PET:P4-DRAFT-001', channel: 'PET', saleNumber: 'P4-DRAFT-001',
    saleDate: date('2026-10-30'), customerCode: 'CUS-001', status: 'draft',
    lineItems: [{ ...documents[0].lineItems[0], quantity: decimal('1') }],
  };
  const create = await sales.insertOne(draft);
  assert.equal(create.insertedId, draft._id);
  const filter = { _id: draft._id, status: 'draft' };
  const found = await sales.findOne(filter);
  assert.equal(found.lineItems[0].quantity.toString(), '1');
  const update = await sales.updateOne(filter, { $set: { 'lineItems.0.quantity': decimal('3') } });
  assert.deepEqual([update.matchedCount, update.modifiedCount], [1, 1]);
  const changed = await sales.findOne(filter);
  assert.equal(changed.lineItems[0].quantity.toString(), '3');
  const deleted = await sales.deleteOne(filter);
  assert.equal(deleted.deletedCount, 1);
  assert.equal(await sales.findOne(filter), null);
  let validationError;
  try {
    await sales.insertOne({ ...draft, _id: 'PET:P4-INVALID', lineItems: [] });
  } catch (error) {
    assert.equal(error.code, 121, error.message);
    validationError = error.code;
  }
  assert.equal(validationError, 121, 'An empty line item array must be rejected.');
  const persisted = await sales.countDocuments();
  assert.equal(persisted, 4);

  const monthlyTotals = await sales.aggregate([
    { $match: { status: { $in: ['approved', 'dispatched', 'closed'] },
      saleDate: { $gte: date(month[0]), $lt: date(month[1]) } } },
    { $project: { channel: 1, saleValue: { $sum: { $map: {
      input: '$lineItems', as: 'line', in: { $multiply: ['$$line.quantity', '$$line.unitPrice'] },
    } } } } },
    { $group: { _id: '$channel', saleCount: { $sum: 1 }, salesValue: { $sum: '$saleValue' } } },
    { $sort: { _id: 1 } },
  ]).toArray();
  const mongoTotals = monthlyTotals.map((row) => ({
    channel: row._id, sale_count: row.saleCount, recorded_sales_value: row.salesValue.toString(),
  }));
  const sqlTotals = projection.totals.map((row) => ({
    ...row, sale_count: Number(row.sale_count), recorded_sales_value: String(row.recorded_sales_value),
  }));
  assert.deepEqual(mongoTotals, sqlTotals);

  const mongoShortages = await sales.aggregate([
    { $match: { channel: 'RGB', status: { $in: ['dispatched', 'closed'] }, 'dispatch.expectedEmpties': { $exists: true } } },
    { $project: { _id: 0, customer_code: '$customerCode', sale_no: '$saleNumber',
      outstanding: { $subtract: ['$dispatch.expectedEmpties', {
        $add: ['$dispatch.initialReturns', '$dispatch.followupReturns'],
      }] } } },
    { $match: { outstanding: { $gt: 0 } } },
    { $sort: { outstanding: -1, sale_no: 1, customer_code: 1 } },
  ]).toArray();
  const sqlShortages = projection.shortages.map((row) => ({
    customer_code: row.customer_code, sale_no: row.sale_no, outstanding: Number(row.outstanding),
  }));
  assert.deepEqual(mongoShortages, sqlShortages);

  const evidence = {
    started_at_utc: started,
    finished_at_utc: new Date().toISOString(),
    mongodb: buildInfo.version,
    postgresql: projection.engine,
    collection: sales.collectionName,
    index: indexName,
    imported_documents: inserted.insertedCount,
    persisted_documents: persisted,
    customer_history: customerSales.map((sale) => sale._id),
    sample_document: BSON.EJSON.serialize(customerSales[0]),
    crud: { inserted_id: create.insertedId, quantity_before: found.lineItems[0].quantity.toString(),
      matched: update.matchedCount, modified: update.modifiedCount,
      quantity_after: changed.lineItems[0].quantity.toString(), deleted: deleted.deletedCount },
    schema_validation_error_code: validationError,
    sales_totals: { mongodb: mongoTotals, postgresql: sqlTotals, match: true },
    shortages: { mongodb: mongoShortages, postgresql: sqlShortages, match: true },
  };
  if (process.argv.includes('--json')) {
    console.log(JSON.stringify(evidence, null, 2));
  } else {
    console.log(`MongoDB ${evidence.mongodb}: ${persisted} posted sales, customer lookup and draft CRUD passed.`);
    console.log(`Schema validation rejected an empty line item array with code ${validationError}.`);
    console.log('Sales totals and RGB shortages match the PostgreSQL reports.');
  }
} finally {
  await client.close();
}
