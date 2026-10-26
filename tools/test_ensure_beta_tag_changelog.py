"""Tests for beta tag release changelog auto-completion."""
import tempfile
import unittest
from pathlib import Path
from ensure_beta_tag_changelog import ensure_changelog


class ChangelogTagReleaseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.file = self.root / "CHANGELOG.md"

    def test_existing_correct_entry_not_rewritten(self):
        value = "# Changelog\n\n## 6.1.0-beta.7 — Fix\n\n- existing notes\n"
        self.file.write_text(value)
        self.assertFalse(ensure_changelog(self.root, "6.1.0-beta.7", "commit title"))
        self.assertEqual(self.file.read_text(), value)

    def test_tag_without_entry_auto_generates(self):
        self.file.write_text("# Changelog\n\n## 6.1.0-beta.6\n\n- old notes\n")
        self.assertTrue(ensure_changelog(self.root, "6.1.0-beta.7", "release summary"))
        out=self.file.read_text()
        self.assertIn("## 6.1.0-beta.7 - Beta Update\n\n- release summary",out)
        self.assertIn("## 6.1.0-beta.6",out)
        self.assertFalse(ensure_changelog(self.root, "6.1.0-beta.7", "release summary"))

    def test_legacy_heading_is_corrected_without_losing_notes(self):
        self.file.write_text("## v6.1.0-beta.7 — Bugfix\n\n- real notes\n\n# Changelog\n\n## 6.1.0-beta.6\n\n- old notes\n")
        self.assertTrue(ensure_changelog(self.root, "6.1.0-beta.7", "ignored commit"))
        value=self.file.read_text()
        self.assertTrue(value.startswith("# Changelog\n"))
        self.assertIn("## 6.1.0-beta.7 — Bugfix", value)
        self.assertIn("- real notes", value)
        self.assertNotIn("## v6.1.0-beta.7", value)
        self.assertFalse(ensure_changelog(self.root, "6.1.0-beta.7", "ignored"))

    def test_duplicates_raise(self):
        self.file.write_text("# Changelog\n\n## 6.1.0-beta.7\n- x\n## v6.1.0-beta.7\n- y\n")
        with self.assertRaisesRegex(ValueError,"Duplicate"):
            ensure_changelog(self.root, "6.1.0-beta.7", "commit")

    def test_heading_without_bullets_raise(self):
        self.file.write_text("# Changelog\n\n## 6.1.0-beta.7\n\n")
        with self.assertRaisesRegex(ValueError,"bullet"):
            ensure_changelog(self.root, "6.1.0-beta.7", "commit")


if __name__ == "__main__":
    unittest.main()
