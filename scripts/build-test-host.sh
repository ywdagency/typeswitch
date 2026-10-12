#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_NAME="TypeSwitchTestHost"
APP_BUNDLE_ID="com.dmvishnyak.typeswitch.testhost"
BUILD_APP_PATH="$ROOT_DIR/.build/${APP_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_APP_PATH="$INSTALL_DIR/${APP_NAME}.app"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
APP_PATH="$BUILD_APP_PATH"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
EXECUTABLE_PATH="$MACOS_PATH/$APP_NAME"

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION" --product "$APP_NAME"

BUILT_BIN_DIR="$(swift build --configuration "$CONFIGURATION" --product "$APP_NAME" --show-bin-path)"
BUILT_EXECUTABLE="$BUILT_BIN_DIR/$APP_NAME"

rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH"
cp "$BUILT_EXECUTABLE" "$EXECUTABLE_PATH"
chmod +x "$EXECUTABLE_PATH"

cat > "$CONTENTS_PATH/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>TypeSwitch Test Host</string>
    <key>CFBundleExecutable</key>
    <string>TypeSwitchTestHost</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TypeSwitch Test Host</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_PATH/PkgInfo"

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
    CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
    CODE_SIGN_IDENTITY="-"
fi

codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_PATH" >/dev/null

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP_PATH"
ditto "$BUILD_APP_PATH" "$INSTALL_APP_PATH"
codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$INSTALL_APP_PATH" >/dev/null

echo "$INSTALL_APP_PATH"
echo "Signed with: $CODE_SIGN_IDENTITY"
