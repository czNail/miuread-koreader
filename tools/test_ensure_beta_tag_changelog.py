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

    def test_identical_duplicate_target_sections_are_auto_merged(self):
        body = "## 6.1.0-beta.7 - Fix\n\n- unchanged\n\n"
        self.file.write_text("# Changelog\n\n" + body + "# Changelog\n\n" + body + "## 6.1.0-beta.6\n\n- old\n",encoding="utf-8")
        self.assertTrue(ensure_changelog(self.root, "6.1.0-beta.7", "commit"))
        value = self.file.read_text()
        self.assertEqual(value.count("## 6.1.0-beta.7 - Fix"), 1)
        self.assertEqual(value.count("# Changelog"), 1)
        self.assertIn("## 6.1.0-beta.6",value)
        self.assertFalse(ensure_changelog(self.root, "6.1.0-beta.7", "commit"))

    def test_duplicated_historical_release_does_not_block_new_tag(self):
        old = "## 6.1.0-beta.6 - Old\n\n- preserved\n\n"
        self.file.write_text("# Changelog\n\n" + old + old, encoding="utf-8")
        self.assertTrue(ensure_changelog(self.root, "6.1.0-beta.7", "new release"))
        value=self.file.read_text()
        self.assertEqual(value.count("## 6.1.0-beta.6"),1)
        self.assertIn("## 6.1.0-beta.7 - Beta Update", value)

    def test_duplicate_conflict_reports_lines_and_preserves_original(self):
        source = "# Changelog\n\n## 6.1.0-beta.7\n- first\n## 6.1.0-beta.7\n- second\n"
        self.file.write_text(source,encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Conflicting.*lines 3 and 5"):
            ensure_changelog(self.root, "6.1.0-beta.7", "commit")
        self.assertEqual(self.file.read_text(), source)

    def test_duplicates_raise(self):
        self.file.write_text("# Changelog\n\n## 6.1.0-beta.7\n- x\n## v6.1.0-beta.7\n- y\n")
        with self.assertRaisesRegex(ValueError,"Conflicting"):
            ensure_changelog(self.root, "6.1.0-beta.7", "commit")

    def test_heading_without_bullets_raise(self):
        self.file.write_text("# Changelog\n\n## 6.1.0-beta.7\n\n")
        with self.assertRaisesRegex(ValueError,"bullet"):
            ensure_changelog(self.root, "6.1.0-beta.7", "commit")


if __name__ == "__main__":
    unittest.main()
