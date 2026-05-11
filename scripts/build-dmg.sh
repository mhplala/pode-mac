#!/usr/bin/env bash
# Build Pode in Release configuration → sign with Developer ID Application
# → bundle into a DMG → submit for Apple notarization → staple the ticket.
#
# After notarization + stapling, Gatekeeper on a fresh Mac will accept the
# .app on first double-click — no "right-click → Open" dance needed.
#
# Usage:
#   ./scripts/build-dmg.sh                # Developer ID + notarize (default)
#   ./scripts/build-dmg.sh --ad-hoc       # Quick local-only build (skip notarize)
#   ./scripts/build-dmg.sh --skip-notarize  # Sign Developer ID but don't notarize
#
# Prereqs (one-time):
#   1. Have a "Developer ID Application: …" cert in your login keychain.
#      Verify with: `security find-identity -v -p codesigning`
#   2. Run ./scripts/notarize-setup.sh once to store Apple credentials in
#      keychain. This step is skipped if you pass --ad-hoc / --skip-notarize.

set -euo pipefail

# ---- Args ------------------------------------------------------------------
MODE="release"   # release (default) | adhoc | release-no-notarize
for arg in "$@"; do
    case "$arg" in
        --ad-hoc|--adhoc)       MODE="adhoc" ;;
        --skip-notarize)        MODE="release-no-notarize" ;;
        *)
            # Treat anything else as a custom icon source path.
            ICON_SRC_OVERRIDE="$arg"
            ;;
    esac
done

# ---- Resolve paths ---------------------------------------------------------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT_NAME="Pode"
SCHEME="Pode"
ICONSET="$ROOT/Pode/Resources/Assets.xcassets/AppIcon.appiconset"
ICON_SRC="${ICON_SRC_OVERRIDE:-$ROOT/icon-source.png}"
BUILD_DIR="$ROOT/build/release"
DERIVED="$BUILD_DIR/derived"
APP_NAME="Pode.app"
DMG_VOL_NAME="Pode"
NOTARY_PROFILE="pode-notary"

mkdir -p "$BUILD_DIR" "$DERIVED"

VERSION="$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*"\(.*\)".*/\1/' || echo "0.1.0")"
DMG_PATH="$BUILD_DIR/Pode-${VERSION}.dmg"

if [[ ! -d "/Applications/Xcode.app" ]]; then
    echo "❌ Xcode.app not found in /Applications. This script requires the full Xcode."
    exit 1
fi
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# ---- Pick a signing identity -----------------------------------------------
if [[ "$MODE" == "adhoc" ]]; then
    SIGN_IDENTITY="-"
    TEAM_ID=""
    echo "ℹ️  Mode: ad-hoc (no Developer ID, no notarization)"
else
    # Auto-detect Developer ID Application identity. We prefer "Developer ID
    # Application:" — that's what Apple requires for notarization.
    SIGN_LINE="$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -1 || true)"
    if [[ -z "$SIGN_LINE" ]]; then
        echo "❌ No 'Developer ID Application' identity found in keychain."
        echo "   Run: security find-identity -v -p codesigning"
        echo "   Or pass --ad-hoc to skip Developer ID signing."
        exit 1
    fi
    SIGN_IDENTITY="$(echo "$SIGN_LINE" | awk -F'"' '{print $2}')"
    # Team ID is the parenthesized chunk at the end of the identity name.
    TEAM_ID="$(echo "$SIGN_IDENTITY" | grep -Eo '\([A-Z0-9]+\)' | tr -d '()')"
    echo "🔑 Identity: $SIGN_IDENTITY  (team $TEAM_ID)"
fi

# ---- 1. Regenerate AppIcon -------------------------------------------------
if [[ -f "$ICON_SRC" ]]; then
    echo "🎨 Generating AppIcon from $ICON_SRC"
    sizes=(
        "16:icon_16x16.png"
        "32:icon_16x16@2x.png"
        "32:icon_32x32.png"
        "64:icon_32x32@2x.png"
        "128:icon_128x128.png"
        "256:icon_128x128@2x.png"
        "256:icon_256x256.png"
        "512:icon_256x256@2x.png"
        "512:icon_512x512.png"
        "1024:icon_512x512@2x.png"
    )
    for entry in "${sizes[@]}"; do
        px="${entry%%:*}"
        name="${entry##*:}"
        sips -s format png \
             -Z "$px" \
             "$ICON_SRC" \
             --out "$ICONSET/$name" >/dev/null
    done
    cat > "$ICONSET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
