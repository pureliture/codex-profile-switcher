# ADR-001: Local Filesystem Token Storage

## Status

Accepted.

## Context

Codex Desktop uses `~/.codex/auth.json` as the active local login state. The app
needs multiple profile snapshots while keeping all other Codex state shared.

## Decision

Store profile snapshots under
`~/.codex-profile-switcher/profiles/<uuid>/auth.json` and metadata in
`~/.codex-profile-switcher/registry.json`. Use app-private directory
permissions and token-file validation instead of Keychain storage in v1.

## Consequences

- Switching can replace only `~/.codex/auth.json`.
- Profile paths are stable UUID paths and are not derived from email.
- File permissions and symlink/hardlink checks are mandatory.
- Cross-machine sync is out of scope.
