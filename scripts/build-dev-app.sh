#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_APP_PATH="$INSTALL_DIR/TypeSwitch.app"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
    CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
export CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP_PATH"
ditto "$ROOT_DIR/.build/TypeSwitch.app" "$INSTALL_APP_PATH"
codesign --verify --deep --strict "$INSTALL_APP_PATH"
echo "$INSTALL_APP_PATH"
echo "Signed with: $CODE_SIGN_IDENTITY"
