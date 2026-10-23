#!/usr/bin/env bash
# Build, sign, notarize and (optionally) publish a da transcribuh release.
#
#   scripts/release.sh <version> [--skip-notarize] [--publish]
#
# Env: PRERELEASE=0 publishes a full release instead of a prerelease. The Sparkle feed
# (releases/latest/download/appcast.xml) only resolves for a full release; see docs/releasing.md.
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
# Version and build come from project.pbxproj (bump them in the release PR).
PROJECT_VERSION="$(grep -m1 -oE 'MARKETING_VERSION = [^;]+' PromptAnnotator.xcodeproj/project.pbxproj | awk '{print $3}')"
PROJECT_BUILD="$(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' PromptAnnotator.xcodeproj/project.pbxproj | awk '{print $3}')"
BUILD_NUMBER="${BUILD_NUMBER:-$PROJECT_BUILD}"
[[ "$VERSION" == "$PROJECT_VERSION" ]] || echo "warning: building $VERSION but project.pbxproj says $PROJECT_VERSION" >&2
OUT="$ROOT/build/release/$VERSION"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/$APP_NAME.app"
DMG="$OUT/$APP_NAME $VERSION.dmg"          # "da transcribuh 0.9.1.dmg"
DMG_ALIAS="da-transcribuh.dmg"              # URL-safe copy for GitHub (see docs/releasing.md)
DMG_BG="$ROOT/Config/dmg/background.tiff"   # 600x400 + 1200x800, from Config/dmg/render-background.swift
ENTITLEMENTS="$ROOT/Config/Release.entitlements"
PRERELEASE="${PRERELEASE:-1}"
# Sparkle comes in through SwiftPM. Clone packages into build/ so its tools sit at a known path.
SPM_DIR="$ROOT/build/spm"
SPARKLE_BIN="${SPARKLE_BIN:-$SPM_DIR/artifacts/sparkle/Sparkle/bin}"
PLIST_ED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Config/Info.plist 2>/dev/null || true)"

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
# Sparkle: tools present, and the EdDSA key in the login Keychain matches the app's public key.
# generate_keys -p prints only the public key. The private key never leaves the Keychain.
[[ -n "$PLIST_ED_KEY" ]] || die "SUPublicEDKey missing from Config/Info.plist"
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  mkdir -p "$SPM_DIR"
  xcodebuild -resolvePackageDependencies -project PromptAnnotator.xcodeproj -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$SPM_DIR" > "$ROOT/build/spm-resolve.log" 2>&1 \
    || die "package resolve failed (log: $ROOT/build/spm-resolve.log)"
fi
for tool in generate_keys generate_appcast sign_update; do
  [[ -x "$SPARKLE_BIN/$tool" ]] || die "Sparkle tool missing: $SPARKLE_BIN/$tool"
done
KEYCHAIN_ED_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
[[ -n "$KEYCHAIN_ED_KEY" ]] || die "no Sparkle EdDSA key in the login Keychain (see docs/releasing.md, Sparkle key)"
[[ "$KEYCHAIN_ED_KEY" == "$PLIST_ED_KEY" ]] || die "Keychain EdDSA key does not match SUPublicEDKey in Config/Info.plist"
[[ -f "$DMG_BG" ]] || die "missing $DMG_BG (run: swift Config/dmg/render-background.swift Config/dmg)"
[[ ! -d "/Volumes/$APP_NAME" ]] || die "/Volumes/$APP_NAME is mounted; eject it first"
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
  -clonedSourcePackagesDirPath "$SPM_DIR" \
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
# Sparkle ships nested helpers (Autoupdate, Updater.app, XPC services). Each must carry our
# Developer ID signature with a timestamp, or notarization rejects the app.
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$SPARKLE_FW" ]] || die "Sparkle.framework not embedded"
for nested in "$SPARKLE_FW" "$SPARKLE_FW/Versions/B/Autoupdate" "$SPARKLE_FW/Versions/B/Updater.app" \
  "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"; do
  [[ -e "$nested" ]] || continue
  NSIG="$(codesign -dv --verbose=4 "$nested" 2>&1)"
  grep -qx "TeamIdentifier=$TEAM_ID" <<<"$NSIG" || die "$nested is not signed by team $TEAM_ID"
  grep -q 'Timestamp=' <<<"$NSIG" || die "$nested has no secure timestamp"
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" == "$PLIST_ED_KEY" ]] \
  || die "exported app carries a different SUPublicEDKey"
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

