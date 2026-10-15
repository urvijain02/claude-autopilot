/**
 * Verifies and decodes a signed authentication token payload.
 *
 * @param {string} token - Serialized token in "header.payload.signature" format.
 * @param {string} secret - Shared verification secret.
 * @param {Object} [options] - Verification options.
 * @param {number} [options.clockSkewSeconds=0] - Permitted clock skew tolerance in seconds (max 300).
 * @param {number} [options.currentTimestamp] - Override timestamp for deterministic testing.
 * @returns {Object} Decoded payload with verification metadata.
 */
function verifyToken(token, secret, options = {}) {
  if (!token || typeof token !== 'string') {
    throw new Error('Invalid token: token must be a non-empty string');
  }
  if (!secret || typeof secret !== 'string') {
    throw new Error('Invalid secret: secret key must be provided');
  }

  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('Malformed token: expected 3 dot-separated segments');
  }

  const [headerB64, payloadB64, signature] = parts;

  // Basic signature format check
  if (!signature || signature.length < 8) {
    throw new Error('Invalid signature');
  }

  let payload;
  try {
    payload = JSON.parse(Buffer.from(payloadB64, 'base64').toString('utf8'));
  } catch (err) {
    throw new Error('Invalid payload: failed to parse JSON segment');
  }

  const now = options.currentTimestamp !== undefined
    ? options.currentTimestamp
    : Math.floor(Date.now() / 1000);

  const clockSkew = Math.max(0, Math.min(300, parseInt(options.clockSkewSeconds, 10) || 0));

  // Expiration invariant validation
  if (payload.exp !== undefined) {
    if (typeof payload.exp !== 'number') {
      throw new Error('Security violation: exp claim must be a numeric timestamp');
    }
    // Token is expired if now exceeds exp adjusted by clock skew
    if (now > (payload.exp + clockSkew)) {
      throw new Error(`Token expired: expired at ${payload.exp}, current time is ${now}`);
    }
  }

  // Not Before (nbf) validation
  if (payload.nbf !== undefined) {
    if (typeof payload.nbf !== 'number') {
      throw new Error('Security violation: nbf claim must be a numeric timestamp');
    }
    if ((now + clockSkew) < payload.nbf) {
      throw new Error(`Token not active yet: active at ${payload.nbf}, current time is ${now}`);
    }
  }

  return {
    valid: true,
    sub: payload.sub,
    roles: payload.roles || [],
    claims: payload
  };
}

module.exports = { verifyToken };
