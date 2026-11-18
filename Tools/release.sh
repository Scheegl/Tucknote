#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TUCKNOTE_SIGNING_IDENTITY:?Set your Developer ID Application identity}"
: "${TUCKNOTE_NOTARY_PROFILE:?Set your notarytool Keychain profile name}"

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
if [[ ! "$version" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
    printf 'Invalid bundle version: %s\n' "$version" >&2
    exit 1
fi
name="Tucknote-$version-macos-arm64.zip"
mkdir -p build/release
destination="$PWD/build/release"
if [[ -e "$destination/$name" || -e "$destination/$name.sha256" ]]; then
    printf 'Release files already exist for %s. Move them before rebuilding.\n' "$version" >&2
    exit 1
fi
staging="$(mktemp -d "$PWD/build/.release.XXXXXX")"
trap 'rm -r "$staging"' EXIT
TUCKNOTE_BUILD_DIR="$staging/build" ./build.sh
app="$staging/build/Tucknote.app"
ditto -c -k --keepParent "$app" "$staging/submission.zip"
xcrun notarytool submit "$staging/submission.zip" --keychain-profile "$TUCKNOTE_NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --keepParent "$app" "$staging/$name"
(
    cd "$staging"
    shasum -a 256 "$name" > "$name.sha256"
    shasum -a 256 -c "$name.sha256"
)
mv -n "$staging/$name" "$staging/$name.sha256" "$destination/"
printf '%s\n' "$destination/$name" "$destination/$name.sha256"
