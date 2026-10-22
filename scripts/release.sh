#!/usr/bin/env bash
# Build, sign, notarize and (optionally) publish a da transcribuh release.
#
#   scripts/release.sh <version> [--skip-notarize] [--publish]
#
# See docs/releasing.md for one-time setup.
set -euo pipefail

TEAM_ID="3BUPEZ2FJQ"
IDENTITY="Developer ID Application: Patrick Brown (${TEAM_ID})"
NOTARY_PROFILE="${NOTARY_PROFILE:-dt-notary}"
SCHEME="PromptAnnotator"
APP_NAME="da transcribuh"
REPO="bicrick/da-transcribuh"

usage() { echo "usage: scripts/release.sh <version> [--skip-notarize] [--publish]" >&2; exit 64; }
die() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

VERSION=""
SKIP_NOTARIZE=0
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) usage ;;
    -*) echo "unknown flag: $arg" >&2; usage ;;
    *) [[ -z "$VERSION" ]] || usage; VERSION="$arg" ;;
  esac
done
[[ -n "$VERSION" ]] || usage
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([-.][0-9A-Za-z.]+)?$ ]] || die "version '$VERSION' should look like 1.0.0"
(( PUBLISH == 0 || SKIP_NOTARIZE == 0 )) || die "--publish needs notarization; drop --skip-notarize"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
OUT="$ROOT/build/release/$VERSION"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/$APP_NAME.app"
DMG="$OUT/da-transcribuh-$VERSION.dmg"
ENTITLEMENTS="$ROOT/Config/Release.entitlements"

# ---- preflight: fail before the slow build, not after ----
step "preflight"
# (capture first: with pipefail, `cmd | grep -q` can fail on SIGPIPE even when it matches)
IDENTITIES="$(security find-identity -v -p codesigning)"
grep -qF "$IDENTITY" <<<"$IDENTITIES" || die "signing identity not in keychain: $IDENTITY"
if (( SKIP_NOTARIZE == 0 )); then
  # notarytool exits 0 even when the profile is missing (it prints "Error: No Keychain
  # password item found"), so require real JSON history back instead of trusting $?.
  NOTARY_CHECK="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json 2>&1 || true)"
  if ! grep -q '"history"' <<<"$NOTARY_CHECK"; then
    cat >&2 <<MSG
error: notary keychain profile "$NOTARY_PROFILE" not found (or its credentials are rejected).
Store it once (it prompts for an app-specific password from https://account.apple.com):

  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "<your Apple ID email>" --team-id "$TEAM_ID"

Or rerun with --skip-notarize to stop after signing + DMG.
MSG
    exit 1
  fi
fi
if (( PUBLISH == 1 )); then
  command -v gh >/dev/null || die "gh not installed (brew install gh)"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in; run: gh auth login"
  gh release view "v$VERSION" -R "$REPO" >/dev/null 2>&1 && die "release v$VERSION already exists"
fi
echo "version $VERSION (build $BUILD_NUMBER), identity: $IDENTITY"
rm -rf "$OUT"; mkdir -p "$OUT"

# ---- 1. archive ----
step "archive (Release, Developer ID, hardened runtime)"
xcodebuild archive \
  -project PromptAnnotator.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -xcconfig Config/Release.xcconfig \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  > "$OUT/archive.log" 2>&1 \
  || { tail -40 "$OUT/archive.log" >&2; die "archive failed (full log: $OUT/archive.log)"; }

# ---- 2. export ----
step "export (developer-id)"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist Config/ExportOptions.plist \
  > "$OUT/export.log" 2>&1 \
  || { tail -40 "$OUT/export.log" >&2; die "export failed (full log: $OUT/export.log)"; }
[[ -d "$APP" ]] || die "export did not produce $APP"

# ---- 3. verify ----
step "verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
SIG="$(codesign -dv --verbose=4 "$APP" 2>&1)"
grep -E '^(Identifier|Format|CodeDirectory|Authority|Timestamp|TeamIdentifier|Runtime Version)=' <<<"$SIG"
grep -q 'flags=0x10000(runtime)' <<<"$SIG" || die "hardened runtime flag missing"
grep -qx "TeamIdentifier=$TEAM_ID" <<<"$SIG" || die "wrong team identifier"
grep -q 'Timestamp=' <<<"$SIG" || die "no secure timestamp"
ENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
grep -q 'com.apple.security.device.audio-input' <<<"$ENTS" || die "audio-input entitlement missing"
grep -q 'get-task-allow' <<<"$ENTS" && die "get-task-allow present; notarization would reject it"
echo "spctl (before notarization this says 'Unnotarized Developer ID'; that's expected):"
spctl -a -vvv -t exec "$APP" 2>&1 || true

notarize() { # <file>
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$OUT/notary.json" \
    || true
  local status id
  status="$(plutil -extract status raw -o - "$OUT/notary.json" 2>/dev/null || echo unknown)"
  id="$(plutil -extract id raw -o - "$OUT/notary.json" 2>/dev/null || echo '?')"
  echo "notary: $status (submission $id)"
  if [[ "$status" != "Accepted" ]]; then
    [[ "$id" != "?" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || cat "$OUT/notary.json" >&2
    die "notarization failed for $1"
  fi
}

# ---- 4a. notarize + staple the app itself (so the copy inside the DMG carries its ticket) ----
if (( SKIP_NOTARIZE == 0 )); then
  step "notarize app"
  ditto -c -k --keepParent "$APP" "$OUT/app.zip"
  notarize "$OUT/app.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vvv -t exec "$APP"
fi

# ---- 4b. DMG ----
step "build DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

# ---- 5. sign DMG ----
step "sign DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict --verbose=2 "$DMG"

# ---- 6/7. notarize + staple DMG ----
if (( SKIP_NOTARIZE == 0 )); then
  step "notarize DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vvv -t open --context context:primary-signature "$DMG"
else
  echo "skipped notarization (--skip-notarize): this DMG will be blocked by Gatekeeper on other Macs"
fi

# ---- 8. publish ----
if (( PUBLISH == 1 )); then
  step "publish GitHub release v$VERSION"
  # README links to releases/latest and da-transcribuh.dmg, so attach an unversioned copy too.
  cp "$DMG" "$OUT/da-transcribuh.dmg"
  gh release create "v$VERSION" -R "$REPO" \
    --title "da transcribuh $VERSION" --generate-notes --target "$(git rev-parse HEAD)" \
    "$DMG" "$OUT/da-transcribuh.dmg"
fi

step "done"
shasum -a 256 "$DMG"
echo "$DMG"
