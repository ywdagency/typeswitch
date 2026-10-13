#!/usr/bin/env bash
# Default mode produces a notarized DMG; --preview never submits or installs anything.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
BUILD_NUMBER="${2:-}"
MODE="${3:-}"
if [[ $# -lt 2 || $# -gt 3 || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ || ( -n "$MODE" && "$MODE" != --preview ) ]]; then
    echo 'Usage: scripts/build-release.sh X.Y.Z BUILD_NUMBER [--preview]' >&2
    exit 1
fi

SIGN_FOR_DISTRIBUTION=1
SUFFIX=""
if [[ "$MODE" == --preview ]]; then
    CODE_SIGN_IDENTITY="-"
    SIGN_FOR_DISTRIBUTION=0
    SUFFIX="-preview"
elif [[ "${CODE_SIGN_IDENTITY:-}" != 'Developer ID Application:'* || -z "${NOTARYTOOL_PROFILE:-}" ]]; then
    echo 'A Developer ID Application identity and NOTARYTOOL_PROFILE are required. Use --preview only for local packaging checks.' >&2
    exit 1
fi

export VERSION BUILD_NUMBER CODE_SIGN_IDENTITY SIGN_FOR_DISTRIBUTION
export CONFIGURATION=release BUILD_UNIVERSAL=1
NOTARY_ARGS=(--keychain-profile "${NOTARYTOOL_PROFILE:-}")
if [[ -n "${NOTARYTOOL_KEYCHAIN:-}" ]]; then
    NOTARY_ARGS+=(--keychain "$NOTARYTOOL_KEYCHAIN")
fi
"$ROOT_DIR/scripts/build-app.sh"
APP_PATH="$ROOT_DIR/.build/TypeSwitch.app"
for architecture in arm64 x86_64; do
    lipo "$APP_PATH/Contents/MacOS/TypeSwitch" -verify_arch "$architecture"
done
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"
WORK_DIR="$(mktemp -d "$DIST_DIR/.package.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
DMG_NAME="TypeSwitch-$VERSION-macOS-universal$SUFFIX.dmg"

if [[ "$MODE" != --preview ]]; then
    ditto -c -k --keepParent "$APP_PATH" "$WORK_DIR/TypeSwitch.zip"
    xcrun notarytool submit "$WORK_DIR/TypeSwitch.zip" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

mkdir "$WORK_DIR/image"
ditto "$APP_PATH" "$WORK_DIR/image/TypeSwitch.app"
ln -s /Applications "$WORK_DIR/image/Applications"
cp "$ROOT_DIR/docs/installation.md" "$WORK_DIR/image/Read Me.md"
if [[ "$MODE" == --preview ]]; then
    printf 'LOCAL PACKAGING PREVIEW\nAd-hoc signed; not notarized. Not a public installation release.\n' > "$WORK_DIR/image/PREVIEW.txt"
fi
hdiutil create -volname "TypeSwitch $VERSION" -srcfolder "$WORK_DIR/image" -format UDZO -ov "$WORK_DIR/$DMG_NAME"
if [[ "$MODE" != --preview ]]; then
    codesign --sign "$CODE_SIGN_IDENTITY" --timestamp "$WORK_DIR/$DMG_NAME"
    xcrun notarytool submit "$WORK_DIR/$DMG_NAME" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$WORK_DIR/$DMG_NAME"
    xcrun stapler validate "$WORK_DIR/$DMG_NAME"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$WORK_DIR/$DMG_NAME"
fi
hdiutil verify "$WORK_DIR/$DMG_NAME"
mv -f "$WORK_DIR/$DMG_NAME" "$DIST_DIR/$DMG_NAME"
cd "$DIST_DIR"
shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
echo "$DIST_DIR/$DMG_NAME"
