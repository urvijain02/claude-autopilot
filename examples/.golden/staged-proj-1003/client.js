/**
 * Event publisher client for the microservice event pipeline.
 */
class EventPublisherClient {
  /**
   * @param {Object} [config]
   */
  constructor(config = {}) {
    this.config = config;
  }

  /**
   * Constructs an event envelope formatted for the microservice ingestion gate.
   *
   * @param {string} eventType - The event name.
   * @param {Object} data - Payload data.
   * @returns {Object} Serialized envelope.
   */
  buildEnvelope(eventType, data = {}) {
    if (!eventType || typeof eventType !== 'string') {
      throw new Error('eventType is required');
    }

    const envelope = {
      eventId: `evt-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
      eventType,
      timestamp: Math.floor(Date.now() / 1000),
      data
    };

    return envelope;
  }
}

module.exports = { EventPublisherClient };
