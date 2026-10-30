#!/usr/bin/env bash
# Builds Orbit.app into ./build. macOS only grants camera/mic/screen access to a real
# app bundle, so `swift run` alone isn't enough.
#
#   scripts/build-app.sh              # release build, ad-hoc signed
#   SIGN_IDENTITY="Apple Development: you@example.com" scripts/build-app.sh
#
# With ad-hoc signing macOS may re-ask for Screen Recording permission after each rebuild.
# Signing with a stable identity (any free Apple Development cert) avoids that.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="$ROOT/build/Orbit.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Orbit" "$APP/Contents/MacOS/Orbit"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP"
