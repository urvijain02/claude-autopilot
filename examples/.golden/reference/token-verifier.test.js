const test = require('node:test');
const assert = require('node:assert');
const { verifyToken } = require('../src/token-verifier');

function createMockToken(payload, secret = 'supersecret') {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64');
  const sig = Buffer.from(`${header}.${body}.${secret}`).toString('base64').substring(0, 16);
  return `${header}.${body}.${sig}`;
}

test('verifyToken - validates an active token with claims', () => {
  const now = 1700000000;
  const token = createMockToken({ sub: 'user-123', roles: ['admin'], exp: now + 3600 });
  const result = verifyToken(token, 'my-secret', { currentTimestamp: now });

  assert.strictEqual(result.valid, true);
  assert.strictEqual(result.sub, 'user-123');
  assert.deepStrictEqual(result.roles, ['admin']);
});

test('verifyToken - rejects expired tokens without clock skew', () => {
  const now = 1700000000;
  const token = createMockToken({ sub: 'user-123', exp: now - 10 });

  assert.throws(
    () => verifyToken(token, 'my-secret', { currentTimestamp: now }),
    /Token expired/
  );
});

test('verifyToken - allows token within valid clock skew tolerance', () => {
  const now = 1700000000;
  // Token expired 15 seconds ago
  const token = createMockToken({ sub: 'user-123', exp: now - 15 });

  // Clock skew of 30 seconds allows it
  const result = verifyToken(token, 'my-secret', {
    currentTimestamp: now,
    clockSkewSeconds: 30
  });

  assert.strictEqual(result.valid, true);
  assert.strictEqual(result.sub, 'user-123');
});

test('verifyToken - rejects malformed tokens', () => {
  assert.throws(() => verifyToken('not-a-token', 'my-secret'), /Malformed token/);
  assert.throws(() => verifyToken('', 'my-secret'), /Invalid token/);
});
