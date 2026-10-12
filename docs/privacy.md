# TypeSwitch Privacy Model

TypeSwitch is a local-only macOS utility. It exists to detect wrong-layout input, safely rewrite text in supported contexts, and switch the active input source when appropriate.

## Data Handling

TypeSwitch does not send text, diagnostics, app context, or permission state over the network. The v1 implementation has no telemetry, analytics, crash upload, sync, OCR, screen recording, or remote service dependency.

Dictionary resources are bundled locally. The frequency lists are generated during development from third-party open word-frequency data and are not fetched by the app at runtime.

When a safe word is missing from the bundled dictionary, TypeSwitch checks the mapped target against the installed local macOS spelling dictionary. Only an independently recognized target may be kept in process memory for up to 30 seconds and offered through `Add Last Word to Dictionary…` in the menu. Nothing is learned automatically. If the user confirms the correction, the pair is stored locally in `UserDefaults` and can be reviewed or deleted from `Learned Words…`. Learned words are not written to diagnostics or sent over the network.

The runtime buffer is intentionally narrow. It tracks only the active word or editable fragment needed for correction decisions. The latest verified automatic correction may remain in memory for up to three seconds so immediate Backspace can restore it. A successful restoration clears that candidate and does not create a persistent or session-wide exception. The candidate is not persisted or written to diagnostics. Diagnostics are redacted by design and must not include raw typed tokens or replacement text. Local diagnostic events may be written to `~/Library/Application Support/TypeSwitch/diagnostics.log`; those entries contain decision metadata, app/control metadata, and redacted AX capability summaries only. AX tree diagnostics may include role, subrole, settable state, selection availability, child count, and text value length, but not the text value itself.

## Permissions

TypeSwitch needs Input Monitoring to observe keyboard events through a passive listen-only `CGEventTap`. It needs Accessibility to inspect the focused element and perform AX-first text replacement in supported editable controls.

Ordinary apps do not need to be registered. TypeSwitch first attempts AX replacement. If an app exposes an empty or unusable AX text model, a bounded fallback may post local delete and physical keyboard events for exactly the observed dictionary-backed token and delimiter. It does not use the clipboard, screen capture, OCR, network calls, or raw diagnostic logging. It never runs after a secure-input, password, terminal, non-writable-context, or ignored-app refusal.

These permissions are user-granted macOS privacy permissions. Internal testing must launch TypeSwitch as a `.app` bundle with a stable bundle identifier (`com.dmvishnyak.typeswitch`) before granting permissions, because macOS Privacy & Security panes list bundled apps more reliably than raw SwiftPM executables. The dev build installs to `~/Applications/TypeSwitch.app` to keep the TCC identity and user selection path stable.

Apple references checked for the current permission/API model:

- `CGEvent.tapCreate`: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29
- `CGEvent.post(tap:)`: https://developer.apple.com/documentation/coregraphics/cgevent/post%28tap%3A%29
- `CGEvent.keyboardSetUnicodeString`: https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29
- `AXUIElement`: https://developer.apple.com/documentation/applicationservices/axuielement
- `AXUIElementSetAttributeValue`: https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue
- `NSTextInputContext.keyboardInputSources`: https://developer.apple.com/documentation/appkit/nstextinputcontext/keyboardinputsources
- `Information Property List`: https://developer.apple.com/documentation/bundleresources/information-property-list
- `CFBundleIdentifier`: https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier

## Refusal Policy

TypeSwitch must do nothing when a context is unsafe or ambiguous. V1 refuses password-like fields, secure input, terminal-like contexts, non-writable AX contexts, missing selection ranges, missing observed tokens, and auto-fix tokens missing from the local dictionary. A missing token can become a learning candidate only after the same safety checks pass; it still cannot be rewritten until the user explicitly confirms and types it again.

Unbounded or speculative synthetic delete-and-retype is excluded from v1. The compatibility fallback must remain dictionary-backed, word-boundary-only, frontmost-app-validated, and gated by the same refusal policy. Refusal is preferable to a risky rewrite.

## Internal Test Requirement

Before using TypeSwitch as a daily utility, internal testing must confirm that diagnostics remain redacted, blocked contexts refuse cleanly, and dictionary auto-fix remains limited by the global toggle and safety gates.
