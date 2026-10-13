# Changelog

## Unreleased

## 0.1.0 — 2026-10-13

Published the first signed, notarized universal macOS DMG as an experimental prerelease (build 2). See [release notes and downloads](https://github.com/ywdagency/typeswitch/releases/tag/v0.1.0).

### Fixed

- Retry Apple ticket retrieval at most three times after stapler error 68, including transient CloudKit connection failures, while retaining all signature, ticket validation, and Gatekeeper checks. Invalid or revoked ticket errors fail immediately.

- Recognize `what's` in the bundled English dictionary so `црфеэы` corrects at a word boundary, including title case and trailing punctuation.

- Serialize text replacement and layout switching with a bounded input queue; replay continued typing in order with the refreshed layout. Remove the 250 ms real-input suppression window and recheck freshness atomically before capture. Regression tests cover typing during fallback deletion/insertion, modifiers, queue limits, cancellation, and undo key releases; the user reported one missing contraction in a Codex fast-typing sample, with broader real-app verification still pending.

- Set explicit modifiers and Unicode characters on bounded fallback keyboard events to preserve replacement case. The user confirmed `lfkmit` → `дальше` in Codex after the fix; broader manual verification remains incomplete.

### Changed

- Verify release DMG contents, source revision, resources, license notices, signatures, and notarization before uploading assets. CI also builds and checks an ad-hoc universal image. Allow explicit updates of unpublished draft candidates while refusing existing tags and published releases; refresh installation instructions for signed builds.

- Prepare universal macOS DMGs with bundled license notices, checksums, installation instructions, and a manually triggered GitHub draft release workflow requiring Developer ID signing and notarization. Local preview packaging is available without release credentials.

- Replace immediate Backspace undo with Esc, preserving the delimiter and restoring the source layout. Continued input and context changes cancel the opportunity.
- Save a permanent, case-sensitive layout exception immediately after a successful Esc undo, without an additional prompt; manage exceptions in Settings → Exceptions.
- Use one curated dictionary for source-language uppercase abbreviation protection and wrong-layout recognition, including `USB`, `SD`, and `SDI`, while retaining normal correction for uppercase words and refusing competing targets or valid source words.

- Recognize Russian inflected forms using bundled Hunspell suffix rules and flagged bases, including `rjgbhjdfybtv` → `копированием`, while protecting valid English and ambiguous Russian/Ukrainian candidates.
- Separate Input Monitoring and Accessibility setup actions request the selected permission and open its matching System Settings pane.
- Input Monitoring setup explicitly registers the access request through `IOHIDRequestAccess`.
- Settings can reveal the running app in Finder for manual addition to macOS permission lists.
- Returning to TypeSwitch refreshes permission state and starts monitoring after access is confirmed. Detected permission revocation clears pending input state and stops monitoring.
- Removed dictionary coverage counts from Settings → About; source and license attribution remains available.
- Added contributor guidance and issue templates, and extended macOS CI to build release executables.

## Initial public source snapshot — 2026-10-12

Published the experimental Swift 6 implementation, local EN/RU/UA dictionaries, controlled test host, and automated tests with a reviewed public history. See the [publication review](docs/publication-review.md). No notarized binary release was published.
