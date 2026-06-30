#!/usr/bin/env bash
#
# ByDesk macOS release: build -> sign inside-out -> DMG -> sign -> notarize -> staple -> verify.
# Prereqs: Developer ID Application cert in keychain + notary profile 'bydesk-notary' stored.
#
#   SIGN_ID="Developer ID Application: <Your Org> (TEAMID)" ./build-release.sh
#
set -euo pipefail
cd "$(dirname "$0")"

# --- config ---
APP_NAME="ByDesk"
APP="flutter/build/macos/Build/Products/Release/${APP_NAME}.app"
ENTITLEMENTS="flutter/macos/Runner/Release.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-bydesk-notary}"
DMG="${APP_NAME}.dmg"

# Auto-detect the Developer ID Application identity if not provided.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/')}"
[ -n "$SIGN_ID" ] || { echo "ERROR: no 'Developer ID Application' identity found. Create the cert first."; exit 1; }
echo "==> Signing identity: $SIGN_ID"

# --- 1. build (skip with SKIP_BUILD=1 if ByDesk.app already built) ---
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  export LANG=en_US.UTF-8 VCPKG_ROOT="$HOME/vcpkg" CARGO_NET_OFFLINE=true
  export PATH="$HOME/cmake331/CMake.app/Contents/bin:$HOME/flutter/bin:$HOME/.pub-cache/bin:$PATH"
  echo "==> building (cargo offline + flutter macos)"
  MACOSX_DEPLOYMENT_TARGET=10.14 cargo build --offline --features flutter --release
  python3 ./build.py --flutter --skip-cargo
fi
[ -d "$APP" ] || { echo "ERROR: $APP not found"; exit 1; }

# --- 2. sign inside-out (deepest Mach-O first, then bundles, then the app), hardened runtime + timestamp ---
SIGN=(codesign -s "$SIGN_ID" --force --options runtime --timestamp)
echo "==> signing dylibs"
find "$APP/Contents/Frameworks" -name "*.dylib" -print0 2>/dev/null | xargs -0 -I{} "${SIGN[@]}" "{}"
echo "==> signing framework bundles"
find "$APP/Contents/Frameworks" -name "*.framework" -type d -print0 2>/dev/null | xargs -0 -I{} "${SIGN[@]}" "{}"
echo "==> signing helper executables (ByDesk, service)"
find "$APP/Contents/MacOS" -type f -print0 2>/dev/null | xargs -0 -I{} "${SIGN[@]}" "{}"
echo "==> signing app bundle (with entitlements)"
codesign -s "$SIGN_ID" --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP"
echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- 3. DMG + sign it ---
echo "==> building DMG"
rm -f "$DMG"
create-dmg --volname "${APP_NAME} Installer" --app-drop-link 600 185 --icon "${APP_NAME}.app" 200 190 \
  --hide-extension "${APP_NAME}.app" "$DMG" "$APP" || create-dmg "$DMG" "$APP"
codesign -s "$SIGN_ID" --force --options runtime --timestamp "$DMG"

# --- 4. notarize + staple ---
echo "==> notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# --- 5. verify (what a clean Mac sees) ---
echo "==> verify"
spctl -a -vvv -t install "$DMG" || true
codesign -dvv "$APP" 2>&1 | grep -i runtime || true
echo "==> DONE: $DMG"
