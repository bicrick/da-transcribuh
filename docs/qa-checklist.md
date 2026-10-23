# launch QA checklist

run this on the exact build u plan to ship, installed in /Applications. tick each box. note the build
(`version (build)`, from About or `defaults read "/Applications/da transcribuh.app/Contents/Info" CFBundleShortVersionString`).

two parts. **A** is automated and read-only (`scripts/qa-auto.sh`). **B** is by hand and needs a person at the keyboard.

## A. automated (scripts/qa-auto.sh)

```sh
scripts/qa-auto.sh                      # checks /Applications/da transcribuh.app
scripts/qa-auto.sh path/to/other.app    # or any other copy
```

it changes nothing and opens no windows. it checks:

- bundle id, version and build
- `codesign --verify --deep --strict`, Developer ID authority, team `3BUPEZ2FJQ`, hardened runtime, secure timestamp
- entitlements: audio-input present, no `get-task-allow`
- Gatekeeper (`spctl`): must say `Notarized Developer ID` for a release. a dev install says "Unnotarized" (warning only)
- Sparkle: framework embedded, all four helpers carry team `3BUPEZ2FJQ` (a failure on a notarized build, a warning
  on a dev build), `SUPublicEDKey` equals `Config/Info.plist`, signed feed required, no automatic checks, feed URL status
- only one indexed copy of the app outside the Desktop checkouts, and the app is running
- no modifier key reported as held (catches a synthetic ⌘V that never releases ⌘)

also run the unit suite (`xcodebuild test -scheme PromptAnnotator`). expect 0 failures. one skip is normal
(`PageLayoutAuditTests.testRenderEveryPageOffscreen` needs `DTPageAuditDir`).

## B. manual

### 1. fresh install
best on a second user account or a spare Mac, so ur own permissions and settings don't hide problems.

- [ ] download the DMG from the release page. it opens with no Gatekeeper warning beyond "downloaded from the internet"
- [ ] drag to Applications, launch. no "damaged" or "unidentified developer" dialog
- [ ] the menu bar icon appears. onboarding opens on its own
- [ ] `~/Library/Application Support/PromptAnnotator` is created. nothing is written to ~/Documents before the first session

### 2. onboarding (Welcome, Permissions, Keybinds, Clipboard history, Appearance, Model, Try a session, Ready)
- [ ] each step's Next/Back works. closing the window mid-way and relaunching resumes sanely
- [ ] **Permissions.** microphone prompt appears once and the row turns granted. Accessibility opens System Settings,
      and the row updates after u toggle it (without relaunch). Screen Recording likewise
- [ ] deny the microphone. the step says what to do and links to System Settings. no crash
- [ ] **Keybinds.** default start/stop is ⌥Space. recording a new chord works. ⌘Space and a chord with ⇧ are refused with a message
- [ ] **Model.** the default (small.en, about 217 MB) downloads with progress. pull the network mid-download: a calm
      offline message, and retry works once back online
- [ ] **Try a session.** speak a sentence. words show live and the text lands in the practice field
- [ ] **Ready.** finishing closes onboarding. relaunching doesn't show it again

### 3. hotkey, record, stop, paste
in TextEdit, Notes, a browser text field, Slack, and a terminal:
- [ ] ⌥Space starts. the island shows and the start sound plays (if on)
- [ ] ⌥Space again stops. the text pastes into the focused field in well under a second
- [ ] after a paste, ⌘ isn't stuck. typing `a` types `a`, not ⌘A (or run `scripts/qa-auto.sh` and check the last line)
- [ ] the clipboard holds the transcript after the paste. what u had copied before is still in clipboard history
- [ ] a silent take shows "No speech detected", pastes nothing and saves nothing to History
- [ ] stop while focus is in a non-text place (Finder desktop). no paste is typed into the void and the text is on the clipboard
- [ ] hold ⇧ during a session and draw. on release a screenshot tile is added. the tile is in the session folder
- [ ] long take (about 60 s). stop still feels quick and the whole text arrives

### 4. Return on ⇧
- [ ] turn on "Return on ⇧" in General
- [ ] stop with ⇧ held. the text pastes, then a plain Return is sent (a chat message sends; in TextEdit a new line, not ⌘Return)
- [ ] stop without ⇧. no Return is sent
- [ ] turn it off. ⇧ at stop sends no Return

### 5. clipboard panel (⌘⇧C)
- [ ] ⌘⇧C opens the panel over the current app. Esc closes it, and focus goes back to where it was
- [ ] copy text, an image and a file in other apps. each shows up, newest first
- [ ] pick an item. it pastes into the previous app. arrow keys and Return work
- [ ] search filters. pin an item, quit and relaunch, and it is still pinned
- [ ] the history limit setting trims old unpinned items. Clear history needs a second click to confirm
- [ ] with "ignore concealed" on (Clipboard settings), a copy from a password manager is not recorded
- [ ] change the panel shortcut in settings. the old one stops working

### 6. history
- [ ] each saved session appears in History with time, text and tiles
- [ ] open folder reveals the session in Finder. copy works. delete asks first and removes the folder
- [ ] unplug or disable the mic, then try to start. an error shows, and the **previous** session is still in History
- [ ] (if u can) fill the disk or make the sessions folder read-only, then do a take. the words are still pasted and
      the message says they were copied

### 7. models
- [ ] the Model page lists the choices with sizes. switch to large-v3 turbo: it downloads, then the next session uses it
- [ ] switch back. no re-download
- [ ] remove a custom model. it leaves the list
- [ ] bring your own model (docs/BRING_YOUR_OWN_MODEL.md): a valid endpoint works. a wrong key shows a clear error
- [ ] start a session before the model is ready. it waits or says so, and doesn't hang

### 8. Sparkle, check for updates
- [ ] "Check for Updates…" is in the menu bar menu and on General → Updates
- [ ] with a newer public release in the feed: it offers the update, shows notes, installs, relaunches into the new version,
      and permissions are kept
- [ ] with no newer version: "You're up to date"
- [ ] while the repo is private: a calm update error is expected (feed is 404)
- [ ] no update check happens on its own (automatic checks are off)

### 9. settings, quit, relaunch
- [ ] General: launch at login on, log out and in, and the app starts. turn it off and it doesn't
- [ ] Show log opens the log. errors.log isn't huge
- [ ] change appearance, sound and shortcuts, then quit (menu → Quit) and relaunch. all settings kept
- [ ] quit during a recording. the app quits cleanly. relaunch, and no half-written session or crash report
      (`~/Library/Logs/DiagnosticReports`) is left
- [ ] Activity Monitor at idle: about 0% CPU, memory steady over 10 min

### sign-off
| build | date | who | A (qa-auto) | B (manual) | notes |
|---|---|---|---|---|---|
| | | | | | |
