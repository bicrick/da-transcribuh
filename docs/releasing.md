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
