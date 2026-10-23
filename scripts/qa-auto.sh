#!/bin/zsh
# Read-only launch checks for an installed build. Changes nothing, opens no windows.
# usage: scripts/qa-auto.sh [path-to-app]   (default /Applications/da transcribuh.app)
APP="${1:-/Applications/da transcribuh.app}"
BID=com.bicrick.PromptAnnotator TEAM=3BUPEZ2FJQ
ROOT="${0:A:h:h}"
pass=0 fail=0 warn=0
ok()   { print "PASS  $1"; ((pass++)); : }
bad()  { print "FAIL  $1"; ((fail++)); : }
note() { print "WARN  $1"; ((warn++)); : }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi }

[[ -d "$APP" ]] || { print "FAIL  no app at $APP"; exit 1 }
PL="$APP/Contents/Info.plist"
v=$(defaults read "$PL" CFBundleShortVersionString) b=$(defaults read "$PL" CFBundleVersion)
print "INFO  $APP  version $v ($b)"
[[ $(defaults read "$PL" CFBundleIdentifier) == $BID ]] && ok "bundle id $BID" || bad "bundle id"

check "codesign --verify --deep --strict" "codesign --verify --deep --strict '$APP'"
sig=$(codesign -dvv "$APP" 2>&1)
[[ $sig == *"Authority=Developer ID Application"* && $sig == *"TeamIdentifier=$TEAM"* ]] && ok "Developer ID signed, team $TEAM" || bad "not Developer ID / wrong team"
[[ $sig == *"(runtime)"* ]] && ok "hardened runtime" || bad "hardened runtime missing"
[[ $sig == *"Timestamp="* ]] && ok "secure timestamp" || bad "no secure timestamp"
ent=$(codesign -d --entitlements :- "$APP" 2>/dev/null)
[[ $ent == *"com.apple.security.device.audio-input"* ]] && ok "audio-input entitlement" || bad "audio-input entitlement missing"
[[ $ent == *"get-task-allow"* ]] && bad "get-task-allow present (debug entitlement)" || ok "no get-task-allow"
notarized=0
gk=$(spctl -a -vvv -t exec "$APP" 2>&1)
if [[ $gk == *"Notarized Developer ID"* ]]; then ok "Gatekeeper: notarized"; notarized=1
elif [[ $gk == *accepted* ]]; then note "Gatekeeper accepts but not notarized (dev install is expected)"
else note "Gatekeeper rejects (expected for an un-notarized dev install): ${gk//$'\n'/ }"; fi

# Sparkle
SP="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d $SP ]] && ok "Sparkle.framework embedded" || bad "Sparkle.framework missing"
for h in Versions/B/Autoupdate Versions/B/Updater.app Versions/B/XPCServices/Downloader.xpc Versions/B/XPCServices/Installer.xpc; do
  t=$(codesign -dvv "$SP/$h" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  if [[ $t == $TEAM ]]; then ok "Sparkle ${h:t} team $TEAM"
  elif ((notarized)); then bad "Sparkle ${h:t} team '$t'"
  else note "Sparkle ${h:t} team '$t' (xcodebuild dev builds leave helpers ad hoc; release.sh re-signs and checks)"; fi
done
key=$(defaults read "$PL" SUPublicEDKey 2>/dev/null)
src=$(plutil -extract SUPublicEDKey raw "$ROOT/Config/Info.plist" 2>/dev/null)
[[ -n $key && $key == $src ]] && ok "SUPublicEDKey matches Config/Info.plist" || bad "SUPublicEDKey mismatch or missing"
[[ $(defaults read "$PL" SURequireSignedFeed) == 1 ]] && ok "SURequireSignedFeed on" || bad "SURequireSignedFeed off"
[[ $(defaults read "$PL" SUEnableAutomaticChecks) == 0 ]] && ok "no automatic update checks" || note "automatic update checks on"
feed=$(defaults read "$PL" SUFeedURL)
code=$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 10 "$feed")
if [[ $code == 200 ]]; then ok "feed reachable ($feed)"; else note "feed HTTP $code ($feed); expected 404 while the repo is private"; fi

# Install hygiene
copies=$(mdfind "kMDItemCFBundleIdentifier == '$BID'" | grep -v '/Desktop/' | wc -l | tr -d ' ')
[[ $copies == 1 ]] && ok "one indexed copy outside Desktop" || note "$copies indexed copies of $BID outside Desktop"
pgrep -f "$APP/Contents/MacOS/" >/dev/null && ok "app is running" || note "app is not running"

# Stuck modifiers (a synthetic paste must not leave ⌘/⌥/⌃/⇧ reported as held)
flags=$(swift -e 'import CoreGraphics; print(CGEventSource.flagsState(.hidSystemState).rawValue & 0x1E0000)' 2>/dev/null)
if [[ -z $flags ]]; then note "could not read modifier state (swift unavailable)"
elif [[ $flags == 0 ]]; then ok "no modifier reported held"
else bad "modifier reported held (mask $(printf %x $flags)); press and release ⌘ to clear, then rerun"; fi

print "\n$pass passed, $fail failed, $warn warnings"
((fail == 0))
