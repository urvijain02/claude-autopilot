# Bundled Evaluation Sandbox Repository

This directory is a minimal, self-contained mock repository used by **Claude Autopilot** to benchmark SWE-agent workflows with zero external dependencies and zero setup.

## Technical Characteristics
* **Runtime:** Node.js (18+ / 20+ / 24+ native `node:test`).
* **Dependencies:** Zero external npm packages (no `node_modules` required).
* **Test Execution Speed:** Under 150ms for all suites.

## Benchmark Modules & Tasks
* **PROJ-1001 (Boundary Bugfix):** `src/paginate.js` & `test/paginate.test.js` — Array slicing and pagination boundary handling.
* **PROJ-1002 (Security & Auth):** `src/token-verifier.js` & `test/token-verifier.test.js` — Clock skew, token expiration, and signature security invariants.
* **PROJ-1003 (Contract Coordination):** `src/schema-validator.js` & `test/schema-validator.test.js` — Microservice envelope schema validator coordinated with `examples/sandbox-client/`.

## Running Tests
```bash
npm test
# or directly
node --test
```
