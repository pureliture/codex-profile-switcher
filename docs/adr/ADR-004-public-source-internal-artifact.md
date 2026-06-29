# ADR-004: Public Source With Internal Signed Artifacts

## Status

Accepted.

## Context

The source can be reviewed publicly, but team distribution requires a trustworthy
binary path.

## Decision

Keep source public. Distribute initial binaries only through an internal channel
after `ReleaseGate` checks pass: public commit SHA, MIT license, upstream
attribution, Developer ID signing, notarization proof, checksum, no public
binary release, and no PR build secrets.

## Consequences

- Teammates can audit source and verify checksum provenance.
- Public GitHub release binaries are excluded from v1.
- Signing and notarization evidence stays in the internal release channel.
