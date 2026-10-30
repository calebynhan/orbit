#!/usr/bin/env bash
# Builds Orbit.app, then wraps it in a drag-to-Applications DMG at build/Orbit-<version>.dmg.
# Uses only tools that ship with macOS (hdiutil, osascript), so nothing to install.
#
#   scripts/build-dmg.sh                       # ad-hoc signed beta
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Orbit.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/Orbit-$VERSION.dmg"
STAGING="$ROOT/build/dmg-staging"
VOLUME="Orbit $VERSION"

"$ROOT/scripts/build-app.sh"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Beta builds aren't notarized; tell people how to get past Gatekeeper once.
if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
  cat > "$STAGING/READ ME FIRST.txt" <<'EOF'
Orbit beta — how to open it the first time

This beta isn't signed with an Apple Developer ID yet, so macOS shows
"Orbit can't be opened" on first launch. One-time fix:

  1. Drag Orbit to Applications, then double-click it (it will refuse).
  2. Open System Settings → Privacy & Security.
  3. Scroll down to the "Orbit was blocked" message and click Open Anyway.
  4. Click Open. macOS remembers this; you won't be asked again.

Orbit then asks for Camera, Microphone, and Screen Recording permission.
Everything stays on your Mac. Recordings are saved to ~/Movies/Orbit.
EOF
fi

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

# Publish this next to the DMG so people can check their download wasn't swapped.
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
echo "SHA-256: $(cut -d' ' -f1 "$DMG.sha256")"
