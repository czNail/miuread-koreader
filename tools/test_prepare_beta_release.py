#!/usr/bin/env python3
"""Regression tests for the manual beta-release metadata preparer."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_beta_release import prepare  # noqa: E402


class PrepareBetaReleaseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "miuread.koplugin/miuread").mkdir(parents=True)
        self.config = self.root / "miuread.koplugin/miuread/config.lua"
        self.meta = self.root / "miuread.koplugin/_meta.lua"
        self.changelog = self.root / "CHANGELOG.md"
        self.config.write_text('local C = {\n  VERSION = "6.0.0-beta.1",\n  UPDATE_CHANNEL = "beta",\n}\n', encoding="utf-8")
        self.meta.write_text('return {\n    version = "6.0.0-beta.1",\n}\n', encoding="utf-8")
        self.changelog.write_text('## 6.0.0-beta.1 - Baseline\n\n- 基线\n', encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def test_prepares_and_preserves_history(self):
        changed = prepare(self.root, "6.0.1-beta.2", "修复书架刷新 | 保留阅读进度")
        self.assertTrue(changed)
        self.assertIn('VERSION = "6.0.1-beta.2"', self.config.read_text())
        self.assertIn('version = "6.0.1-beta.2"', self.meta.read_text())
        log = self.changelog.read_text()
        self.assertTrue(log.startswith("## 6.0.1-beta.2 - Beta Update\n"))
        self.assertIn("- 修复书架刷新\n- 保留阅读进度", log)
        self.assertIn("## 6.0.0-beta.1 - Baseline", log)

    def test_rerun_is_idempotent(self):
        prepare(self.root, "6.0.1-beta.2", "修复书架刷新")
        before = [f.read_bytes() for f in (self.config, self.meta, self.changelog)]
        self.assertFalse(prepare(self.root, "6.0.1-beta.2", "修复书架刷新"))
        self.assertEqual(before, [f.read_bytes() for f in (self.config, self.meta, self.changelog)])

    def test_existing_version_notes_cannot_be_rewritten(self):
        prepare(self.root, "6.0.1-beta.2", "修复书架刷新")
        with self.assertRaisesRegex(ValueError, "不一致"):
            prepare(self.root, "6.0.1-beta.2", "不同的更新说明")

    def test_rejects_rollback_and_invalid_version(self):
        with self.assertRaisesRegex(ValueError, "版本回退"):
            prepare(self.root, "5.9.0-beta.1", "回退")
        with self.assertRaisesRegex(ValueError, "无效的 Beta"):
            prepare(self.root, "not-a-version", "无效")

    def test_rejects_empty_notes_without_writing(self):
        before = self.config.read_bytes()
        with self.assertRaisesRegex(ValueError, "不能为空"):
            prepare(self.root, "6.0.1-beta.2", "  ")
        self.assertEqual(before, self.config.read_bytes())

    def test_rejects_mismatched_versions(self):
        self.meta.write_text('return {\n    version = "6.0.0-beta.2",\n}\n', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "源码版本"):
            prepare(self.root, "6.0.1-beta.2", "修复")

    def test_preserves_changelog_top_heading(self):
        self.changelog.write_text('# Changelog\n\n' + self.changelog.read_text(), encoding="utf-8")
        prepare(self.root, "6.0.1-beta.2", "修复")
        self.assertTrue(self.changelog.read_text().startswith('# Changelog\n\n## 6.0.1-beta.2'))


if __name__ == "__main__":
    unittest.main()
