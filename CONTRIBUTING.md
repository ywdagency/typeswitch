# Contributing to TypeSwitch

TypeSwitch is an experimental macOS utility. Read the [architecture](docs/architecture.md), [privacy model](docs/privacy.md), and [compatibility matrix](docs/compatibility.md) before changing correction behavior. A missed correction is preferable to changing the wrong text.

## Development

Use macOS 15+ with Swift 6 and the macOS SDK. There are no external Swift package dependencies.

```sh
swift test
python3 -m unittest discover -s scripts/tests
swift build --configuration release
./scripts/build-dev-app.sh
./scripts/build-test-host.sh
```

The app scripts install local development bundles in `~/Applications`. They use a local development signing identity when available and ad-hoc signing otherwise. Do not commit app bundles, signing certificates, diagnostics, or learned words. Tests must use isolated preferences and fake platform clients where possible.

## Changes and pull requests

Keep each pull request focused on one problem. Explain the trigger, resulting behavior, verification performed, and remaining limitations. Add regression tests for changed inference, safety, event ordering, or rewrite semantics. Preserve refusal paths and verify platform-sensitive APIs against current Apple documentation. GitHub Actions runs automated tests and a release build; a passing run does not establish compatibility with a real editor.

For changes to text replacement, use the controlled test host and record actual results in [testing](docs/testing.md) and [compatibility](docs/compatibility.md). Never mark an untested app as supported. Do not introduce networking, telemetry, OCR, screen recording, or broader rewrite behavior as part of an unrelated fix.

## Bug reports

Use the bug-report template with the macOS version, app/version, active input layouts, a synthetic example, and expected versus actual behavior. Do not attach real typed text, credentials, learned words, or unreviewed logs. Possible security or privacy defects belong in [private reports](SECURITY.md).

## Dictionary data

The bundled dictionaries are generated resources with separate licenses. Preserve their headers, [license texts](LICENSES/), and [source notices](docs/third-party-notices.md). Explain data changes separately from code changes. Run `scripts/update-frequency-dictionaries.py` only when intentionally regenerating data; it downloads upstream files and is not part of normal app startup or CI. Russian inflection resources can be regenerated separately with `python3 scripts/russian_inflections.py`; their upstream revision and SHA-256 hashes are pinned. Python 3 is required for these developer tools and their tests, not for running the app.
