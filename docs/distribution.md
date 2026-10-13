# GitHub distribution

The repository prepares universal macOS 15+ DMGs with an Applications shortcut, installation notes, bundled dictionary attribution and license texts, and a SHA-256 checksum. Binary artifacts and signing material stay out of Git. No notarized release has been published yet.

## Local packaging check

```sh
./scripts/build-release.sh 0.1.0 1 --preview
```

This builds both arm64 and x86_64, assembles and verifies an ad-hoc signed app, and writes `dist/TypeSwitch-0.1.0-macOS-universal-preview.dmg` with its checksum. It does not install, launch, notarize, or upload the app. `PREVIEW.txt` marks the image as unsuitable for public installation. Architecture verification confirms the binary contains both slices; Intel execution requires a separate Intel Mac test.

Verify the assembled preview with:

```sh
python3 scripts/verify-dmg.py dist/TypeSwitch-0.1.0-macOS-universal-preview.dmg --version 0.1.0 --build-number 1 --preview
```

The verifier mounts the image read-only and checks its checksum, metadata, source revision, dictionaries, license notices, installation shortcut, and both binary architectures. Distribution mode (without `--preview`) additionally requires Developer ID signing, hardened runtime, timestamps, stapled app/image tickets, and Gatekeeper acceptance. It never installs or launches the app and detaches the image after validation or failure. Use a checkout matching the build's source revision, or pass its checkout path with `--source-dir`.

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

The manually triggered **Prepare signed release** workflow runs tests, builds and notarizes the universal DMG, verifies its contents, and creates a **draft prerelease** with the DMG, checksum, and version-specific notes. It never runs on ordinary pushes and does not publish the draft. Run it on `main` with an unused `X.Y.Z` version and increasing numeric build number. Prepare `docs/releases/X.Y.Z.md` before dispatching. Existing tags and releases are refused by default to avoid attaching a different build to an existing version.

For iteration before publication, explicitly select `update_draft` and increase the build number. This mode requires an existing unpublished draft and refuses any existing Git tag. It repeats those checks after notarization before replacing draft assets and updating the target commit and notes. Published releases cannot be updated through this workflow. Keep downloaded copies of earlier candidates if they are needed for comparison.

Configure repository Actions secrets `MACOS_CERTIFICATE_P12_BASE64` (exported Developer ID Application certificate with its private key, base64 encoded), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY` (full certificate name), `NOTARY_API_KEY_P8` (App Store Connect team API key contents), `NOTARY_API_KEY_ID`, and `NOTARY_API_ISSUER_ID`. Use a team API key authorized for notarization. Never commit credentials. The workflow imports them into a temporary keychain, stores a notarytool profile there, and removes the keychain and key file after the job, including failures.

Before publishing the draft, download the assets through a browser on a clean Mac and verify Gatekeeper, drag-and-drop installation, permission onboarding, and the applicable [compatibility checks](compatibility.md). Test both supported processor architectures before claiming both were observed. Update `docs/installation.md`, README, changelog, and release notes to reflect actual publication and verification. The draft's source archive preserves the exact bundled dictionary data and transformation sources alongside their licenses. Publication is a separate maintainer action.

## Observed signing verification

The first signed [GitHub workflow run](https://github.com/ywdagency/typeswitch/actions/runs/38344410461) completed successfully and created the unpublished 0.1.0 build 1 candidate. Apple accepted both the app ZIP and DMG. The initial app submission took about 32 minutes; the image submission then completed in under a minute. Workflow credentials were removed successfully.

On 2026-10-13, the candidate downloaded through the GitHub CLI passed local checksum, app/image signature and ticket validation, Gatekeeper assessment, architecture, metadata, resource, attribution, and installation-shortcut checks. This did not launch or install the app and does not establish a clean-Mac browser-download result, permission onboarding, Intel execution, or broader editor compatibility. Build 2 refreshes the packaged instructions and runs the reusable content verifier before replacing the unpublished candidate.
