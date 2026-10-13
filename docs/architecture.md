# Architecture

TypeSwitch is a SwiftPM macOS 15+ application with an executable product target, a separate controlled test-host executable, and a test target. The app uses SwiftUI for settings and AppKit for its menu bar integration. It has no third-party Swift package dependencies.

## Event and correction flow

`InputMonitor` uses an active session `CGEventTap` so it can consume Esc only when a recent correction is eligible for undo. Other keys are passed through. It observes mouse-down and scroll events only to invalidate pending corrections; pointer coordinates are not collected. Keyboard-layout data is refreshed on the main actor and passed to the event thread through a lock-protected snapshot. Events receive monotonic sequence numbers before delivery to the main actor.

`BufferManager` retains the active word and resets on ambiguous transitions such as navigation, paste, or context change. `LayoutMapper` converts physical keyboard mappings between supported English, Russian, and Ukrainian sources. `LayoutInferenceEngine` combines that mapping with bundled dictionary evidence and refuses ambiguous candidates. `LanguageSwitchEvidenceTracker` handles conservative Russian/Ukrainian language evidence across nearby words.

`RussianInflectionDictionary` also recognizes Russian case forms through bundled Hunspell suffix rules and flagged base entries. It reverses one suffix transformation and requires the original base, its exact affix flag, and the rule's ending condition to match. This covers forms such as `копированием` without guessing endings or storing every expanded word. Known English source words stay protected, and newly recognized Russian forms do not override an ambiguous Ukrainian candidate. Recognition is limited to the bundled rules; irregular forms require explicit dictionary entries. Resources load once per process, with no runtime downloads or learning.

`LayoutCoordinator` orchestrates the flow. `AutoFixFreshnessPolicy` requires the delimiter to remain the latest observed input before a delayed correction can run. `SafetyGateEvaluator` rejects unsafe or unsupported contexts before text mutation.

## Text replacement

`AXFocusedElement` resolves the focused editable control through an injectable Accessibility seam. `AXRewriteEngine` performs and verifies text replacement. Native controls and browser controls have different write policies; browser fields must not receive a speculative whole-value replacement.

`AXRewriteRoutingPolicy` routes known browser/control cases to the bounded physical-key fallback when their AX text model is unsuitable. `SyntheticTextFallbackRewriteEngine` operates only on the observed dictionary-backed token and delimiter after context checks. Posted events are marked and temporarily suppressed from inference to avoid recursive corrections. This path is implemented, but broad real-app safety has not been established by the automated tests.

The fallback prepares all keyboard events before deleting text. Each insertion event carries explicit modifier flags and the intended character's Unicode payload, so its case does not depend on the default event translation. Physical key codes remain available for frameworks that translate events themselves. Diagnostics record only case counts and modifier state when investigating case mismatches.

`InputSourceController` tracks enabled macOS sources and switches the future layout after the correction flow. `AutoCorrectionUndoTracker` holds the most recent verified automatic correction briefly so immediate Esc can restore it in the same focused field. `CorrectionUndoEscapeGate` checks expiry and the AX focus identity before consuming Esc, including its repeat and release events. Other input, clicks, scrolling, app/input-source changes, and expiry invalidate that opportunity. The coordinator repeats freshness and context safety checks before restoring text, preserving the delimiter on both AX and bounded fallback paths.

Focus identity is resolved through the frontmost app's AX element, falling back to its focused window when no field identity is exposed. In that limited model, pointer and navigation events cancel undo; programmatic focus changes within the same window remain a manual compatibility concern.

## Local state and presentation

`PermissionsController` preflights keyboard-listening access and Accessibility trust. Settings and the status menu expose a separate action for each missing permission. Input Monitoring requests use the public `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` API to register the request, as [recommended by Apple DTS](https://developer.apple.com/forums/thread/828052). Each action opens its matching System Settings pane through `NSWorkspace`, with a general Privacy & Security fallback. The running app can be revealed in Finder for manual addition if macOS omits it from the list. Returning to TypeSwitch refreshes status; newly confirmed access starts monitoring, and detected revocation stops it and clears pending input state. Permission setup does not reset TCC or grant access automatically.

`AppSettingsStore` stores language preferences and the pause shortcut. `AppPolicyStore` stores ignored-app identities. `LearnedCorrectionStore` persists only user-confirmed mappings. A safe learning candidate is held temporarily in memory and expires without being saved unless the user confirms it.

`CorrectionExceptionStore` persists an exception immediately after a successful user-triggered Esc undo, keyed by the exact spelling and source layout. A failed, refused, or expired undo saves nothing. Exceptions and `UppercaseAbbreviationPolicy` protect automatic inference and learning suggestions; explicit correction remains available. The abbreviation allowlist is curated per source language and does not infer abbreviations from length or uppercase alone. Esc is the explicit opt-out gesture; there is no additional confirmation or popover. Exceptions survive app restarts, and Settings → Exceptions supports removal.

`StatusItemController`, settings views, and the learned-words window expose those capabilities. `DiagnosticsLogger` records redacted decision/control metadata, never the typed token or replacement. See [privacy](privacy.md) for storage and permission details.

## Verification boundaries

Tests exercise mapping, ambiguity, freshness, undo, state persistence, redaction, and rewrite/refusal behavior through test seams. `TypeSwitchTestHost` provides controlled AppKit and SwiftUI editable, secure, and read-only fields for manual checks. The [compatibility matrix](compatibility.md) separates expected classifications from observed results; an expected classification is not a verified result.

The publication contains a reviewed source snapshot with fresh public history. The private development history, local build products, diagnostics, and internal task logs are not part of this repository.
