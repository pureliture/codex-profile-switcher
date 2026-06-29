# Security

## Supported Scope

This app protects against local accidental token exposure, corrupted profile
snapshots, interrupted switches, concurrent switch attempts, symlink/hardlink
token-file attacks, unwanted shared-state mutation, and unsigned internal
artifacts.

It does not protect against a compromised macOS user account, compromised Codex
Desktop process, OpenAI service-side token semantics, or cross-machine profile
sync.

## Reporting

Do not include `auth.json`, access tokens, refresh tokens, id tokens,
authorization headers, account IDs, raw command logs, or filesystem dumps in a
public issue.

For internal reports, include only:

- app version or commit SHA
- macOS version
- high-level operation: add profile, switch profile, restart
- redacted transaction state
- whether rollback succeeded
- whether restart succeeded

## Local Data

Profile snapshots are stored in `~/.codex-profile-switcher/profiles/<uuid>/`.
Metadata is stored in `~/.codex-profile-switcher/registry.json`. The registry
must not contain raw token material.

To reset the app state manually, quit the app first, then move
`~/.codex-profile-switcher` aside instead of deleting it until any needed backup
is confirmed.
