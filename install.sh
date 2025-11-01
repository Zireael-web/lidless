#!/usr/bin/env zsh
set -euo pipefail

ROOT=${0:A:h}
APP="$ROOT/build/Lidless.app"
INSTALL="/Applications/Lidless.app"
GUI_DOMAIN="gui/$(id -u)"
APP_PLIST="$HOME/Library/LaunchAgents/app.lidless.Lidless.plist"
WATCHDOG_PLIST="$HOME/Library/LaunchAgents/app.lidless.LidlessWatchdog.plist"
NO_LAUNCH=false

if [[ "${1:-}" == "--no-launch" ]]; then
  NO_LAUNCH=true
fi

"$ROOT/build.sh"

launchctl bootout "$GUI_DOMAIN" "$APP_PLIST" 2>/dev/null || true
launchctl bootout "$GUI_DOMAIN" "$WATCHDOG_PLIST" 2>/dev/null || true
launchctl bootout "$GUI_DOMAIN/app.lidless.Lidless" 2>/dev/null || true
launchctl bootout "$GUI_DOMAIN/app.lidless.LidlessWatchdog" 2>/dev/null || true

if pgrep -f "$INSTALL/Contents/MacOS/Lidless" >/dev/null; then
  echo "→ stopping existing Lidless"
  pkill -f "$INSTALL/Contents/MacOS/Lidless" || true
  sleep 0.5
fi

if pgrep -f "$INSTALL/Contents/Library/Helpers/LidlessWatchdog" >/dev/null; then
  echo "→ stopping existing watchdog"
  pkill -f "$INSTALL/Contents/Library/Helpers/LidlessWatchdog" || true
  sleep 0.5
fi

echo "→ installing to /Applications"
rm -rf "$INSTALL"
cp -R "$APP" "$INSTALL"
xattr -dr com.apple.quarantine "$INSTALL" 2>/dev/null || true

if [[ "$NO_LAUNCH" == false ]]; then
  echo "→ launching"
  open "$INSTALL"
else
  launchctl bootout "$GUI_DOMAIN/app.lidless.Lidless" 2>/dev/null || true
  launchctl bootout "$GUI_DOMAIN/app.lidless.LidlessWatchdog" 2>/dev/null || true
  echo "→ launch skipped"
fi

echo "→ installed: $INSTALL"