# ---- 4b. DMG: drag-to-install window ----
# 600x400 window, no toolbar or status bar, 128pt icons. The app sits on the left card
# of the background, an /Applications link on the right. Finder lays it out once while
# the image is writable, so a Finder window opens briefly during this step.
WIN_W=600; WIN_H=400; ICON=128; APP_X=150; APPS_X=450; ICON_Y=190

dmg_with_create_dmg() {
  create-dmg \
    --volname "$APP_NAME" \
    --background "$DMG_BG" \
    --window-pos 200 120 --window-size "$WIN_W" "$WIN_H" \
    --icon-size "$ICON" --text-size 12 \
    --icon "$APP_NAME.app" "$APP_X" "$ICON_Y" --hide-extension "$APP_NAME.app" \
    --app-drop-link "$APPS_X" "$ICON_Y" \
    --filesystem HFS+ --format UDZO --hdiutil-quiet \
    "$DMG" "$STAGE"
}

dmg_with_hdiutil() {
  local rw="$OUT/rw.dmg" dev mnt
  mkdir -p "$STAGE/.background"
  cp "$DMG_BG" "$STAGE/.background/background.tiff"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$rw" >/dev/null
  dev="$(hdiutil attach -readwrite -noverify -noautoopen "$rw" | awk '/Apple_HFS/ {print $1}')"
  mnt="/Volumes/$APP_NAME"
  osascript <<OSA
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON
    set text size of opts to 12
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
  SetFile -a V "$mnt/.background" 2>/dev/null || true
  sync
  hdiutil detach "$dev" -quiet || hdiutil detach "$dev" -force -quiet
  hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
  rm -f "$rw"
}

step "build DMG"
STAGE="$OUT/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
rm -f "$DMG"
if command -v create-dmg >/dev/null; then
  echo "using $(create-dmg --version)"
  dmg_with_create_dmg
else
  echo "create-dmg not found; using hdiutil + Finder AppleScript"
  dmg_with_hdiutil
fi
rm -rf "$STAGE"
[[ -f "$DMG" ]] || die "DMG was not created"

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

# ---- 7b. Sparkle appcast (EdDSA-signed enclosure + signed feed) ----
# Signs with the Keychain key. The first run may raise a Keychain prompt for
# generate_appcast / sign_update; see docs/releasing.md.
step "appcast"
SPARKLE_BIN="$SPARKLE_BIN" scripts/make-appcast.sh "$DMG" "$VERSION" "$OUT"

# ---- 8. publish ----
if (( PUBLISH == 1 )); then
  step "publish GitHub release v$VERSION"
  # GitHub turns spaces in asset names into dots, so the proper-named DMG shows up as
  # "da.transcribuh.<version>.dmg". The URL-safe alias keeps a stable
  # releases/latest/download/da-transcribuh.dmg link for the README.
  # appcast.xml rides along so releases/latest/download/appcast.xml (SUFeedURL) finds it.
  cp "$DMG" "$OUT/$DMG_ALIAS"
  PRE_FLAG=(); (( PRERELEASE == 1 )) && PRE_FLAG=(--prerelease)
  gh release create "v$VERSION" -R "$REPO" \
    --title "da transcribuh $VERSION beta" --generate-notes ${PRE_FLAG[@]+"${PRE_FLAG[@]}"} --target "$(git rev-parse HEAD)" \
    "$DMG" "$OUT/$DMG_ALIAS" "$OUT/appcast.xml"
fi

# ---- 9. leave no second app on disk ----
# The archive and export each hold a full .app. Spotlight and LaunchServices would offer
# them next to /Applications, so keep the archive as a zip (dSYMs included) and drop both.
step "tidy app copies"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
ditto -c -k --keepParent "$ARCHIVE" "$OUT/$APP_NAME $VERSION.xcarchive.zip"
for copy in "$APP" "$ARCHIVE/Products/Applications/$APP_NAME.app"; do
  [[ -d "$copy" ]] && { "$LSREGISTER" -u "$copy" 2>/dev/null || true; }
done
rm -rf "$EXPORT" "$ARCHIVE"

step "done"
shasum -a 256 "$DMG"
echo "$DMG"
