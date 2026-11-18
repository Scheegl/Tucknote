#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
build_dir="${TUCKNOTE_BUILD_DIR:-$PWD/build}"
mkdir -p "$build_dir"
staging="$(mktemp -d "$build_dir/.build.XXXXXX")"
trap 'rm -r "$staging"' EXIT
app="$staging/Tucknote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun swiftc -module-cache-path "$build_dir/ModuleCache" -target arm64-apple-macos13.0 \
    -parse-as-library Sources/Brand.swift Tools/AppIcon.swift -o "$staging/app-icon"
"$staging/app-icon" "$app/Contents/Resources/Tucknote.icns"
cp Info.plist "$app/Contents/"
cp LICENSE "$app/Contents/Resources/"
xcrun --sdk macosx swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-cache-path "$build_dir/ModuleCache" -target arm64-apple-macos13.0 \
    -O -warnings-as-errors -parse-as-library Sources/*.swift -o "$app/Contents/MacOS/Tucknote"
if [[ -n "${TUCKNOTE_SIGNING_IDENTITY:-}" ]]; then
    if [[ "$TUCKNOTE_SIGNING_IDENTITY" != "Developer ID Application: "* ]]; then
        printf '%s\n' 'A Developer ID Application identity is required for distribution.' >&2
        exit 1
    fi
    codesign --force --options runtime --timestamp --sign "$TUCKNOTE_SIGNING_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --strict "$app"
ditto "$app" "$build_dir/Tucknote.app"
codesign --verify --strict "$build_dir/Tucknote.app"
printf '%s\n' "$build_dir/Tucknote.app"
