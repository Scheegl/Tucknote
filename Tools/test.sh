#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
staging="$(mktemp -d "${TMPDIR:-/tmp}/tucknote-tests.XXXXXX")"
trap 'rm -r "$staging"' EXIT
mkdir -p build
xcrun swiftc -module-cache-path "$PWD/build/ModuleCache" -target arm64-apple-macos13.0 \
    -warnings-as-errors -parse-as-library Sources/Inbox.swift Sources/LinkMetadata.swift \
    Tests/InboxChecks.swift -o "$staging/check"
"$staging/check" "$staging"
