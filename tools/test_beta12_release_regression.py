#!/usr/bin/env python3
"""Release safety invariants that do not require a GitHub network call."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BETA = (ROOT / ".github/workflows/release-beta.yml").read_text(encoding="utf-8")
STABLE = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")

class ReleaseSafetyTest(unittest.TestCase):
    def test_lua_module_path_and_executable_contract(self):
        self.assertIn('LUA_PATH: "./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;;"', BETA)
        for name in ('test_beta11_download_resume_policy.lua', 'test_beta11_resume_coordinator.lua'):
            text = (ROOT / 'tools' / name).read_text(encoding='utf-8')
            self.assertIn('package.path="./miuread.koplugin/?.lua;./miuread.koplugin/?/init.lua;"..package.path', text)
            self.assertIn('lua5.1 tools/' + name, BETA)
            self.assertIn('luajit tools/' + name, BETA)

    def test_release_tag_after_testing_and_immutable(self):
        self.assertNotIn('git tag -f', STABLE)
        self.assertNotIn('git push --force origin "refs/tags/', STABLE)
        self.assertLess(STABLE.index('name: Verify stable package and manifest'), STABLE.index('name: Commit stable identity and ensure immutable tag'))
        self.assertLess(BETA.index('name: Verify beta package and manifest'), BETA.index('name: Create or update beta prerelease'))

    def test_beta_remains_two_entrypoints_and_no_tag_rewrites(self):
        self.assertIn('  workflow_dispatch:', BETA)
        self.assertIn('  push:', BETA)
        self.assertNotIn('git push --force', BETA)
        self.assertIn('EXISTING_TAG_SHA', BETA)

if __name__ == '__main__':
    unittest.main()
