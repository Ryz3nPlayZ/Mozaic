#!/usr/bin/env bash
# Creates a Mozaic.dmg containing Mozaic.app, Mozaic Notch.app (when built with
# Scripts/build-notch.sh), and a shortcut to Applications, then mounts it.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build/app"
APP_PATH="$BUILD_DIR/Mozaic.app"
NOTCH_APP_PATH="$BUILD_DIR/Mozaic Notch.app"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/Mozaic.dmg"

echo "💿 Packaging DMG..."

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Mozaic.app not found at $APP_PATH. Please run Scripts/build-app.sh first." >&2
  exit 1
fi

# Clean up previous staging and DMG
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"

# Create staging directory
mkdir -p "$STAGING_DIR"

# Copy app to staging
echo "  → Copying Mozaic.app..."
cp -R "$APP_PATH" "$STAGING_DIR/"
if [[ -d "$NOTCH_APP_PATH" ]]; then
  echo "  → Copying Mozaic Notch.app..."
  cp -R "$NOTCH_APP_PATH" "$STAGING_DIR/"
else
  echo "  → Mozaic Notch.app not built; run Scripts/build-notch.sh to include it."
fi

# Create symlink to Applications folder
echo "  → Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

# Create the DMG
echo "  → Running hdiutil create..."
hdiutil create -volname "Mozaic" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

# Clean up staging directory
rm -rf "$STAGING_DIR"

echo "✅ DMG created successfully at $DMG_PATH"

# Mount the DMG
echo "💿 Mounting DMG..."
hdiutil attach "$DMG_PATH"

echo "🎉 DMG mounted successfully! Drag Mozaic (and Mozaic Notch) to your Applications folder."
