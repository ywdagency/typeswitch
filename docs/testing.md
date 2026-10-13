# TypeSwitch Internal Testing

This document defines the first internal test pass. The goal is not broad compatibility. The goal is to prove that dictionary-backed auto-fix works in controlled contexts, the global toggle is reliable, and unsafe contexts refuse cleanly.

## Baseline Commands

Run from the repository root:

```bash
swift build
swift test
./scripts/build-dev-app.sh
./scripts/build-test-host.sh
open ~/Applications/TypeSwitch.app
open ~/Applications/TypeSwitchTestHost.app
```

Automated tests use isolated `UserDefaults` suites that are removed after every test. Repeated dictionary examples are parameterized so a failure identifies the exact input/replacement pair instead of stopping a larger batch at its first failure.

The current executable product name is `TypeSwitch`. For permission testing, prefer `~/Applications/TypeSwitch.app` over `swift run TypeSwitch`; macOS Privacy & Security lists bundled apps more reliably than raw SwiftPM executables, and a stable app location avoids TCC confusion from `.build` paths.

## Permission Setup

Open TypeSwitch from `~/Applications/TypeSwitch.app`. Settings → General shows a separate row for each permission. Click `Enable…` on a missing row to request only that permission and open its matching System Settings page. The status menu offers the same separate actions. Enable TypeSwitch in:

- Privacy & Security -> Input Monitoring -> TypeSwitch
- Privacy & Security -> Accessibility -> TypeSwitch

