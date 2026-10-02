#!/usr/bin/env bash
# Builds the standalone "Mozaic Notch.app" from the boring.notch fork and
# packages it as "Mozaic Notch.dmg" next to Mozaic.app (see ADR-1001).
#
# The notch is its own app with its own bundle ID, usage strings, entitlements,
# and Sparkle feed, so it owns its TCC identity. Do not embed it in Mozaic.app.
#
# Env:
#   NOTCH_ROOT      boring.notch checkout (default: ../boring.notch)
#   MOZAIC_SIGNING  adhoc | dev | developer-id | unsigned (default: dev)
#   APP_IDENTITY    explicit codesign identity

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NOTCH_ROOT=${NOTCH_ROOT:-"$ROOT/../boring.notch"}
SIGNING_MODE=${MOZAIC_SIGNING:-dev}
BUILD_DIR="$ROOT/.build/app"
DERIVED_DATA="$ROOT/.build/notch-derivedData"
APP_NAME="Mozaic Notch"
BUNDLE_ID="com.zemuliu.MozaicNotch"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

PROJECT="$NOTCH_ROOT/boringNotch.xcodeproj"
if [[ ! -d "$PROJECT" ]]; then
  echo "ERROR: $PROJECT not found. Clone the Mozaic Notch fork or set NOTCH_ROOT." >&2
  exit 1
fi

echo "🔨 Building $APP_NAME..."
xcodebuild -project "$PROJECT" \
  -scheme boringNotch \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

PRODUCT="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$PRODUCT" ]]; then
  echo "ERROR: expected $PRODUCT. Is the fork's PRODUCT_NAME still \"$APP_NAME\"?" >&2
  exit 1
fi

ACTUAL_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PRODUCT/Contents/Info.plist")
if [[ "$ACTUAL_ID" != "$BUNDLE_ID" ]]; then
  echo "ERROR: $APP_NAME has bundle ID $ACTUAL_ID, expected $BUNDLE_ID." >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
rm -rf "$APP_BUNDLE"
cp -R "$PRODUCT" "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# ── Code signing ──────────────────────────────────────────────────────────────

case "$SIGNING_MODE" in
  unsigned|none)
    CODESIGN_ARGS=()
    ;;
  adhoc)
    CODESIGN_ARGS=(--force --sign -)
    ;;
  dev|development)
    CODESIGN_ID=${APP_IDENTITY:-$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}' || true)}
    if [[ -z "$CODESIGN_ID" ]]; then
      echo "WARN: No Apple Development certificate found. Falling back to ad-hoc signing."
      CODESIGN_ARGS=(--force --sign -)
    else
      CODESIGN_ARGS=(--force --options runtime --sign "$CODESIGN_ID")
    fi
    ;;
  developer-id|distribution|release)
    CODESIGN_ID=${APP_IDENTITY:-$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)".*/\1/' || true)}
    if [[ -z "$CODESIGN_ID" ]]; then
      echo "ERROR: No Developer ID Application certificate found for release signing." >&2
      exit 1
    fi
    CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$CODESIGN_ID")
    ;;
  *)
    echo "ERROR: Unknown MOZAIC_SIGNING mode: $SIGNING_MODE" >&2
    exit 1
    ;;
esac

if [[ ${#CODESIGN_ARGS[@]} -gt 0 ]]; then
  echo "🔏 Signing $APP_NAME..."
  resign() { codesign "${CODESIGN_ARGS[@]}" "$1"; }

  # Innermost first: Sparkle's helpers, then each framework, then the XPC helper.
  SPARKLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
  if [[ -d "$SPARKLE" ]]; then
    for xpc in Downloader Installer; do
      [[ -d "$SPARKLE/XPCServices/$xpc.xpc" ]] && resign "$SPARKLE/XPCServices/$xpc.xpc"
    done
    [[ -d "$SPARKLE/Updater.app" ]] && resign "$SPARKLE/Updater.app"
    [[ -f "$SPARKLE/Autoupdate" ]] && resign "$SPARKLE/Autoupdate"
  fi
  for framework in "$APP_BUNDLE"/Contents/Frameworks/*.framework; do
    [[ -d "$framework" ]] && resign "$framework"
  done
  XPC_HELPER="$APP_BUNDLE/Contents/XPCServices/BoringNotchXPCHelper.xpc"
  if [[ -d "$XPC_HELPER" ]]; then
    codesign "${CODESIGN_ARGS[@]}" \
      --entitlements "$NOTCH_ROOT/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements" "$XPC_HELPER"
  fi

  # The source entitlements use Xcode's $(PRODUCT_BUNDLE_IDENTIFIER), which
  # codesign does not expand.
  ENTITLEMENTS="$BUILD_DIR/MozaicNotch.entitlements"
  sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    "$NOTCH_ROOT/boringNotch/boringNotch.entitlements" > "$ENTITLEMENTS"
  codesign "${CODESIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
  codesign --verify --deep --strict "$APP_BUNDLE"
else
  echo "🔓 Skipping code signing."
fi

# ── DMG ───────────────────────────────────────────────────────────────────────

echo "💿 Packaging $APP_NAME.dmg..."
STAGING_DIR="$BUILD_DIR/notch-dmg-staging"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING_DIR"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")
echo ""
echo "✅ $APP_NAME $VERSION"
echo "📍 App: $APP_BUNDLE"
echo "📍 DMG: $DMG_PATH"
