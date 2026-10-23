#!/usr/bin/env bash
# Build a Developer ID-signed dev copy of da transcribuh and install it as THE
# single copy at /Applications/da transcribuh.app.
#
# Why Developer ID: TCC (Accessibility, Microphone, Input Monitoring) ties grants
# to the bundle ID plus the signing requirement. Releases are signed with
# "Developer ID Application: Patrick Brown (3BUPEZ2FJQ)", so a dev build signed the
# same way with the same bundle ID (com.bicrick.PromptAnnotator) keeps the grants.
# Never install a "Prompt Annotator Local" build into /Applications. This script
# never runs tccutil reset.
#
# Usage:
#   scripts/install-dev.sh              # build latest origin/main (fetches first)
#   scripts/install-dev.sh <git-ref>    # build a branch, tag or sha (e.g. origin/release/0.9.2)
#   scripts/install-dev.sh --here       # build the current working tree, uncommitted changes included
#   scripts/install-dev.sh --no-launch  # any of the above, without relaunching afterwards
#
# The installed CFBundleShortVersionString is "<MARKETING_VERSION>-dev+<shortsha>"
# (plus ".dirty" for --here with local changes), shown in Settings > General.
set -euo pipefail

TEAM_ID="3BUPEZ2FJQ"
IDENTITY="Developer ID Application: Patrick Brown (${TEAM_ID})"
BUNDLE_ID="com.bicrick.PromptAnnotator"
SCHEME="PromptAnnotator"
APP_NAME="da transcribuh"
DEST="/Applications/${APP_NAME}.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="${DT_DEV_DERIVED_DATA:-$HOME/Library/Caches/dt-install-dev/DerivedData}"
WORK="$HOME/Library/Caches/dt-install-dev/src"

die()  { echo "install-dev: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

REF="origin/main"; HERE=0; LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --here) HERE=1 ;;
    --no-launch) LAUNCH=0 ;;
    -h|--help) sed -n 2,20p "$0"; exit 0 ;;
    -*) die "unknown flag $arg" ;;
    *) REF="$arg" ;;
  esac
done

security find-identity -v -p codesigning | grep -qF "$IDENTITY" || die "signing identity not in keychain: $IDENTITY"

# ---- 1. source ----
cd "$ROOT"
if (( HERE == 1 )); then
  SRC="$ROOT"
  SHA="$(git rev-parse --short HEAD)"
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || SHA="$SHA.dirty"
else
  step "checkout $REF (detached worktree, your checkout is untouched)"
  git fetch -q origin
  git worktree remove --force "$WORK" >/dev/null 2>&1 || rm -rf "$WORK"
  git worktree prune
  git worktree add -q --detach "$WORK" "$REF"
  SRC="$WORK"
  SHA="$(git -C "$WORK" rev-parse --short HEAD)"
fi
cleanup() {
  if [[ "$SRC" == "$WORK" ]]; then git -C "$ROOT" worktree remove --force "$WORK" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

BASE_VERSION="$(grep -m1 'MARKETING_VERSION = ' "$SRC/PromptAnnotator.xcodeproj/project.pbxproj" | sed -E 's/.*= *"?([^";]+)"?;.*/\1/')"
DEV_VERSION="${BASE_VERSION}-dev+${SHA}"

# ---- 2. build (Release config, Developer ID, hardened runtime) ----
step "build $DEV_VERSION"
xcodebuild build \
  -project "$SRC/PromptAnnotator.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DD" \
  -xcconfig "$SRC/Config/Release.xcconfig" \
  CODE_SIGN_ENTITLEMENTS="$SRC/Config/Release.entitlements" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  MARKETING_VERSION="$DEV_VERSION" \
  -quiet
BUILT="$DD/Build/Products/Release/${APP_NAME}.app"
[[ -d "$BUILT" ]] || die "build product missing: $BUILT"

# ---- 3. verify signature before touching /Applications ----
step "verify signature"
codesign --verify --deep --strict "$BUILT" || die "codesign verify failed"
SIG="$(codesign -dv --verbose=4 "$BUILT" 2>&1)"
grep -qF "Authority=$IDENTITY" <<<"$SIG" || die "not signed with $IDENTITY"
grep -qx "TeamIdentifier=$TEAM_ID" <<<"$SIG" || die "wrong team identifier"
grep -qx "Identifier=$BUNDLE_ID" <<<"$SIG" || die "wrong bundle identifier"

# ---- 4. quit the running app ----
step "quit running app"
if pgrep -f "/${APP_NAME}.app/Contents/MacOS/" >/dev/null; then
  osascript -e "with timeout of 10 seconds" -e "tell application id \"$BUNDLE_ID\" to quit" -e "end timeout" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do pgrep -f "/${APP_NAME}.app/Contents/MacOS/" >/dev/null || break; sleep 0.2; done
  pkill -f "/${APP_NAME}.app/Contents/MacOS/" 2>/dev/null || true
  sleep 0.5
fi

# ---- 5. replace the single copy in /Applications ----
step "install to $DEST"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
"$LSREGISTER" -f "$DEST"

# Drop the build product so Spotlight / LaunchServices see exactly one copy.
"$LSREGISTER" -u "$BUILT" >/dev/null 2>&1 || true
rm -rf "$BUILT"

echo "installed $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString) (build $(defaults read "$DEST/Contents/Info" CFBundleVersion))"

# ---- 6. relaunch ----
if (( LAUNCH == 1 )); then
  step "launch"
  open "$DEST"
fi
