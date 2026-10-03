#!/usr/bin/env bash
# Builds the standalone "Mozaic Notch.app" from the vendored boring.notch fork
# in Notch/ and places it next to Mozaic.app (see ADR-1001). Scripts/create-dmg.sh
# and the release workflow package both apps into one DMG.
#
# The notch is its own app with its own bundle ID, usage strings, entitlements,
# and Sparkle feed, so it owns its TCC identity. Do not embed it in Mozaic.app.
#
# Env:
#   NOTCH_ROOT      boring.notch fork checkout (default: Notch/)
#   MOZAIC_SIGNING  adhoc | dev | developer-id | unsigned (default: dev)
#   APP_IDENTITY    explicit codesign identity
#   ARCHES          architectures to build, e.g. "arm64 x86_64" (default: host)
#
# The notch ships with the same MARKETING_VERSION and BUILD_NUMBER as Mozaic
# (version.env), so both Sparkle feeds advance together.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
NOTCH_ROOT=${NOTCH_ROOT:-"$ROOT/Notch"}
SIGNING_MODE=${MOZAIC_SIGNING:-dev}
BUILD_DIR="$ROOT/.build/app"
DERIVED_DATA="$ROOT/.build/notch-derivedData"
APP_NAME="Mozaic Notch"
BUNDLE_ID="com.zemuliu.MozaicNotch"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

PROJECT="$NOTCH_ROOT/boringNotch.xcodeproj"
if [[ ! -d "$PROJECT" ]]; then
  echo "ERROR: $PROJECT not found. Set NOTCH_ROOT to the Mozaic Notch fork." >&2
  exit 1
fi

ARCH_SETTINGS=()
if [[ -n "${ARCHES:-}" ]]; then
  ARCH_SETTINGS=(ARCHS="$ARCHES" ONLY_ACTIVE_ARCH=NO)
fi

echo "🔨 Building $APP_NAME..."
xcodebuild -project "$PROJECT" \
  -scheme boringNotch \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ${ARCH_SETTINGS[@]+"${ARCH_SETTINGS[@]}"} \
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

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_BUNDLE/Contents/Info.plist")
if [[ "$VERSION" != "$MARKETING_VERSION" || "$BUILD" != "$BUILD_NUMBER" ]]; then
  echo "ERROR: $APP_NAME is $VERSION ($BUILD), expected $MARKETING_VERSION ($BUILD_NUMBER)." >&2
  exit 1
fi

echo ""
echo "✅ $APP_NAME $VERSION ($BUILD)"
echo "📍 App: $APP_BUNDLE"
