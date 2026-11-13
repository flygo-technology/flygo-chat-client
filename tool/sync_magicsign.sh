#!/usr/bin/env bash
# Copies the Magic Sign extension (extensions/sign-relay) and its app shim
# (apps/mobile/assets/app) into assets/magicsign/, so the "Ký số" browser runs
# the same code as the Chrome extension, the Electron browser and the Magic
# Sign mobile app.
#   tool/sync_magicsign.sh <path to a vietnam-usb-token-signer checkout>
set -euo pipefail
SRC="${1:?path to vietnam-usb-token-signer}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/assets/magicsign"
mkdir -p "$OUT"
rsync -a --delete --exclude '*.test.mjs' --exclude README.md "$SRC/extensions/sign-relay/" "$OUT/ext/"
mkdir -p "$OUT/app"
for f in engine.html page-bridge.js prompt.html shim.js; do cp "$SRC/apps/mobile/assets/app/$f" "$OUT/app/$f"; done
REV=$(git -C "$SRC" rev-parse --short HEAD)
VER=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$OUT/ext/manifest.json" | head -1)
printf '%s %s\n' "$VER" "$REV" > "$OUT/VERSION"
echo "assets/magicsign: sign-relay $VER ($REV)"
