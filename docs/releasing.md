# releasing

releases are Developer ID signed, notarized and stapled, then shipped as a DMG on GitHub releases.
everything runs from `scripts/release.sh` on a Mac with Xcode 16+.

## one-time setup

1. **signing cert.** the login keychain needs `Developer ID Application: Patrick Brown (3BUPEZ2FJQ)`
   (with its private key). check with:

   ```sh
   security find-identity -v -p codesigning
   ```

2. **notary credentials.** make an app-specific password at <https://account.apple.com>
   (Sign-In and Security → App-Specific Passwords), then store it in the keychain as profile `dt-notary`:

   ```sh
   xcrun notarytool store-credentials "dt-notary" --apple-id "<your Apple ID email>" --team-id "3BUPEZ2FJQ"
   ```

   it prompts for the password, so nothing ends up in shell history or the repo.
   use a different profile name by exporting `NOTARY_PROFILE`.

3. **gh** (only for `--publish`): `brew install gh && gh auth login`.

4. **Sparkle EdDSA key.** already done on Patrick's Mac (Oct 23, 2026). the private key lives only in the
   login keychain (item `https://sparkle-project.org`, account `ed25519`). the public half is
   `SUPublicEDKey` in `Config/Info.plist`. to check the pair still matches:

   ```sh
   build/spm/artifacts/sparkle/Sparkle/bin/generate_keys -p   # prints the public key only
   ```

   never run `generate_keys -x` (it exports the private key to a file), and never paste the key anywhere.
   back it up with the login keychain itself (Time Machine, or Keychain Access export to an encrypted
   location you control). if it is lost, already-installed copies can no longer accept updates; they would
   need a manual reinstall of a build carrying a new `SUPublicEDKey`.
   on a new Mac with no key, `generate_keys` (no flags) makes one and prints only the public key.

## cut a release

```sh
scripts/release.sh 1.0.0              # archive → export → verify → notarize app → DMG → sign → notarize DMG → staple
scripts/release.sh 1.0.0 --publish    # same, then create GitHub release v1.0.0 with the DMG
scripts/release.sh 1.0.0 --skip-notarize   # local dry run: stops after signing + DMG (Gatekeeper will block it elsewhere)
```

output lands in `build/release/<version>/` (gitignored):

- `da transcribuh <version>.dmg`: volume `da transcribuh`, holding `da transcribuh.app` and an `Applications` link
- `da transcribuh <version>.xcarchive.zip` (dSYMs), `app.zip` (what was notarized), logs and `notary.json`

the script deletes the exported `.app` and the `.xcarchive` at the end, so Spotlight and LaunchServices
only ever see the copy in `/Applications`.

- bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj` in the release PR. the script
  builds the version you pass (it warns if that differs from the project) with the project's build number
  (override with `BUILD_NUMBER=...`). the app shows them as `<version> beta (<build>)` (`AppVersion.channel`).
- `--publish` creates a prerelease and uploads two copies of the same DMG. GitHub replaces spaces in asset
  names with dots, so `da transcribuh <version>.dmg` appears as `da.transcribuh.<version>.dmg`.
  the URL-safe alias `da-transcribuh.dmg` keeps the README's `releases/latest/download/da-transcribuh.dmg`
  link stable. it is the only reason the alias exists.

## the DMG window

opening the DMG shows a 600x400 Finder window with no toolbar or status bar and 128pt icons:
the app on the left card, `Applications` on the right, and "drag me into Applications" with a
pixel arrow in Departure Mono on the Ink paper background.

- background: `Config/dmg/background.tiff` (600x400 and 1200x800 in one file, for Retina). regenerate with

  ```sh
  swift Config/dmg/render-background.swift Config/dmg
  (cd Config/dmg && tiffutil -cathidpicheck background.png background@2x.png -out background.tiff)
  ```

  if you move icons, keep the positions in `render-background.swift` and `scripts/release.sh` in sync.
- layout: `create-dmg` when it is installed (`brew install create-dmg`). otherwise the script falls back
  to `hdiutil` plus a Finder AppleScript doing the same thing. either way Finder opens the image once
  while it is writable, so a Finder window flashes during the build, and the first run may ask to let
  the terminal control Finder.

## how signing is wired

`project.pbxproj` keeps local-dev signing (`Prompt Annotator Local`, no hardened runtime) so day-to-day
builds and in-flight PRs aren't affected. the script layers release signing on top:

- `Config/Release.xcconfig`: Developer ID identity, team `3BUPEZ2FJQ`, hardened runtime, `--timestamp`,
  no injected `get-task-allow`
- `Config/Release.entitlements`: hardened-runtime entitlements (just `com.apple.security.device.audio-input`)
- `Config/ExportOptions.plist`: `developer-id` export, manual signing

### why only audio-input

hardened runtime blocks the mic without `com.apple.security.device.audio-input`. nothing else needs an entitlement:

- **accessibility paste + Carbon hotkeys**: TCC permission prompts, not entitlements (app isn't sandboxed)
- **screen capture**: TCC (Screen Recording), not an entitlement
- **WhisperKit**: runs CoreML models (`.mlmodelc` data, not code), so no JIT, unsigned-memory or
  library-validation exceptions. the app has no AppleScript/Apple Events, `dlopen` or JavaScriptCore use.
- **model downloads**: plain network access, which non-sandboxed apps have by default

if a new feature needs another entitlement, add it to `Config/Release.entitlements` and note why here.

## checks the script enforces

- `codesign --verify --deep --strict` passes, the runtime flag (`0x10000`) is set, team is `3BUPEZ2FJQ`, a secure timestamp is present
- the signed entitlements include audio-input and do **not** include `get-task-allow` (notarization rejects it)
- after notarizing: `stapler validate` and `spctl -a -vvv` report `source=Notarized Developer ID` for the app and the DMG
- preflight: the keychain EdDSA key (`generate_keys -p`) equals `SUPublicEDKey` in `Config/Info.plist`
- `Sparkle.framework` is embedded, and it and its helpers (Autoupdate, Updater.app, Downloader.xpc,
  Installer.xpc) carry team `3BUPEZ2FJQ` with a secure timestamp. the exported app carries the same `SUPublicEDKey`
- `appcast.xml` has an `sparkle:edSignature` on the enclosure, a signed feed, and passes `sign_update --verify`

## auto-updates (Sparkle 2)

the app embeds Sparkle 2.10.0 (SwiftPM, exact version). `UpdateController` owns one
`SPUStandardUpdaterController`. it never starts under unit tests. "Check for Updates…" sits in the
menu bar menu and on General → Updates.

**what ships now (beta, private repo):**

| Info.plist key | value | why |
|---|---|---|
| `SUFeedURL` | `https://da-transcribuh-site.vercel.app/appcast.xml` | public, served by the website repo. keep this URL even after a custom domain is added |
| `SUPublicEDKey` | public EdDSA key | verifies every update and the feed |
| `SUEnableAutomaticChecks` | `false` | no background checks, and no first-launch permission prompt |
| `SUAutomaticallyUpdate` | `false` | never installs without asking |
| `SURequireSignedFeed` | `true` | rejects an appcast that is not signed by our key |
| `SUVerifyUpdateBeforeExtraction` | `true` | checks the DMG signature before unpacking it |

