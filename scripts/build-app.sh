#!/usr/bin/env bash
# Assemble an app without installing or launching it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
APP_PATH="$ROOT_DIR/.build/TypeSwitch.app"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo 'VERSION must be X.Y.Z and BUILD_NUMBER must be a positive integer.' >&2
    exit 1
fi
if [[ "$CONFIGURATION" != debug && "$CONFIGURATION" != release ]]; then
    echo 'CONFIGURATION must be debug or release.' >&2
    exit 1
fi

BUILD_ARGS=(--configuration "$CONFIGURATION" --product TypeSwitch)
if [[ "${BUILD_UNIVERSAL:-0}" == 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
cd "$ROOT_DIR"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
test -d "$BIN_DIR/TypeSwitch_TypeSwitchApp.bundle"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources/Legal/docs"
cp "$BIN_DIR/TypeSwitch" "$APP_PATH/Contents/MacOS/TypeSwitch"
chmod +x "$APP_PATH/Contents/MacOS/TypeSwitch"
ditto "$BIN_DIR/TypeSwitch_TypeSwitchApp.bundle" "$APP_PATH/Contents/Resources/TypeSwitch_TypeSwitchApp.bundle"
cp "$ROOT_DIR/Sources/TypeSwitchApp/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$APP_PATH/Contents/Resources/Legal/LICENSE"
cp "$ROOT_DIR/docs/third-party-notices.md" "$APP_PATH/Contents/Resources/Legal/docs/third-party-notices.md"
ditto "$ROOT_DIR/LICENSES" "$APP_PATH/Contents/Resources/Legal/LICENSES"
cat > "$APP_PATH/Contents/Resources/Legal/SOURCE.txt" <<SOURCE
TypeSwitch $VERSION (build $BUILD_NUMBER, $CONFIGURATION configuration)
Source, bundled dictionary inputs, transformation scripts, and license notices:
https://github.com/ywdagency/typeswitch
Release source: https://github.com/ywdagency/typeswitch/tree/v$VERSION
Release tags become available after publication.
Build revision: $(git rev-parse HEAD)
SOURCE

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>TypeSwitch</string>
    <key>CFBundleExecutable</key><string>TypeSwitch</string>
    <key>CFBundleIdentifier</key><string>com.dmvishnyak.typeswitch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>TypeSwitch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 TypeSwitch contributors.</string>
</dict></plist>
PLIST
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
plutil -lint "$APP_PATH/Contents/Info.plist"
SIGN_ARGS=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "${SIGN_FOR_DISTRIBUTION:-0}" == 1 ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
else
    SIGN_ARGS+=(--timestamp=none)
fi
codesign "${SIGN_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
echo "$APP_PATH"
