# Releasing

## Preview releases

1. Update `VERSION`, the changelog, and `docs/releases/<version>.md`.
2. Run `./scripts/check.sh` on macOS, then `./scripts/package.sh --universal`.
3. Launch the packaged app and check notch placement, menu bar mode, Settings, and a refresh. Use demo data for shared screenshots. Do not switch real accounts as an automated release check.
4. Review the diff and images for credentials, real account identities, personal paths, and private configuration.
5. Wait for both architecture jobs in `.github/workflows/ci.yml` to pass before tagging a release.
6. Tag the reviewed commit as `v<version>` and push that tag. `.github/workflows/release.yml` reruns both architecture checks, builds a universal app, checks an extracted copy, and publishes a GitHub **prerelease** with a DMG, ZIP, and `SHA256SUMS.txt`. The notes must disclose that the preview is not Apple-notarized.

`./scripts/package.sh` builds for the current host architecture; `--universal` builds both Apple Silicon and Intel. Artifacts contain the app and license notices, plus installation instructions in the DMG. Credentials and caches are never bundled. A DMG is created with Apple's `hdiutil`; no packaging dependencies are required.

The regular CI workflow also keeps per-architecture test artifacts for 14 days. Release assets persist with their GitHub release.

## Public binary distribution

The preview script uses ad-hoc signing. Before promoting downloads to a notarized release, configure a Developer ID certificate, sign with the hardened runtime and timestamp, submit the signed archive to Apple's notarization service, staple the accepted ticket, and validate the result on a clean Mac. Recreate the final DMG, ZIP, and checksums after stapling. Update the README, packaged Read Me, and release notes to describe the actual signing status.

Keep signing credentials in private CI secrets. Do not commit certificates, private keys, passwords, or notarization credentials. Public binary signing is deliberately separate from pull-request CI.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for the current signing and submission requirements.
