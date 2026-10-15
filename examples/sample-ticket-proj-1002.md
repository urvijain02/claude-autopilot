# PROJ-1002: Enforce Maximum Clock Skew Tolerance on Token Verification

**Issue Type:** Security / Improvement  
**Components:** `sandbox-repo/src/token-verifier.js`  
**Primary Repository:** `./examples/sandbox-repo`  

## Summary
The token verification utility permits callers to supply an arbitrary `clockSkewSeconds` value. If an excessive clock skew is supplied, expired tokens can remain valid indefinitely, violating security policy.

## Acceptance Criteria
1. The `clockSkewSeconds` option must be strictly capped at 300 seconds (5 minutes). Any requested skew greater than 300 seconds must clamp to 300 or throw a validation error.
2. Negative clock skew values must be clamped to 0.
3. Tokens with an explicit `exp` timestamp in the past beyond the permitted clock skew must consistently throw `Token expired`.
4. Unit tests in `test/token-verifier.test.js` must verify the boundary conditions.

## Out of Scope
* Implementing asymmetric RSA / ECDSA cryptographic verification.
