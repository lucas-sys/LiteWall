#!/usr/bin/env bash
# Reproducible verification: build -> static/runtime shim contract -> window layer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"

echo "== [1/4] Build LiteWall.app =="
"$ROOT/build.sh"

echo
echo "== [2/4] Compile verification probes =="
xcrun swiftc "$ROOT/tools/shim-probe.swift" -o "$BUILD/shim-probe"
codesign -s - --force "$BUILD/shim-probe" >/dev/null 2>&1 || true
xcrun swiftc "$ROOT/tools/window-probe.swift" -o "$BUILD/window-probe"

echo
echo "== [3/4] Verify WEShim runtime contract for every bundled wallpaper =="
for dir in "$ROOT/Wallpapers"/*/; do
    echo "-- $(basename "$dir")"
    "$BUILD/shim-probe" "$dir" "$ROOT/Sources/WEShim.js"
done

echo
echo "== [4/4] Verify desktop-level window (requires a running app) =="
if pgrep -x LiteWall >/dev/null 2>&1; then
    "$BUILD/window-probe"
else
    echo "LiteWall is not running — skipped."
    echo "To check manually:  open \"$BUILD/LiteWall.app\" && \"$BUILD/window-probe\""
fi

echo
echo "Verification complete."
