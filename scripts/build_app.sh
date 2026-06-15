#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Arkiv"
DIST="$ROOT/dist"
APP="$DIST/Arkiv.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

export CLANG_MODULE_CACHE_PATH="$PROJECT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT/.build/swiftpm-module-cache"
export XDG_CACHE_HOME="$PROJECT/.build/cache"

swift build --package-path "$PROJECT" -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$PROJECT/.build/release/Arkiv" "$MACOS/Arkiv"

# Plist & PkgInfo
cp "$PROJECT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Icon
cp "$PROJECT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

codesign --force --deep --sign - "$APP" >/dev/null

# Remove quarantine so macOS doesn't block launch on this machine
xattr -cr "$APP" 2>/dev/null || true

echo "$APP"
