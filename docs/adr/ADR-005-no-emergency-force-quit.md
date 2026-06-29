# ADR-005: Emergency Force-Quit Excluded

## Status

Accepted.

## Context

Codex Desktop needs to restart after a profile switch. Force-quitting could lose
active work or create shared-state churn.

## Decision

Request graceful termination and reopen Codex after verified switch. Do not add
emergency force-quit behavior in v1.

## Consequences

- Restart failure is reported separately from switch failure.
- Verified auth switches are not rolled back merely because reopening failed.
- Any future force-quit path requires a separate ADR and explicit confirmation.
