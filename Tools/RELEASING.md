# Release Tucknote

Run the build and offline checks on a clean checkout. Confirm the bundle version in `Info.plist` and tag the reviewed commit with the matching version (for example, `v1.7` for bundle version `1.7`). Increment both the release version and build number. The in-app checker compares numeric versions and uses the ZIP produced by the release script to identify a release with an app download.

Pushing to `main` makes source changes available to contributors. To announce an update in the app, publish a stable GitHub Release from a version tag. The checker ignores drafts and pre-releases. A source-only release works without Apple credentials and points users to GitHub's generated source archive. With immutable releases enabled, publish the first notarized app under a new version if the preceding release contained source only.

On the release Mac, install a **Developer ID Application** certificate and configure an Apple `notarytool` Keychain profile. Supply the identity and profile names as `TUCKNOTE_SIGNING_IDENTITY` and `TUCKNOTE_NOTARY_PROFILE`, then run `./Tools/release.sh`. Signing keys and Apple credentials stay in Keychain. The script builds with Hardened Runtime, verifies the signature, notarizes the bundle, staples and validates the ticket, assesses the app with Gatekeeper, then creates the ZIP and SHA-256 checksum in `build/release`.

Download and open the candidate on an Apple Silicon Mac with Gatekeeper enabled. Confirm quick capture, search, and opening a public link. Attach the ZIP and checksum to a **draft** GitHub Release for the tag, then verify the assets before publishing. The source archive is generated from the tag by GitHub.

On the public repository, enable private vulnerability reporting, protect `main` with the build check, and enable immutable releases if available. Keep the PR workflow read-only and separate from signing and release publication.
