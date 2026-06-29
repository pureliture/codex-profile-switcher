# ADR-003: Official Login Through Temporary Codex Home

## Status

Accepted.

## Context

The app must not implement OAuth or token refresh directly. It also must not
depend on `codex-auth`.

## Decision

Create a temporary app-owned `CODEX_HOME`, run the official Codex login command
against that home, validate the resulting temporary `auth.json`, import it as a
profile snapshot, and remove the temporary home.

## Consequences

- OAuth remains owned by Codex.
- The real `~/.codex/auth.json` is fingerprinted before and after login.
- Cancelled, failed, missing, or invalid login output creates no profile.
- Terminal/device-code login remains a fallback/debug mode, not the default UX.
