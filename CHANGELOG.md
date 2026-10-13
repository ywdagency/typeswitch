# Changelog

## Unreleased

### Fixed

- Set explicit modifiers and Unicode characters on bounded fallback keyboard events to preserve replacement case. The user confirmed `lfkmit` → `дальше` in Codex after the fix; broader manual verification remains incomplete.

### Changed

- Replace immediate Backspace undo with Esc, preserving the delimiter and restoring the source layout. Continued input and context changes cancel the opportunity.
- Save a permanent, case-sensitive layout exception immediately after a successful Esc undo, without an additional prompt; manage exceptions in Settings → Exceptions.
- Protect curated source-language uppercase abbreviations while retaining normal correction for uppercase words.

- Recognize Russian inflected forms using bundled Hunspell suffix rules and flagged bases, including `rjgbhjdfybtv` → `копированием`, while protecting valid English and ambiguous Russian/Ukrainian candidates.
- Separate Input Monitoring and Accessibility setup actions request the selected permission and open its matching System Settings pane.
- Input Monitoring setup explicitly registers the access request through `IOHIDRequestAccess`.
- Settings can reveal the running app in Finder for manual addition to macOS permission lists.
- Returning to TypeSwitch refreshes permission state and starts monitoring after access is confirmed. Detected permission revocation clears pending input state and stops monitoring.
- Removed dictionary coverage counts from Settings → About; source and license attribution remains available.
- Added contributor guidance and issue templates, and extended macOS CI to build release executables.

## Initial public source snapshot — 2026-10-12

Published the experimental Swift 6 implementation, local EN/RU/UA dictionaries, controlled test host, and automated tests with a reviewed public history. See the [publication review](docs/publication-review.md). No notarized binary release was published.
