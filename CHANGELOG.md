# Changelog

All notable changes to **Claude Autopilot** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
* **Autonomous SWE Pipeline:** 3-phase state machine orchestrating ticket intake, deterministic TDD implementation, and adversarial review-and-fix iterations.
* **Deterministic Quality Gates:** External POSIX Bash gates (`gate-tests.sh`, `gate-build.sh`) validating compiler and test verdicts with zero model self-grading.
* **Asymmetric Context Isolation:** Decoupled authoring and review roles using asymmetric model tiers (Sonnet implementer vs. Opus adversarial reviewer).
* **Multi-Repo Coordination Architecture:** Dynamic repository discovery, isolated workspace clones, unified cross-repo test planning, and atomic cross-linked PRs.
* **Crash-Resilient State Protocol:** Disk-persisted execution state in `$STATE/state.json` allowing uninterrupted pipeline resumption across sessions.
* **Private Feed Resilience:** Automatic offline package cache fallback and environment failure escalation for protected NuGet/npm package registries.
* **Formal Architecture Specification (RFC-001):** Complete protocol specification in `docs/SPECIFICATION.md` detailing state transitions, JSON schemas, gate contracts, and convergence proofs.
* **Documentation & Community Suite:** Comprehensive Security Policy (`SECURITY.md`), Contributor Guide (`CONTRIBUTING.md`), and visual architecture diagrams.
