# Architecture

TypeSwitch is a SwiftPM macOS 15+ application with an executable product target, a separate controlled test-host executable, and a test target. The app uses SwiftUI for settings and AppKit for its menu bar integration. It has no third-party Swift package dependencies.

## Event and correction flow

`InputMonitor` observes keyboard events with a passive `CGEventTap`. Keyboard-layout data is refreshed on the main actor and passed to the event thread through a lock-protected snapshot. Events receive monotonic sequence numbers before delivery to the main actor.

`BufferManager` retains the active word and resets on ambiguous transitions such as navigation, paste, or context change. `LayoutMapper` converts physical keyboard mappings between supported English, Russian, and Ukrainian sources. `LayoutInferenceEngine` combines that mapping with bundled dictionary evidence and refuses ambiguous candidates. `LanguageSwitchEvidenceTracker` handles conservative Russian/Ukrainian language evidence across nearby words.

`LayoutCoordinator` orchestrates the flow. `AutoFixFreshnessPolicy` requires the delimiter to remain the latest observed input before a delayed correction can run. `SafetyGateEvaluator` rejects unsafe or unsupported contexts before text mutation.

## Text replacement

`AXFocusedElement` resolves the focused editable control through an injectable Accessibility seam. `AXRewriteEngine` performs and verifies text replacement. Native controls and browser controls have different write policies; browser fields must not receive a speculative whole-value replacement.

`AXRewriteRoutingPolicy` routes known browser/control cases to the bounded physical-key fallback when their AX text model is unsuitable. `SyntheticTextFallbackRewriteEngine` operates only on the observed dictionary-backed token and delimiter after context checks. Posted events are marked and temporarily suppressed from inference to avoid recursive corrections. This path is implemented, but broad real-app safety has not been established by the automated tests.

`InputSourceController` tracks enabled macOS sources and switches the future layout after the correction flow. `AutoCorrectionUndoTracker` holds the most recent verified automatic correction briefly so immediate Backspace can restore it in the same app. Other input, context changes, and expiry invalidate that opportunity.

## Local state and presentation

`PermissionsController` preflights keyboard-listening access and Accessibility trust. Settings and the status menu expose a separate action for each missing permission. Input Monitoring requests use the public `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` API to register the request, as [recommended by Apple DTS](https://developer.apple.com/forums/thread/828052). Each action opens its matching System Settings pane through `NSWorkspace`, with a general Privacy & Security fallback. The running app can be revealed in Finder for manual addition if macOS omits it from the list. Returning to TypeSwitch refreshes status; newly confirmed access starts monitoring, and detected revocation stops it and clears pending input state. Permission setup does not reset TCC or grant access automatically.

`AppSettingsStore` stores language preferences and the pause shortcut. `AppPolicyStore` stores ignored-app identities. `LearnedCorrectionStore` persists only user-confirmed mappings. A safe learning candidate is held temporarily in memory and expires without being saved unless the user confirms it.

`StatusItemController`, settings views, and the learned-words window expose those capabilities. `DiagnosticsLogger` records redacted decision/control metadata, never the typed token or replacement. See [privacy](privacy.md) for storage and permission details.

## Verification boundaries

Tests exercise mapping, ambiguity, freshness, undo, state persistence, redaction, and rewrite/refusal behavior through test seams. `TypeSwitchTestHost` provides controlled AppKit and SwiftUI editable, secure, and read-only fields for manual checks. The [compatibility matrix](compatibility.md) separates expected classifications from observed results; an expected classification is not a verified result.

The publication contains a reviewed source snapshot with fresh public history. The private development history, local build products, diagnostics, and internal task logs are not part of this repository.
