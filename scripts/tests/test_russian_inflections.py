import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from russian_inflections import parse_bases, parse_suffix_rules


class RussianInflectionGeneratorTests(unittest.TestCase):
    def test_preserves_flags_and_excludes_proper_names(self):
        self.assertEqual(
            parse_bases("5\nкопирование/J\nслово/K\nслово/J\nМосква/I\nтест\n", {"J", "K", "I"}),
            [("копирование", "J"), ("слово", "JK")],
        )

    def test_preserves_conditions_and_zero_endings(self):
        self.assertEqual(
            parse_suffix_rules("SET UTF-8\nSFX J Y 2\nSFX J е ем ие\nSFX J е 0 [^ц]е\n"),
            [("J", "е", "0", "[^ц]е"), ("J", "е", "ем", "ие")],
        )

    def test_rejects_unsupported_features_and_incomplete_rules(self):
        for content in [
            "PFX A Y 1\nPFX A 0 по .\n",
            "SFX J Y 1\nSFX J е ем/K ие\n",
            "SFX J Y 2\nSFX J е ем ие\n",
            "SFX J Y 1\nSFX J е ем (ие|ье)\n",
            "FLAG long\n",
        ]:
            with self.subTest(content=content), self.assertRaises(ValueError):
                parse_suffix_rules(content)
        with self.assertRaises(ValueError):
            parse_bases("1\nкопирование/JK\n", {"J"})


if __name__ == "__main__":
    unittest.main()
