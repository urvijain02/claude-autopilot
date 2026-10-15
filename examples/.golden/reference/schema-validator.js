/**
 * Validates incoming microservice event envelopes.
 *
 * @param {Object} event - Event envelope payload.
 * @returns {Object} Validation outcome { valid: boolean, errors: string[] }
 */
function validateEventEnvelope(event) {
  const errors = [];

  if (!event || typeof event !== 'object') {
    return { valid: false, errors: ['Event payload must be a non-null object'] };
  }

  if (!event.eventId || typeof event.eventId !== 'string') {
    errors.push('Missing or invalid required field: eventId (string)');
  }

  if (!event.eventType || typeof event.eventType !== 'string') {
    errors.push('Missing or invalid required field: eventType (string)');
  }

  if (!event.timestamp || typeof event.timestamp !== 'number') {
    errors.push('Missing or invalid required field: timestamp (epoch number)');
  }

  if (!event.data || typeof event.data !== 'object') {
    errors.push('Missing or invalid required field: data (object)');
  }

  // Routing key validation (optional field for topic partitioning)
  if (event.routingKey !== undefined) {
    if (typeof event.routingKey !== 'string' || event.routingKey.trim() === '') {
      errors.push('Field routingKey must be a non-empty string when provided');
    }
  }

  return {
    valid: errors.length === 0,
    errors
  };
}

module.exports = { validateEventEnvelope };
