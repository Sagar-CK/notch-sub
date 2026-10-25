# Releasing

## Source and test artifacts

1. Update the version in `scripts/build.sh` and the changelog.
2. Run `./scripts/check.sh` on macOS, then `./scripts/package.sh --skip-build`.
3. Launch the packaged app and check notch placement, menu bar mode, Settings, and a refresh. Use demo data for shared screenshots. Do not switch real accounts as an automated release check.
4. Review the diff and images for credentials, real account identities, personal paths, and private configuration.
5. Wait for both architecture jobs in `.github/workflows/ci.yml` to pass before tagging a release.
6. Tag the reviewed commit and publish release notes describing verified providers and known limitations. Attach the appropriate architecture's ZIP and its matching SHA-256 file only after deciding whether it is a test artifact or a signed public binary.

`./scripts/package.sh` builds for the current host architecture. CI creates separate Apple Silicon and Intel artifacts. Artifacts contain the app and license notices; credentials and caches are never bundled.

## Public binary distribution

The current script uses ad-hoc signing. Before offering a normal downloadable binary, configure a Developer ID certificate, sign with the hardened runtime and timestamp, submit the signed archive to Apple's notarization service, staple the accepted ticket, and validate the result on a clean Mac. Recreate the final ZIP and checksum after stapling.

Keep signing credentials in private CI secrets. Do not commit certificates, private keys, passwords, or notarization credentials. Public binary signing is deliberately separate from pull-request CI.

See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for the current signing and submission requirements.
