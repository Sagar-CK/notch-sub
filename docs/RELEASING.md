# Releasing

## Preview checklist

1. Update `VERSION`, `CHANGELOG.md`, and `docs/releases/<version>.md`.
2. Run `./scripts/check.sh` and `./scripts/package.sh --universal`.
3. Check notch and menu bar placement, Settings, refresh, and compact display. Use demo data for screenshots.
4. Review the diff and artifacts for private data. Do not switch real accounts as a release check.
5. Wait for both architecture checks on `main` to pass.
6. Tag that commit as `v<version>` and push the tag.

The release workflow verifies the version, reruns checks, builds universal installers, validates an extracted app, and publishes a GitHub prerelease.

## Artifacts

| Artifact | Purpose |
| --- | --- |
| `.app` | Native macOS app |
| `.dmg` | Drag-to-install download |
| `.zip` | App archive |
| `SHA256SUMS.txt` | Download integrity checks |

Artifacts contain the app, license notices, and installation instructions. They never include account data. Omit `--universal` for a host-only build. CI test artifacts expire after 14 days; release downloads persist.

## Signing

Previews use ad-hoc signing. Keep that status explicit in the README, installer, and release notes.

For notarized distribution: configure a private Developer ID certificate, sign with the hardened runtime and timestamp, submit to Apple, staple the ticket, validate on a clean Mac, then recreate the final installers and checksums. Keep signing credentials out of source and pull-request CI.

[Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