Verify each action reaches its named page. Links are best effort; if macOS rejects a pane URL, TypeSwitch opens Privacy & Security. Input Monitoring explicitly requests access through `IOHIDRequestAccess`, as [recommended by Apple DTS](https://developer.apple.com/forums/thread/828052) when CoreGraphics and Accessibility access overlap.

If Input Monitoring does not list TypeSwitch automatically, click `Show TypeSwitch in Finder` in TypeSwitch, then use `+` in the macOS pane to add that exact app. The Finder action resolves the running bundle rather than assuming an installation path.

The dev app should be signed with an Apple Development identity when available. Rebuilding with a different signing identity may require removing and re-adding TypeSwitch in Input Monitoring and Accessibility.

Return to TypeSwitch after granting permissions and confirm both rows show `Allowed`. Status refreshes on app activation; `Check Again` provides a manual refresh. Confirm the diagnostic log shows `inputMonitor startRequested`, `eventTapCreated`, and `firstKeyDownObserved`. If macOS requires a relaunch, quit and reopen the same app bundle. Revoke one permission, return, and confirm correction stops and the missing row reappears. Real TCC transitions require manual verification; unit tests use a fake client and never grant, revoke, or reset real permissions.

On 2026-10-12, the signed development app's fresh launch reported both permission checks granted, created the event tap, and observed keyboard input. The user reported correction working in GPT and GPT Classic. This is a limited session result; it does not complete the controlled host or cross-app safety matrix. UI automation could not verify permission pane navigation because app selection timed out, so pane navigation and grant/revocation transitions remain pending.

Open Settings and verify About shows the product description and source attribution without dictionary coverage counts. Confirm the FrequencyWords and Hunspell links open their source and license pages.

## Controlled Test Host

Run the controlled host before testing TextEdit, browsers, Electron apps, or other third-party controls. It is a separate signed app with bundle identifier `com.dmvishnyak.typeswitch.testhost` and does not import or run product code.

With auto-fix enabled, type `ghbdtn ` into each AppKit `NSTextField`, AppKit `NSTextView`, SwiftUI `TextField`, and SwiftUI `TextEditor`. Each editable control must become `привет ` with the caret after the delimiter. Repeat `руддщ ` in the opposite direction.

Type the same tokens into the SwiftUI `SecureField`; TypeSwitch must refuse without changing the text or future input source. The read-only AppKit field must remain unchanged and must never trigger the bounded fallback. Record all six results in `docs/compatibility.md`. A wrong range, wrong target, secure-field rewrite, or read-only fallback is `risky-stop`.

## Hotkeys

Manual correction is the primary internal-test path:

- `Control+Option+Space`: turn dictionary auto-fix on or off.

The menu bar exposes the same toggle and shows the configured shortcut.

Left-click the menu bar icon and confirm the TypeSwitch menu opens. Right-click while auto-fix is on and confirm it turns off without opening the menu. Right-click again and confirm it turns back on. Each state change must play one short click sound.

After every successful, read-back-verified AX text replacement, confirm TypeSwitch plays the same short click sound used by the right-click ON/OFF toggle. A layout-only switch, ignored token, failed rewrite, or unconfirmable bounded fallback must remain silent.

After an automatic replacement, press Esc immediately. Confirm the original token and source layout return, the delimiter remains, and the caret stays after it. No popover or confirmation should appear. Confirm the original spelling appears immediately in Settings → Exceptions and is not auto-corrected again in the same source layout, including before trailing punctuation. Other case variants and layouts remain independent. Restart the app and confirm the exception still applies. Remove it in Settings → Exceptions and confirm correction resumes. A failed or refused undo must not create an exception.

Repeat Esc after waiting more than three seconds, after typing another character, after Backspace, after navigation, after clicking another field in the same app, after scrolling, after changing input sources, and after changing apps. In those cases Esc must retain the app's normal behavior and must not restore an earlier token. Backspace must always retain normal deletion behavior. Modified Esc must pass through. Hold Esc after a valid undo and confirm it cannot undo a second correction. Repeat the immediate-undo case in the Codex composer to verify the bounded fallback path with the delimiter preserved. Secure, password, terminal, ignored-app, stale-event, and non-writable contexts must still refuse.

Type known source-language abbreviations such as `CEO`, `API`, `СССР`, and `ЗСУ` in their corresponding layouts and confirm no automatic rewrite or layout-only switch occurs. Type `LFKMIT ` with US English active and confirm `ДАЛЬШЕ `; uppercase alone must not disable normal correction. Type `ФЗШ ` with Russian active and confirm `API `: an abbreviation in the target language must not protect a wrong-layout source spelling. Unknown abbreviations receive no automatic uppercase heuristic; a successful Esc undo saves an exception for their exact spelling and source layout.

After one RU→EN correction, continue typing several normal English words and confirm they remain unchanged and do not produce repeated clicks. Repeat in the opposite direction.

Add EN, RU, and UA in macOS Keyboard settings and confirm only these detected languages appear in TypeSwitch. Change the macOS input source mid-word and confirm the partial buffer is discarded. After TypeSwitch switches to Ukrainian-PC, type Ukrainian words and confirm diagnostics count Cyrillic characters rather than Latin physical-key characters. With RU active, type two Ukrainian-only words within eight seconds and confirm TypeSwitch switches to UA without rewriting them; pause longer than eight seconds and confirm evidence expires. With UA active, confirm `грізть` maps to `грызть`, while source-valid `ті`, `мі`, and RU/UA-common `слово` remain unchanged.

Leave TypeSwitch running while typing and switching EN/RU/UA sources repeatedly. Confirm no crash report contains `SystemKeyboardCharacterResolver`, `TSMGetInputSourceProperty`, or `_dispatch_assert_queue_fail` on `TypeSwitch.InputMonitor`. The automated regression test refreshes the layout snapshot on MainActor and reads it from a detached task.

In Messages, switch from RU or UA to English and immediately continue typing several normal English words without pausing. TypeSwitch must not rewrite an English word to the same English word. If the monitor still holds a stale physical-layout snapshot for the first completed token, diagnostics must show `autoFixSkipped reason=layoutSnapshotMismatch`; the token must remain unchanged and the snapshot must refresh. Continue typing quickly while AX diagnostics are slow and confirm older word-boundary requests are skipped as `staleInputSequence` instead of executing in a burst.

With UA active, type `єротика ` and confirm it maps to Russian `эротика ` because the source word is absent from UA, the target exists in RU, and `э` is Russian-exclusive.

For learning, type a valid wrong-layout word that is absent from both bundled and learned dictionaries but recognized by the installed macOS dictionary in the target language. Confirm that no automatic window interrupts typing and that `Add Last Word to Dictionary…` appears in the menu for 30 seconds. Type the normal Russian word `что` and confirm the mechanical mapping `xnj` is rejected without a menu candidate. Adding must require confirmation and must not alter the already typed text. Type the word again and confirm normal dictionary-backed auto-fix now applies. Open `Learned Words…`, remove the entry, and confirm the word is no longer corrected.

## Test Result Format

Record each result in `docs/compatibility.md` using this shape:

`App | Control | Flow | Expected | Actual | Status | Notes`

Allowed statuses are `pass`, `blocked-as-expected`, `failed-safe`, and `risky-stop`.

`risky-stop` means TypeSwitch rewrote text in the wrong element, rewrote the wrong range, rewrote when the context should have been blocked, or switched layout in a way that masked a rewrite failure. Stop widening compatibility immediately if this happens.

## Auto-Fix Matrix

Use `Control+Option+Space` to confirm auto-fix is enabled before each correction test.

Native AppKit or TextEdit plain text:

- Type `ghbdtn `, expect `привет ` and future input source switched to Russian.
- Type `руддщ `, expect `hello ` and future input source switched to English.
- Turn auto-fix off with the shortcut, type `ghbdtn `, and confirm that no rewrite occurs.
- Turn auto-fix back on and confirm correction resumes.

Browser textarea:

- Repeat dictionary word-boundary auto-fix in Safari.
- Repeat dictionary word-boundary auto-fix in Chrome. Confirm diagnostics select `rewriteRouting path=boundedFallback` before any AX text mutation, and confirm the caret remains after the replacement and delimiter; it must not jump to the beginning of the word or field.
- Repeat dictionary word-boundary auto-fix in the ChatGPT desktop composer in both GPT and GPT Classic modes. Confirm its `AXTextArea` uses `rewriteRouting path=boundedFallback`, the exact word and delimiter are replaced, and the target input source remains active for subsequent typing.
- Repeat in the ChatGPT app (`com.openai.chat`) and confirm AX-first replacement succeeds.
- Repeat in the Codex/ChatGPT composer (`com.openai.codex`) and confirm the bounded fallback succeeds after the empty AX text model returns `invalidRange`.
- In the Codex/ChatGPT composer, type `ghbdsn ` on EN and confirm the physical-key fallback produces `привіт ` after switching to UA; confirm generated replacement events do not create a second correction decision.
- In Settings > Ignored Apps, add applications through the `+` picker and by dragging from Finder, confirm their icons appear, verify `−` removes the selected app, and confirm ignored apps never rewrite text.
- Switch focus before a delayed fallback and confirm no deletion or insertion occurs in the new app.

Ignored apps:

- From the status-item menu, choose `Ignore <Current App>` and confirm neither AX rewrite nor fallback runs there.
- Confirm the app appears in the compact `Ignored Apps` section in Settings.
- Remove it and confirm correction resumes without relaunching TypeSwitch.

Blocked contexts:

- Terminal must refuse.
- iTerm2 must refuse.
- Password-like fields must refuse.
- Secure input contexts must refuse when available.
- Read-only or non-writable AX contexts must refuse.

Auto-fix is expected only after a word boundary, only for words present in the local dictionary, and only when the focused field passes safety checks. It must not correct mid-word and must not run in Terminal or iTerm2. The global toggle must stop and resume correction immediately.

When a context fails unexpectedly, inspect the redacted local log at `~/Library/Application Support/TypeSwitch/diagnostics.log`. The log must not contain raw typed text or replacement text.

## Exit Criteria

The internal test pass is complete when `swift build` and `swift test` pass, dictionary auto-fix succeeds in at least one controlled native text input, the toggle hotkey is reliable, all blocked-context checks refuse safely, diagnostics remain redacted, and `docs/compatibility.md` contains the observed results.

## Single-Instance Check

Launch the installed `TypeSwitch.app`, then request a second launch with `open -n ~/Applications/TypeSwitch.app`. Confirm that the second process exits immediately, the existing TypeSwitch instance is activated, and only one TypeSwitch process remains. Repeat once after an unclean termination to confirm that the file lock is released by the operating system.
