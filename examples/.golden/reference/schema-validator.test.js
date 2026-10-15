const test = require('node:test');
const assert = require('node:assert');
const { validateEventEnvelope } = require('../src/schema-validator');

test('validateEventEnvelope - validates a compliant legacy event without routingKey', () => {
  const event = {
    eventId: 'evt-101',
    eventType: 'order.created',
    timestamp: 1700000000,
    data: { orderId: 42, amount: 99.5 }
  };

  const outcome = validateEventEnvelope(event);
  assert.strictEqual(outcome.valid, true);
  assert.strictEqual(outcome.errors.length, 0);
});

test('validateEventEnvelope - validates an event with routingKey', () => {
  const event = {
    eventId: 'evt-102',
    eventType: 'order.created',
    timestamp: 1700000000,
    routingKey: 'orders.eu-west-1',
    data: { orderId: 43 }
  };

  const outcome = validateEventEnvelope(event);
  assert.strictEqual(outcome.valid, true);
  assert.strictEqual(outcome.errors.length, 0);
});

test('validateEventEnvelope - catches invalid routingKey format', () => {
  const event = {
    eventId: 'evt-103',
    eventType: 'order.created',
    timestamp: 1700000000,
    routingKey: '', // invalid empty string
    data: { orderId: 44 }
  };

  const outcome = validateEventEnvelope(event);
  assert.strictEqual(outcome.valid, false);
  assert.strictEqual(outcome.errors.some(e => e.includes('routingKey')), true);
});

test('validateEventEnvelope - catches missing required envelope fields', () => {
  const outcome = validateEventEnvelope({});
  assert.strictEqual(outcome.valid, false);
  assert.strictEqual(outcome.errors.length >= 4, true);
});