the feed and the DMGs live on the public website (`bicrick/da-transcribuh-site`), so updates work while
this repo stays private. 0.9.4 and older builds still point at the old GitHub feed and never see updates.

**the appcast.** `scripts/release.sh` runs `scripts/make-appcast.sh` after the DMG is notarized and stapled.
it calls Sparkle's `generate_appcast` on a folder holding just `da-transcribuh-<version>.dmg`, with enclosure URL
`https://da-transcribuh-site.vercel.app/download/da-transcribuh-<version>.dmg`. the enclosure gets an EdDSA
signature and the feed is signed (generate_appcast signs it because the app sets `SURequireSignedFeed`).
the feed lists one version. Sparkle only needs the newest.

**publish to the site.** copy the DMG to the site repo as `download/da-transcribuh-<version>.dmg` (keep older
ones), copy `appcast.xml` to the site root, point the `/download` and `/download/latest` redirects in its
`vercel.json` at the new DMG, push to main, then check `/appcast.xml` and the DMG return 200.

`generate_appcast` and `sign_update` are different binaries, so the first release may show
"generate_appcast wants to use your confidential information stored in "https://sparkle-project.org"".
click **Always Allow** while you are at the Mac. the release preflight also resolves SwiftPM packages into
`build/spm` on the first run, which fetches from github.com through git's `osxkeychain` helper. that
can raise a GitHub keychain prompt too.

**flip at public launch** (one PR, then cut the release):

1. make the repo public (or host `appcast.xml` and the DMG somewhere public, and point `SUFeedURL` there).
2. publish full releases, not prereleases. `releases/latest` skips prereleases, so the feed and the README
   download link only resolve for a full release: `PRERELEASE=0 scripts/release.sh <version> --publish`.
   make that the default in `release.sh` once betas stop.
3. in `Config/Info.plist` set `SUEnableAutomaticChecks` to `true`. optionally add
   `SUScheduledCheckInterval` (seconds, default 86400 = daily).
4. optional: `SUAutomaticallyUpdate` `true` for silent background installs (users can still opt out).
5. change the General → Updates detail text (`updatesDetail` in `ConfigurationPage.swift`) and the
   `UpdateConfigTests` expectations to match.
6. updates only reach installs that already embed Sparkle (the first release after this lands, and later).
   0.9.2 and older need one manual download.

**test an update end to end** (before launch, once the repo is public or with a local feed): install
version N, publish N+1 with `--publish`, then "Check for Updates…" in N should offer N+1, download,
verify and relaunch. to rehearse against a private feed, build a throwaway copy with a different
`SUFeedURL` and never install it over `/Applications`. `make-appcast.sh` can be dry-run with a throwaway
key file (`ED_KEY_FILE=/tmp/... ASSET_NAME=...`) so the real key is not touched.

## Dev install (keeps permissions)

`scripts/install-dev.sh` builds a Developer ID-signed copy and replaces the single
`/Applications/da transcribuh.app`. Same bundle ID and same signing requirement as a
release, so Accessibility, Microphone and Input Monitoring grants carry over. It never
runs `tccutil reset`, and it never installs a "Prompt Annotator Local" build.

```
scripts/install-dev.sh              # latest origin/main
scripts/install-dev.sh <git-ref>    # any branch, tag or sha
scripts/install-dev.sh --here       # current working tree
```

The installed version reads `<version>-dev+<shortsha>`. The build product is deleted
after install so Spotlight sees one copy. Run it after every PR merge.
