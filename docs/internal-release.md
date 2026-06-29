# Internal Release Checklist

Do not publish a public GitHub release binary for v1. Use this checklist for
team-only distribution.

## Preflight

- Confirm the source tree is clean.
- Confirm the build commit is a public commit SHA.
- Run `swift run CodexProfileSwitcherCoreTests`.
- Run `swift build`.
- Confirm `LICENSE` and `NOTICE.md` are included in the artifact.
- Confirm the artifact was not built from a pull request context with CI secrets.

## Build

```sh
bash scripts/build-app.sh
```

The unsigned app bundle is created under `.build/artifacts/`.
Without `CODE_SIGN_IDENTITY`, the script applies an ad hoc local signature so
bundle structure and resource sealing can be validated. Internal distribution
must still use the expected Developer ID identity.

## Sign And Notarize

Sign with the expected Developer ID identity:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: YOUR TEAM" bash scripts/build-app.sh
```

Create notarization evidence:

```sh
ditto -c -k --keepParent ".build/artifacts/Codex Profile Switcher.app" ".build/artifacts/Codex Profile Switcher.zip"
xcrun notarytool submit ".build/artifacts/Codex Profile Switcher.zip" --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple ".build/artifacts/Codex Profile Switcher.app"
```

Capture the notary output as internal evidence. Do not commit credentials or
notary logs that contain private account details.

## Checksum

```sh
shasum -a 256 ".build/artifacts/Codex Profile Switcher.zip"
```

Publish the checksum in the internal distribution channel next to the artifact.

## Release Gate

The build is distributable only when all `ReleaseGate` conditions pass:

- valid 40-character commit SHA
- MIT license included
- upstream visual attribution included
- Developer ID signing identity recorded
- notarization proof recorded
- SHA-256 checksum recorded
- no public binary release
- no pull request build secrets
