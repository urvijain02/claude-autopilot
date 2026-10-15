const test = require('node:test');
const assert = require('node:assert');
const { EventPublisherClient } = require('../src/client');

test('EventPublisherClient - constructs valid envelope without routingKey', () => {
  const client = new EventPublisherClient();
  const envelope = client.buildEnvelope('user.signup', { userId: 'u-101' });

  assert.strictEqual(envelope.eventType, 'user.signup');
  assert.strictEqual(envelope.data.userId, 'u-101');
  assert.strictEqual(envelope.routingKey, undefined);
  assert.strictEqual(typeof envelope.timestamp, 'number');
  assert.strictEqual(envelope.eventId.startsWith('evt-'), true);
});

test('EventPublisherClient - attaches routingKey when configured', () => {
  const client = new EventPublisherClient({ routingKey: 'billing.events' });
  const envelope = client.buildEnvelope('billing.invoiced', { invoiceId: 999 });

  assert.strictEqual(envelope.routingKey, 'billing.events');
  assert.strictEqual(envelope.eventType, 'billing.invoiced');
});

test('EventPublisherClient - validates required eventType', () => {
  const client = new EventPublisherClient();
  assert.throws(() => client.buildEnvelope(''), /eventType is required/);
});
