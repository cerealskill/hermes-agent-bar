#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="HermesBar.app"

cd "$PROJECT_DIR"
./scripts/build_app.sh

rm -rf "/Applications/$APP_NAME"
cp -R "build/$APP_NAME" "/Applications/$APP_NAME"

echo "Installed /Applications/$APP_NAME"
echo "Launch with: open /Applications/$APP_NAME"
