#!/usr/bin/env bash
# One-time interactive setup for notarization credentials.
#
# Stores an App Store Connect-style profile in the user's keychain so the
# build-dmg.sh script can call `notarytool submit --keychain-profile pode-notary`
# without prompting every time.
#
# What you'll need:
#   - Your Apple ID email (the one tied to the developer account)
#   - An app-specific password — generate at:
#         https://appleid.apple.com → Sign-In & Security → App-Specific Passwords
#     (Apple-ID password itself doesn't work for notarization.)
#   - Your team ID (the 10-char string like "UK68KKX58X")

set -euo pipefail

PROFILE_NAME="pode-notary"

cat <<EOF
🔐 One-time notarization setup

This will prompt for your Apple ID, an app-specific password, and your
Team ID, then store them in your login keychain under the profile name
"$PROFILE_NAME". Subsequent dmg builds will reuse the stored credentials.

Generate an app-specific password first:
  https://appleid.apple.com → Sign-in & Security → App-Specific Passwords

EOF

if xcrun notarytool history --keychain-profile "$PROFILE_NAME" >/dev/null 2>&1; then
    echo "✅ Profile \"$PROFILE_NAME\" already exists. Re-run will overwrite it."
    echo ""
fi

xcrun notarytool store-credentials "$PROFILE_NAME"

echo ""
echo "✅ Done. Credentials stored under \"$PROFILE_NAME\"."
echo "   Run ./scripts/build-dmg.sh to build + sign + notarize."
