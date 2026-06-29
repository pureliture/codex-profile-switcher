# ADR-002: Shared-State Verifier Semantics

## Status

Accepted.

## Context

The intended behavior is that account switching changes only
`~/.codex/auth.json`. Sessions, history, MCP, skills, plugins, and config must
remain shared.

## Decision

Capture a baseline before auth replacement and verify again before restarting
Codex. Use strong hashes for config and metadata files, and lightweight
fingerprints for larger directories such as sessions and logs.

## Consequences

- Unknown shared-state changes fail closed before restart.
- Verification failure after auth replacement triggers rollback.
- Restart-created session or log churn is avoided by verifying before restart.
