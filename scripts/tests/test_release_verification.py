import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("verify_dmg", Path(__file__).resolve().parents[1] / "verify-dmg.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class ReleaseChecksumTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dmg = Path(self.temp.name) / "TypeSwitch image.dmg"
        self.dmg.write_bytes(b"fixture image")
        self.checksum = Path(str(self.dmg) + ".sha256")
        self.digest = hashlib.sha256(self.dmg.read_bytes()).hexdigest()
        self.checksum.write_text(f"{self.digest}  {self.dmg.name}\n")

    def test_accepts_exact_image_including_spaces_in_name(self):
        verifier.verify_checksum(self.dmg)

    def test_refuses_changed_image(self):
        self.dmg.write_bytes(b"changed image")
        with self.assertRaises(verifier.VerificationError):
            verifier.verify_checksum(self.dmg)

    def test_refuses_redirected_or_malformed_checksums(self):
        for content in (
            f"{self.digest}  ../another.dmg\n",
            f"{self.digest}  {self.dmg.name}\n{self.digest}  another.dmg\n",
            "not a checksum\n",
        ):
            with self.subTest(content=content), self.assertRaises(verifier.VerificationError):
                self.checksum.write_text(content)
                verifier.verify_checksum(self.dmg)


class ReleaseImageContentsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "source"
        self.image = root / "image"
        self.resources = self.image / "TypeSwitch.app/Contents/Resources"
        self.info = self.resources.parent / "Info.plist"
        self.bundle = self.resources / "TypeSwitch_TypeSwitchApp.bundle"
        self.bundle.mkdir(parents=True)
        self.metadata = {
            "CFBundleIdentifier": "com.dmvishnyak.typeswitch",
            "CFBundleExecutable": "TypeSwitch",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "15.0",
            "LSUIElement": True,
        }
        self.info.write_bytes(plistlib.dumps(self.metadata))
        (self.image / "Applications").symlink_to("/Applications")
        (self.image / "Read Me.md").write_text("Installation instructions")
        (self.source / "docs").mkdir(parents=True)
        (self.source / "docs/installation.md").write_text("Installation instructions")
        (self.resources / "AppIcon.icns").write_bytes(b"icon")
        for name in ("english.txt", "russian.txt", "ukrainian.txt"):
            (self.bundle / name).write_text("fixture dictionary")
        for name in ("LICENSE", "docs/third-party-notices.md", "LICENSES/dictionary-license.txt"):
            for base in (self.source, self.resources / "Legal"):
                path = base / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture notice: " + name)
        (self.resources / "Legal/SOURCE.txt").write_text("Build revision: fixture-revision\n")
        git = patch.object(verifier.subprocess, "run", return_value=SimpleNamespace(stdout="fixture-revision\n"))
        git.start()
        self.addCleanup(git.stop)

    def verify(self, preview=False):
        return verifier.verify_contents(self.image, self.source, "0.1.0", "1", preview)

    def test_accepts_complete_image(self):
        self.assertEqual(self.verify(), self.image / "TypeSwitch.app")

    def test_refuses_wrong_app_identity_version_or_build(self):
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            with self.subTest(key=key), self.assertRaises(verifier.VerificationError):
                self.info.write_bytes(plistlib.dumps({**self.metadata, key: "wrong"}))
                self.verify()

    def test_refuses_changed_instructions_license_or_missing_dictionary(self):
        instructions = self.image / "Read Me.md"
        original_instructions = instructions.read_bytes()
        instructions.write_text("outdated instructions")
        with self.assertRaises(verifier.VerificationError):
            self.verify()
        instructions.write_bytes(original_instructions)
        license_path = self.resources / "Legal/LICENSES/dictionary-license.txt"
        original = license_path.read_bytes()
        license_path.write_text("modified notice")
        with self.assertRaises(verifier.VerificationError):
            self.verify()
        license_path.write_bytes(original)
        (self.bundle / "ukrainian.txt").unlink()
        with self.assertRaises(verifier.VerificationError):
            self.verify()

    def test_refuses_incorrect_installation_shortcut(self):
        shortcut = self.image / "Applications"
        shortcut.unlink()
        shortcut.symlink_to("/tmp")
        with self.assertRaises(verifier.VerificationError):
            self.verify()

    def test_refuses_different_source_revision(self):
        (self.resources / "Legal/SOURCE.txt").write_text("Build revision: another-revision\n")
        with self.assertRaises(verifier.VerificationError):
            self.verify()

    def test_keeps_preview_and_distribution_labels_distinct(self):
        with self.assertRaises(verifier.VerificationError):
            self.verify(preview=True)
        (self.image / "PREVIEW.txt").write_text("Local preview")
        self.verify(preview=True)
        with self.assertRaises(verifier.VerificationError):
            self.verify()


if __name__ == "__main__":
    unittest.main()
