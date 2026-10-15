const test = require('node:test');
const assert = require('node:assert');
const { paginate } = require('../src/paginate');

test('paginate - returns first page of items with correct defaults', () => {
  const items = Array.from({ length: 25 }, (_, i) => `item-${i + 1}`);
  const result = paginate(items, { page: 1, pageSize: 10 });

  assert.strictEqual(result.totalItems, 25);
  assert.strictEqual(result.totalPages, 3);
  assert.strictEqual(result.currentPage, 1);
  assert.strictEqual(result.items.length, 10);
  assert.strictEqual(result.items[0], 'item-1');
  assert.strictEqual(result.items[9], 'item-10');
  assert.strictEqual(result.hasNext, true);
  assert.strictEqual(result.hasPrev, false);
});

test('paginate - correctly handles last page with exact remainder', () => {
  const items = Array.from({ length: 25 }, (_, i) => `item-${i + 1}`);
  const result = paginate(items, { page: 3, pageSize: 10 });

  assert.strictEqual(result.currentPage, 3);
  assert.strictEqual(result.items.length, 5);
  assert.strictEqual(result.items[0], 'item-21');
  assert.strictEqual(result.items[4], 'item-25');
  assert.strictEqual(result.hasNext, false);
  assert.strictEqual(result.hasPrev, true);
});

test('paginate - correctly handles exact multiple of pageSize (PROJ-1001 AC1)', () => {
  const items = Array.from({ length: 20 }, (_, i) => `item-${i + 1}`);
  const result = paginate(items, { page: 2, pageSize: 10 });

  assert.strictEqual(result.totalItems, 20);
  assert.strictEqual(result.totalPages, 2);
  assert.strictEqual(result.currentPage, 2);
  assert.strictEqual(result.items.length, 10);
  assert.strictEqual(result.items[0], 'item-11');
  assert.strictEqual(result.items[9], 'item-20');
  assert.strictEqual(result.hasNext, false);
  assert.strictEqual(result.hasPrev, true);
});

test('paginate - handles out-of-range page gracefully with empty items', () => {
  const items = ['a', 'b', 'c'];
  const result = paginate(items, { page: 99, pageSize: 10 });

  assert.strictEqual(result.totalItems, 3);
  assert.strictEqual(result.items.length, 0);
  assert.strictEqual(result.hasNext, false);
  assert.strictEqual(result.hasPrev, true);
});

test('paginate - handles empty or non-array inputs', () => {
  const result = paginate(null);
  assert.strictEqual(result.totalItems, 0);
  assert.strictEqual(result.totalPages, 1);
  assert.strictEqual(result.items.length, 0);
});
