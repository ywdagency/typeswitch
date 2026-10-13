import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class NotarizationRetryTests(unittest.TestCase):
    def run_stapler(self, failures, code):
        with tempfile.TemporaryDirectory(prefix="typeswitch-stapler-test-") as temp:
            root = Path(temp)
            (root / "xcrun").write_text('''#!/bin/bash
test "$1" = stapler && test "$2" = staple || exit 64
count=0
if [[ -f "$COUNT_FILE" ]]; then count="$(cat "$COUNT_FILE")"; fi
count=$((count + 1))
printf '%s' "$count" > "$COUNT_FILE"
printf '%s' "$3" > "$TARGET_FILE"
if [[ "$count" -le "$FAILURES" ]]; then exit "$FAILURE_CODE"; fi
''')
            (root / "sleep").write_text('#!/bin/bash\nprintf "%s\\n" "$1" >> "$DELAY_FILE"\n')
            for name in ("xcrun", "sleep"):
                (root / name).chmod(0o755)
            helper = Path(__file__).resolve().parents[1] / "lib/notarization.sh"
            env = dict(
                os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                FAILURES=str(failures), FAILURE_CODE=str(code), COUNT_FILE=str(root / "count"),
                TARGET_FILE=str(root / "target"), DELAY_FILE=str(root / "delays"),
            )
            target = str(root / "TypeSwitch image.dmg")
            result = subprocess.run(
                ["bash", "-c", 'set -euo pipefail; source "$1"; staple_with_retry "$2"', "test", str(helper), target],
                env=env, capture_output=True, text=True,
            )
            self.assertEqual((root / "target").read_text(), target)
            delays = (root / "delays").read_text().splitlines() if (root / "delays").exists() else []
            return result.returncode, int((root / "count").read_text()), delays

    def test_success_and_transient_ticket_failures(self):
        self.assertEqual(self.run_stapler(0, 68), (0, 1, []))
        self.assertEqual(self.run_stapler(2, 68), (0, 3, ["5", "10"]))

    def test_stops_after_three_ticket_failures(self):
        self.assertEqual(self.run_stapler(10, 68), (68, 3, ["5", "10"]))

    def test_does_not_retry_invalid_or_revoked_tickets(self):
        for code in (65, 66, 77):
            with self.subTest(code=code):
                self.assertEqual(self.run_stapler(10, code), (code, 1, []))


if __name__ == "__main__":
    unittest.main()
