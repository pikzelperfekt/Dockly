#!/bin/bash
# Cut a new Dockly release: bump version, build (universal + Sparkle), zip,
# and regenerate the signed appcast for GitHub Releases.
#
#   ./release.sh <version> <github-user>
#   e.g. ./release.sh 1.1 josi
#
# Optional env:
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)"  → real signing
#   NOTARY_PROFILE="dockly"   → notarize via `xcrun notarytool ... --keychain-profile`
set -e
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version> <github-user>}"
GH_USER="${2:?usage: ./release.sh <version> <github-user>}"
REL="dist/releases"

echo "▶ Bumping version → $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Info.plist

# Build the signed, universal app (build-app.sh honors CODESIGN_IDENTITY).
./build-app.sh release

# Optional: notarize so updates install with zero Gatekeeper friction.
if [ -n "$NOTARY_PROFILE" ]; then
    echo "▶ Notarizing…"
    TMPZIP="$(mktemp -d)/Dockly-notarize.zip"
    ditto -c -k --keepParent "dist/Dockly.app" "$TMPZIP"
    xcrun notarytool submit "$TMPZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "dist/Dockly.app"
fi

# Zip the app for distribution (ditto preserves symlinks + signatures).
mkdir -p "$REL"
rm -f "$REL/Dockly.zip"
ditto -c -k --keepParent "dist/Dockly.app" "$REL/Dockly.zip"

# Generate the signed appcast (reads the EdDSA private key from your Keychain).
GENAPPCAST="$(find .build/artifacts/sparkle/Sparkle/bin -name generate_appcast | head -1)"
"$GENAPPCAST" --download-url-prefix "https://github.com/$GH_USER/Dockly/releases/latest/download/" "$REL"

echo ""
echo "✅ Release $VERSION ready in $REL"
echo "   • Dockly.zip"
echo "   • appcast.xml"
echo ""
echo "Publish on GitHub:"
echo "   1. Create a release tagged v$VERSION"
echo "   2. Upload BOTH $REL/Dockly.zip and $REL/appcast.xml as assets"
echo "   Installed apps will see it via SUFeedURL (.../releases/latest/download/appcast.xml)."
