#!/usr/bin/env bash
#
# ByDesk rebrand — scoped, constants-first, dependency-safe.
# Run with GNU sed on PATH (macOS): PATH="$(brew --prefix gnu-sed)/libexec/gnubin:$PATH"
#
set -euo pipefail

# ---------------- CONFIG (real ByDesk values) ----------------
APP_NAME="ByDesk"
ORG="com.bydesk"
BUNDLE_ID="com.bydesk.app"
DESC="ByDesk Remote Desktop"
SCHEME="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')"   # bydesk
RENDEZVOUS="relay.bydesk.app"                               # DevOps value (hbbs host)
PUBKEY="iD4pYd4Nu6awcd0RV9yj0IyQyv7bXZXybCCbkaPob5k="       # server id_ed25519.pub
UPDATE_API="https://api.bydesk.app/version/latest"          # update endpoint
COPYRIGHT="Copyright © 2026 ByDesk. All rights reserved."
# -------------------------------------------------------------

CFG="libs/hbb_common/src/config.rs"
LIB="libs/hbb_common/src/lib.rs"
[ -f "$CFG" ] || { echo "ERROR: $CFG not found. Did you clone --recurse-submodules?"; exit 1; }

echo "==> 1/6 core constants (hbb_common)"
sed -i "s|RwLock::new(\"RustDesk\".to_owned())|RwLock::new(\"${APP_NAME}\".to_owned())|" "$CFG"
sed -i "s|\"rs-ny.rustdesk.com\"|\"${RENDEZVOUS}\"|" "$CFG"
sed -i "s|OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=|${PUBKEY}|" "$CFG"
sed -i "s|https://api.rustdesk.com/version/latest|${UPDATE_API}|" "$LIB"

echo "==> 2/6 Cargo package metadata (deps untouched)"
sed -i '0,/^name = "rustdesk"/s//name = "bydesk"/' Cargo.toml
sed -i "s|^description = \"RustDesk Remote Desktop\"|description = \"${DESC}\"|" Cargo.toml
sed -i 's|^default-run = "rustdesk"|default-run = "bydesk"|' Cargo.toml
sed -i "s|^name = \"RustDesk\"\$|name = \"${APP_NAME}\"|" Cargo.toml
sed -i "s|identifier = \"com.carriez.rustdesk\"|identifier = \"${BUNDLE_ID}\"|" Cargo.toml

echo "==> 3/6 Flutter pubspec"
sed -i "s|^description: .*|description: ${DESC}|" flutter/pubspec.yaml

echo "==> 4/6 macOS packaging"
AX="flutter/macos/Runner/Configs/AppInfo.xcconfig"
sed -i "s|PRODUCT_NAME = RustDesk|PRODUCT_NAME = ${APP_NAME}|" "$AX"
sed -i "s|PRODUCT_BUNDLE_IDENTIFIER = com.carriez.flutterHbb|PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID}|" "$AX"
sed -i "s|PRODUCT_COPYRIGHT = .*|PRODUCT_COPYRIGHT = ${COPYRIGHT}|" "$AX"
sed -i "s|com.carriez.rustdesk|${BUNDLE_ID}|g" flutter/macos/Runner/Info.plist
sed -i "s|com.carriez.rustdesk|${BUNDLE_ID}|g" flutter/macos/Runner.xcodeproj/project.pbxproj
sed -i "s|<string>rustdesk</string>|<string>${SCHEME}</string>|" flutter/macos/Runner/Info.plist

echo "==> 5/6 Dart literals"
sed -i "s|\"RustDesk\",|\"${APP_NAME}\",|" flutter/lib/desktop/widgets/tabbar_widget.dart

echo "==> 6/6 done."
