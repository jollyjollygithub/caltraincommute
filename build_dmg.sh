#!/usr/bin/env bash
#
# Builds the macOS app and wraps it in a DMG for sharing.
#
#   ./build_dmg.sh              # build, sign with whatever is available
#   ./build_dmg.sh --notarize   # also submit to Apple and staple the ticket
#
# Output lands in dist/Commute-<version>.dmg, where <version> is AppInfo.version
# from Schedule.swift — the string the app shows in its footer.
#
# ── On signing, which decides whether this opens on someone else's Mac ────────
#
# The script signs with the best identity it finds:
#
#   Developer ID Application   Gatekeeper's distribution identity. Combined with
#                              --notarize, the DMG opens by double-click on any
#                              Mac, no warnings. This is the only combination
#                              that "just works" for sharing.
#
#   ad-hoc ("-")               The fallback when no Developer ID certificate is
#                              installed. The app runs, but macOS quarantines
#                              anything downloaded from the internet, so the
#                              recipient must right-click → Open the first time
#                              (see the Read Me the script puts in the DMG).
#
# An "Apple Development" certificate is deliberately NOT used: it embeds a
# provisioning profile tied to specific registered Macs, so an app signed with
# it is *less* portable than an ad-hoc one.
#
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="CaltrainUpcoming.xcodeproj"
SCHEME="CaltrainUpcoming"
APP_NAME="Commute"          # CFBundleDisplayName; the .app on disk is the target name
BUILD_DIR="build/dmg"
DIST_DIR="dist"

NOTARIZE=0
# A notarytool keychain profile, created once with:
#   xcrun notarytool store-credentials caltrain-notary \
#     --apple-id you@example.com --team-id A7SGPP54UA --password <app-specific-password>
NOTARY_PROFILE="${NOTARY_PROFILE:-caltrain-notary}"

for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=1 ;;
        -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# ── Version ──────────────────────────────────────────────────────────────────
# Single source of truth is the constant the app displays, so a DMG can never
# claim a version the app doesn't report.
VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' CaltrainUpcoming/Schedule.swift)
[ -n "$VERSION" ] || { echo "error: couldn't read AppInfo.version from Schedule.swift" >&2; exit 1; }

# ── Pick a signing identity ──────────────────────────────────────────────────
DEV_ID=$(security find-identity -v -p codesigning \
         | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)

if [ -n "$DEV_ID" ]; then
    SIGN_ID="$DEV_ID"
    SIGNED_FOR_DISTRIBUTION=1
    echo "signing with: $SIGN_ID"
else
    SIGN_ID="-"
    SIGNED_FOR_DISTRIBUTION=0
    echo "signing ad-hoc: no Developer ID Application certificate installed"
    if [ "$NOTARIZE" = 1 ]; then
        echo "error: --notarize needs a Developer ID Application certificate." >&2
        echo "       Apple only notarizes Developer ID-signed code." >&2
        exit 1
    fi
fi

# ── Build ────────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"          # also gives the log below somewhere to land
LOG="$BUILD_DIR/xcodebuild.log"
echo "building $SCHEME (Release, macOS)…"
xcodebuild \
    -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    build > "$LOG" 2>&1 \
  || { echo "build failed — see $LOG" >&2; tail -20 "$LOG" >&2; exit 1; }

APP=$(find "$BUILD_DIR/Build/Products/Release" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "error: no .app in build products" >&2; exit 1; }

# Fail loudly rather than shipping a bundle whose signature won't validate.
codesign --verify --deep --strict "$APP"
echo "signature verified: $(basename "$APP")"

# ── Stage the DMG contents ───────────────────────────────────────────────────
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/$APP_NAME.app"
# The customary drop target, so the window reads "drag this onto that".
ln -s /Applications "$STAGE/Applications"

if [ "$SIGNED_FOR_DISTRIBUTION" = 0 ] || [ "$NOTARIZE" = 0 ]; then
    cat > "$STAGE/Read Me First.txt" <<TXT
$APP_NAME $VERSION

Installing
  Drag $APP_NAME onto the Applications folder in this window.

First launch
  This build isn't notarized by Apple, so macOS will refuse a plain
  double-click and say it "cannot be opened because Apple cannot check it
  for malicious software".

  To open it anyway, once:
    1. Find $APP_NAME in your Applications folder.
    2. Right-click (or Control-click) it and choose Open.
    3. Click Open in the dialog.

  macOS remembers the choice, so every launch after that is an ordinary
  double-click. The warning is about the absence of an Apple-issued
  signature, not about anything detected in the app.
TXT
fi

# ── Build the disk image ─────────────────────────────────────────────────────
mkdir -p "$DIST_DIR"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

# hdiutil warns that it's deprecated in favour of `diskutil image create`,
# but that replacement is too new to exist on older macOS or on GitHub's
# runner images, so the portable call stays.
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO -ov \
    "$DMG" > /dev/null
echo "wrote $DMG ($(du -h "$DMG" | cut -f1))"

# A signed DMG lets the recipient's Mac verify the container itself, not just
# the app inside it. Ad-hoc signing a DMG buys nothing, so it's skipped.
if [ "$SIGNED_FOR_DISTRIBUTION" = 1 ]; then
    codesign --sign "$SIGN_ID" --timestamp "$DMG"
    echo "signed the disk image"
fi

# ── Notarize ─────────────────────────────────────────────────────────────────
if [ "$NOTARIZE" = 1 ]; then
    echo "submitting to Apple (this usually takes a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    # Stapling attaches the ticket so the DMG validates without a network round
    # trip on the recipient's Mac.
    xcrun stapler staple "$DMG"
    echo "notarized and stapled"
fi

# ── Report what the recipient will actually see ──────────────────────────────
echo
echo "── $DMG"
if [ "$NOTARIZE" = 1 ]; then
    spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 | sed 's/^/   /' || true
    echo "   Opens by double-click on any Mac."
else
    echo "   NOT notarized. On another Mac, Gatekeeper will block the first"
    echo "   launch; the recipient must right-click → Open once. The DMG"
    echo "   includes a Read Me explaining that."
    echo "   To remove the friction: install a Developer ID Application"
    echo "   certificate, then re-run with --notarize."
fi
