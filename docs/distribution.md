# GitHub distribution

The repository prepares universal macOS 15+ DMGs with an Applications shortcut, installation notes, bundled dictionary attribution and license texts, and a SHA-256 checksum. Binary artifacts and signing material stay out of Git. No notarized release has been published yet.

## Local packaging check

```sh
./scripts/build-release.sh 0.1.0 1 --preview
```

This builds both arm64 and x86_64, assembles and verifies an ad-hoc signed app, and writes `dist/TypeSwitch-0.1.0-macOS-universal-preview.dmg` with its checksum. It does not install, launch, notarize, or upload the app. `PREVIEW.txt` marks the image as unsuitable for public installation. Architecture verification confirms the binary contains both slices; Intel execution requires a separate Intel Mac test.

## Signed release

Apple requires a Developer ID Application certificate, hardened runtime, and notarization for normal Gatekeeper distribution. See [Apple's distribution requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). Apple Development and ad-hoc signatures do not satisfy that release path.

With a Developer ID identity in the local keychain and credentials previously stored using `xcrun notarytool store-credentials`, run:

```sh
CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARYTOOL_PROFILE='typeswitch-notary' \
./scripts/build-release.sh 0.1.0 1
```

The script signs with hardened runtime and a secure timestamp, submits an app ZIP to Apple, staples and validates the app ticket, builds and signs the DMG, submits it, staples and validates its ticket, and checks Gatekeeper acceptance before writing the final DMG and checksum to `dist/`. Failed checks stop packaging. Only this mode is suitable for a release asset. Build from the intended clean, reviewed commit; notarization uploads the built app and DMG to Apple and does not send user data.

## GitHub draft workflow

The manually triggered **Prepare signed release** workflow runs tests, builds and notarizes the universal DMG, and creates a **draft prerelease** with the DMG, checksum, and version-specific notes. It never runs on ordinary pushes and does not publish the draft. Run it on `main` with an unused `X.Y.Z` version and increasing numeric build number. Prepare `docs/releases/X.Y.Z.md` before dispatching. Existing tags and releases are refused to avoid attaching a different build to an existing version.

Configure repository Actions secrets `MACOS_CERTIFICATE_P12_BASE64` (exported Developer ID Application certificate with its private key, base64 encoded), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY` (full certificate name), `NOTARY_API_KEY_P8` (App Store Connect team API key contents), `NOTARY_API_KEY_ID`, and `NOTARY_API_ISSUER_ID`. Use a team API key authorized for notarization. Never commit credentials. The workflow imports them into a temporary keychain, stores a notarytool profile there, and removes the keychain and key file after the job, including failures.

Before publishing the draft, download the assets through a browser on a clean Mac and verify Gatekeeper, drag-and-drop installation, permission onboarding, and the applicable [compatibility checks](compatibility.md). Test both supported processor architectures before claiming both were observed. Update `docs/installation.md`, README, changelog, and release notes to reflect actual publication and verification. The draft's source archive preserves the exact bundled dictionary data and transformation sources alongside their licenses. Publication is a separate maintainer action.
