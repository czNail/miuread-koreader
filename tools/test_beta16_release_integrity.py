"""Real source contract: single release heading and no ignored historical duplicates."""
import re
import sys
import unittest
from pathlib import Path
TOOLS = Path(__file__).resolve().parent
sys.path.insert(0,str(TOOLS))
from changelog_integrity import normalize_changelog, VERSION_ENTRY
ROOT=TOOLS.parent

class Integrity(unittest.TestCase):
    def test_full_changelog_is_normalized_and_single_heading(self):
        source=(ROOT/'CHANGELOG.md').read_text(encoding='utf-8')
        self.assertEqual(normalize_changelog(source),source)
        self.assertEqual(source.count('# Changelog'),1)
        self.assertEqual(source.count('## 6.1.0-beta.14 - UX'),1)
        self.assertEqual(source.count('## 6.1.0-beta.15 - Public'),1)
        self.assertEqual(source.count('## 6.1.0-beta.16 - Beta release'),1)
        heads=[VERSION_ENTRY.fullmatch(x.strip()) for x in source.splitlines() if x.startswith('## ')]
        versions=[x.group('version') for x in heads if x is not None]
        self.assertEqual(len(versions),len(set(versions)))

    def test_metadata_exactly_matches_package_version(self):
        a=(ROOT/'miuread.koplugin/_meta.lua').read_text(encoding='utf-8')
        b=(ROOT/'miuread.koplugin/miuread/config.lua').read_text(encoding='utf-8')
        import re
        a_version=re.search(r'version\s*=\s*"([^"]+)"',a)
        b_version=re.search(r'VERSION\s*=\s*"([^"]+)"',b)
        self.assertIsNotNone(a_version)
        self.assertIsNotNone(b_version)
        self.assertRegex(a_version.group(1), r'^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$')
        self.assertEqual(a_version.group(1),b_version.group(1))
        self.assertIn('## '+a_version.group(1), (ROOT/'CHANGELOG.md').read_text(encoding='utf-8'))

    def test_beta15_comment_hotfix_preserved(self):
        annotations=(ROOT/'miuread.koplugin/miuread/annotations.lua').read_text(encoding='utf-8')
        api=(ROOT/'miuread.koplugin/miuread/api_web.lua').read_text(encoding='utf-8')
        self.assertIn('mark_batch_completed(batch)',annotations)
        self.assertIn('missing review list',annotations)
        self.assertIn('_agent_readreviews',api)

if __name__ == '__main__': unittest.main()