else
    echo "⚠️  $ICON_SRC not found — keeping existing icons in the asset catalog."
fi

# ---- 2. xcodegen -----------------------------------------------------------
echo "⚙️  xcodegen"
xcodegen --quiet

# ---- 3. Release build ------------------------------------------------------
echo "🔨 Release build"
EXTRA_BUILD_FLAGS=()
if [[ "$MODE" == "adhoc" ]]; then
    EXTRA_BUILD_FLAGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY=-
        DEVELOPMENT_TEAM=
    )
else
    EXTRA_BUILD_FLAGS=(
        CODE_SIGN_STYLE=Manual
        "CODE_SIGN_IDENTITY=$SIGN_IDENTITY"
        "DEVELOPMENT_TEAM=$TEAM_ID"
        OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp"
    )
fi

xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED" \
    "${EXTRA_BUILD_FLAGS[@]}" \
    build | tail -10

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "❌ Build did not produce $BUILT_APP"
    exit 1
fi

rm -rf "$BUILD_DIR/$APP_NAME"
cp -R "$BUILT_APP" "$BUILD_DIR/$APP_NAME"

# ---- 4. Re-sign the .app with hardened runtime ------------------------------
echo "✍️  Re-signing app"
ENTITLEMENTS="$ROOT/Pode/Pode.entitlements"
if [[ "$MODE" == "adhoc" ]]; then
    codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME"
else
    # Notarization requires:
    #   --options runtime  → Hardened Runtime enabled
    #   --timestamp        → Secure timestamp
    #   --entitlements     → Match what's baked into the binary
    # `--deep` is discouraged (Apple wants per-bundle signing); xcodebuild
    # already signed nested code, and we only re-sign the outer bundle.
    codesign --force \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$BUILD_DIR/$APP_NAME"
fi

codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/$APP_NAME" 2>&1 | tail -3

# ---- 5. Build DMG ----------------------------------------------------------
echo "💿 Building DMG"
STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$BUILD_DIR/$APP_NAME" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$DMG_VOL_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" >/dev/null

# ---- 6. Sign the DMG --------------------------------------------------------
echo "✍️  Signing DMG"
if [[ "$MODE" == "adhoc" ]]; then
    codesign --force --sign - "$DMG_PATH"
else
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi

# ---- 7. Notarize -----------------------------------------------------------
if [[ "$MODE" == "release" ]]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo ""
        echo "⚠️  Notarization profile \"$NOTARY_PROFILE\" not found in keychain."
        echo "   Run ./scripts/notarize-setup.sh once to store credentials,"
        echo "   then re-run this build to notarize."
        echo ""
        echo "   The DMG IS signed with Developer ID, but Gatekeeper will"
        echo "   still warn on first launch until it's notarized + stapled."
        SKIPPED_NOTARIZE=1
    else
        echo "📬 Submitting DMG to Apple for notarization (this can take 1–5 min)…"
        # `--wait` blocks until Apple finishes; we then staple if accepted.
        if xcrun notarytool submit \
            "$DMG_PATH" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait; then
            echo "📌 Stapling ticket to DMG"
            xcrun stapler staple "$DMG_PATH"

            # Also staple the .app inside (so users who run it directly
            # without mounting the DMG still get the offline ticket).
            xcrun stapler staple "$BUILD_DIR/$APP_NAME"

            # Verify Gatekeeper is happy.
            echo "🔎 spctl assessment:"
            spctl --assess --type execute --verbose "$BUILD_DIR/$APP_NAME" 2>&1 || true
            spctl --assess --type install --verbose "$DMG_PATH"            2>&1 || true
        else
            echo "❌ Notarization failed. Pull the log with:"
            echo "    xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
            exit 1
        fi
    fi
fi

# ---- 8. Done ---------------------------------------------------------------
SIZE="$(du -sh "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "✅ Done."
echo "   App: $BUILD_DIR/$APP_NAME"
echo "   DMG: $DMG_PATH  ($SIZE)"
case "$MODE" in
    adhoc)
        echo "   Mode: ad-hoc — fresh Macs need right-click → Open on first launch."
        ;;
    release-no-notarize)
        echo "   Mode: Developer ID, no notarization — Gatekeeper will warn until you notarize."
        ;;
    release)
        if [[ "${SKIPPED_NOTARIZE:-0}" == "1" ]]; then
            echo "   Mode: Developer ID — notarization skipped (set up keychain profile)."
        else
            echo "   Mode: Developer ID + notarized + stapled — fresh Macs open it cleanly."
        fi
        ;;
esac
