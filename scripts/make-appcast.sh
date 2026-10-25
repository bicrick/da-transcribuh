#!/usr/bin/env bash
# Write a signed Sparkle appcast for one release DMG.
#
#   scripts/make-appcast.sh <dmg> <version> <out-dir>
#
# Called by scripts/release.sh after the DMG is notarized and stapled. Writes
# <out-dir>/appcast.xml with an EdDSA-signed enclosure and a signed feed.
#
# The EdDSA private key is read from the login Keychain (generate_keys, account
# "ed25519") by Sparkle's own tools. This script never reads, prints or copies it.
# The first run of generate_appcast / sign_update may show a Keychain prompt;
# see docs/releasing.md.
#
# Env:
#   SPARKLE_BIN    Sparkle's bin/ dir (generate_appcast, sign_update, generate_keys).
#   ED_KEY_FILE    Only for dry runs with a throwaway key. Never point this at the real key.
#   EXPECT_ED_KEY  Public key the feed must verify against (default: SUPublicEDKey in Config/Info.plist).
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
[[ $# -eq 3 ]] || die "usage: scripts/make-appcast.sh <dmg> <version> <out-dir>"
DMG="$1"; VERSION="$2"; OUT="$3"
REPO="bicrick/da-transcribuh"
# The feed and DMGs are served by the public website (bicrick/da-transcribuh-site), so
# updates work while this repo stays private. The site hosts each DMG at
# /download/da-transcribuh-<version>.dmg and the feed at /appcast.xml (SUFeedURL).
SITE="${SITE_URL:-https://da-transcribuh-site.vercel.app}"
DMG_ALIAS="${ASSET_NAME:-da-transcribuh-$VERSION.dmg}"   # file name the enclosure URL points at (ASSET_NAME only for dry runs)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="${SPARKLE_BIN:?set SPARKLE_BIN to the Sparkle bin directory}"
[[ -f "$DMG" ]] || die "no DMG at $DMG"
for tool in generate_appcast sign_update; do
  [[ -x "$SPARKLE_BIN/$tool" ]] || die "missing $SPARKLE_BIN/$tool"
done

KEY_ARGS=()
if [[ -n "${ED_KEY_FILE:-}" ]]; then
  KEY_ARGS=(--ed-key-file "$ED_KEY_FILE")
  echo "appcast: dry run with throwaway key file (not the Keychain key)"
fi
EXPECT_ED_KEY="${EXPECT_ED_KEY:-$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Config/Info.plist")}"

# generate_appcast reads every archive in a folder and writes into it, so give it a
# folder holding only this release, under the file name the site will serve.
STAGE="$OUT/appcast-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$DMG" "$STAGE/$DMG_ALIAS"

"$SPARKLE_BIN/generate_appcast" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
  --download-url-prefix "$SITE/download/" \
  --link "https://github.com/$REPO" \
  --maximum-versions 1 \
  -o "$OUT/appcast.xml" \
  "$STAGE"
rm -rf "$STAGE"
[[ -f "$OUT/appcast.xml" ]] || die "generate_appcast wrote no appcast.xml"

# The enclosure must carry an EdDSA signature (SUVerifyUpdateBeforeExtraction checks it).
grep -q 'sparkle:edSignature=' "$OUT/appcast.xml" || die "appcast enclosure has no sparkle:edSignature"
grep -q "url=\"$SITE/download/$DMG_ALIAS\"" "$OUT/appcast.xml" || die "enclosure URL is not $SITE/download/$DMG_ALIAS"

# The feed itself must be signed (Info.plist sets SURequireSignedFeed). generate_appcast
# signs it when the app requires that; sign it here if it didn't.
if ! grep -q 'sparkle-signatures:' "$OUT/appcast.xml"; then
  "$SPARKLE_BIN/sign_update" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} "$OUT/appcast.xml"
fi
grep -q 'sparkle-signatures:' "$OUT/appcast.xml" || die "appcast feed is not signed"

# Verify against the public key the app ships with, not whatever key signed it.
# A key-file dry run checks against its own key instead.
if [[ -z "${ED_KEY_FILE:-}" ]]; then
  "$SPARKLE_BIN/generate_keys" -p | grep -qxF "$EXPECT_ED_KEY" \
    || die "Keychain key does not match SUPublicEDKey in Config/Info.plist"
fi
"$SPARKLE_BIN/sign_update" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} --verify "$OUT/appcast.xml" || die "appcast signature does not verify"
echo "appcast: $OUT/appcast.xml (signed, verified)"
