#!/usr/bin/env bash
# Build LiteWall.app with the Command Line Tools only (no full Xcode needed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/LiteWall.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

# Only ever remove this project's own previous build output.
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "[1/4] Compiling Swift sources..."
xcrun swiftc -O \
  -target arm64-apple-macosx13.0 \
  "$ROOT"/Sources/*.swift \
  -o "$MACOS/LiteWall"

echo "[2/4] Copying resources..."
cp "$ROOT/Sources/WEShim.js" "$RES/WEShim.js"
cp -R "$ROOT/Wallpapers" "$RES/Wallpapers"

echo "[3/4] Ad-hoc signing (required by WebKit JIT)..."
codesign --force --sign - --identifier "dev.litewall.LiteWall" "$APP"

echo "[4/4] Verifying bundle..."
codesign --verify --verbose=1 "$APP" 2>&1 | tail -2 || true

echo
echo "Built: $APP"
echo "Run:   open \"$APP\""
echo "Stop:  osascript -e 'tell application \"LiteWall\" to quit'  (or use the menu bar icon)"
