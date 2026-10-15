# Sandbox Consumer Client Repository

This repository represents a dependent consumer library that coordinates with the `sandbox-repo` microservice event envelope in **Task PROJ-1003** (Multi-Repo Schema Coordination).

## Purpose
Demonstrates Claude Autopilot's **Multi-Repo Coordination Architecture**:
1. `sandbox-repo` updates the server event schema.
2. `sandbox-client` updates client serialization to pass the new `routingKey` field.
3. Tests in both repositories are verified independently.
4. Coordinated pull requests are opened atomically.
