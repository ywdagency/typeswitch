#!/usr/bin/env python3
"""Verify a release image without installing or launching the application."""

import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


class VerificationError(Exception):
    pass


def verify_checksum(dmg: Path) -> None:
    checksum = Path(str(dmg) + ".sha256").read_text().strip()
    match = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", checksum)
    if match is None or match[2] != dmg.name:
        raise VerificationError("Checksum must name exactly the supplied DMG.")
    with dmg.open("rb") as source:
        hasher = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(chunk)
        digest = hasher.hexdigest()
    if digest != match[1].lower():
        raise VerificationError("DMG SHA-256 checksum does not match.")


def verify_contents(image: Path, source: Path, version: str, build: str, preview: bool) -> Path:
    app = image / "TypeSwitch.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {
        "CFBundleIdentifier": "com.dmvishnyak.typeswitch",
        "CFBundleExecutable": "TypeSwitch",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "LSMinimumSystemVersion": "15.0",
        "LSUIElement": True,
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise VerificationError(f"Unexpected app metadata: {key}.")
    if not (image / "Applications").is_symlink() or os.readlink(image / "Applications") != "/Applications":
        raise VerificationError("The Applications installation shortcut is missing or incorrect.")
    if not (image / "Read Me.md").is_file():
        raise VerificationError("Installation instructions are missing.")
    if (image / "Read Me.md").read_bytes() != (source / "docs/installation.md").read_bytes():
        raise VerificationError("Installation instructions differ from source.")
    if (image / "PREVIEW.txt").exists() != preview:
        raise VerificationError("Preview label does not match the verification mode.")
    resources = app / "Contents/Resources"
    bundle = resources / "TypeSwitch_TypeSwitchApp.bundle"
    if not (resources / "AppIcon.icns").is_file() or not bundle.is_dir():
        raise VerificationError("App resources are missing.")
    for name in ("english.txt", "russian.txt", "ukrainian.txt"):
        if not any(path.is_file() and path.stat().st_size > 0 for path in bundle.rglob(name)):
            raise VerificationError(f"Bundled dictionary is missing: {name}.")
    legal = resources / "Legal"
    notices = [Path("LICENSE"), Path("docs/third-party-notices.md")]
    notices += [path.relative_to(source) for path in (source / "LICENSES").rglob("*") if path.is_file()]
    for notice in notices:
        if (legal / notice).read_bytes() != (source / notice).read_bytes():
            raise VerificationError(f"Bundled license notice differs from source: {notice}.")
    revision = subprocess.run(
        ["git", "-C", str(source), "rev-parse", "HEAD"], check=True, capture_output=True, text=True
    ).stdout.strip()
    provenance = (legal / "SOURCE.txt").read_text()
    if f"Build revision: {revision}\n" not in provenance:
        raise VerificationError("App provenance does not match the checked-out source revision.")
    return app


def run(*args: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise VerificationError(f"{args[0]} failed:\n{result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dmg", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--preview", action="store_true", help="Check an ad-hoc preview without notarization requirements.")
    parser.add_argument("--source-dir", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    dmg = args.dmg.resolve()
    try:
        verify_checksum(dmg)
        run("hdiutil", "verify", str(dmg))
        if not args.preview:
            run("codesign", "--verify", "--strict", str(dmg))
            run("xcrun", "stapler", "validate", str(dmg))
            run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", str(dmg))
        with tempfile.TemporaryDirectory(prefix="typeswitch-image-check-") as mount:
            run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, str(dmg))
            try:
                app = verify_contents(Path(mount), args.source_dir, args.version, args.build_number, args.preview)
                run("codesign", "--verify", "--deep", "--strict", str(app))
                for architecture in ("arm64", "x86_64"):
                    run("lipo", str(app / "Contents/MacOS/TypeSwitch"), "-verify_arch", architecture)
                if not args.preview:
                    signature = run("codesign", "-dvvv", str(app))
                    if "Authority=Developer ID Application:" not in signature or "runtime" not in signature or "Timestamp=" not in signature:
                        raise VerificationError("Expected Developer ID signing, hardened runtime, and a secure timestamp.")
                    run("xcrun", "stapler", "validate", str(app))
                    run("spctl", "--assess", "--type", "execute", str(app))
            finally:
                run("hdiutil", "detach", mount)
    except (VerificationError, OSError, ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(1, f"DMG verification failed: {error}\n")
    signing = "preview signature" if args.preview else "Developer ID signatures, tickets, and Gatekeeper"
    print(f"Verified {dmg.name}: checksum, metadata, source revision, resources, licenses, both architectures, and {signing}.")


if __name__ == "__main__":
    main()
