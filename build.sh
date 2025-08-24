#!/usr/bin/env zsh
set -euo pipefail

ROOT=${0:A:h}
SRC="$ROOT/Lidless"
WATCHDOG_SRC="$ROOT/LidlessWatchdog"
APP="$ROOT/build/Lidless.app"
INFO="$SRC/Info.plist"
RES="$SRC/Resources"
MAIN_BIN="$APP/Contents/MacOS/Lidless"
WATCHDOG_BIN="$APP/Contents/Library/Helpers/LidlessWatchdog"

echo "→ generating icon"
xcrun swift "$ROOT/tools/generate_icons.swift" "$RES"

echo "→ preparing bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/Helpers"
cp "$INFO" "$APP/Contents/Info.plist"
cp "$RES/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

MAIN_SWIFT_FILES=("${(@f)$(find "$SRC" -name "*.swift" -type f)}")
WATCHDOG_SWIFT_FILES=(
  "$WATCHDOG_SRC/WatchdogMain.swift"
  "$SRC/Core/Display/PrivateDisplayAPI.swift"
  "$SRC/Persistence/StateStore.swift"
)

echo "→ compiling Lidless"
xcrun swiftc \
  -target arm64-apple-macosx13.0 \
  -O \
  -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework Combine \
  -framework CoreGraphics \
  -Xlinker -sectcreate \
  -Xlinker __TEXT \
  -Xlinker __info_plist \
  -Xlinker "$INFO" \
  -o "$MAIN_BIN" \
  "${MAIN_SWIFT_FILES[@]}"

echo "→ compiling watchdog"
xcrun swiftc \
  -target arm64-apple-macosx13.0 \
  -O \
  -parse-as-library \
  -framework Foundation \
  -framework CoreGraphics \
  -o "$WATCHDOG_BIN" \
  "${WATCHDOG_SWIFT_FILES[@]}"

find "$APP" -name '._*' -delete
xattr -cr "$APP" 2>/dev/null || true

echo "→ signing"
codesign --sign - --force --options runtime "$WATCHDOG_BIN" >/dev/null
codesign --sign - --force --deep --options runtime "$APP" >/dev/null

echo "→ packaging"
mkdir -p "$ROOT/dist"
COPYFILE_DISABLE=1 ditto -c -k --keepParent "$APP" "$ROOT/dist/Lidless.app.zip"
if command -v pkgbuild >/dev/null; then
  COPYFILE_DISABLE=1 pkgbuild \
    --component "$APP" \
    --install-location /Applications \
    --identifier app.lidless.Lidless.pkg \
    --version 0.1.0 \
    "$ROOT/dist/Lidless.pkg" >/dev/null
fi

echo "→ done"
echo "$APP"
