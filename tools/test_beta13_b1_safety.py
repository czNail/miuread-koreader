#!/usr/bin/env python3
"""B1 safety contracts: no destructive comment refresh, no cloud delete on book removal."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / 'miuread.koplugin'


def source(name):
    return (PLUGIN / name).read_text(encoding='utf-8')


class B1Safety(unittest.TestCase):
    def test_checkpoint_version_is_consistent(self):
        import re
        meta = re.search(r'version\s*=\s*"([^"]+)"', source('_meta.lua'))
        config = re.search(r'VERSION\s*=\s*"([^"]+)"', source('miuread/config.lua'))
        self.assertIsNotNone(meta)
        self.assertIsNotNone(config)
        self.assertEqual(meta.group(1), config.group(1))
        self.assertRegex(meta.group(1), r'^6\.1\.0-beta\.(?:13(?:-B[1-6])?|14)$')

    def test_comments_are_incrementally_merged(self):
        db = source('miuread/thought_database.lua')
        self.assertIn('SCHEMA_VERSION = 4', db)
        self.assertIn('CREATE TABLE IF NOT EXISTS thought_sync_state', db)
        self.assertIn('CREATE TABLE IF NOT EXISTS thought_locations', db)
        self.assertIn('local function merge_chapter(', db)
        self.assertIn('last_success_at', db)
        self.assertIn("status = 'partial'", db)
        self.assertNotIn('DELETE FROM thought_comments WHERE chapter_uid', db)
        self.assertNotIn('DROP TABLE IF EXISTS thought_migration', db)
        self.assertIn('previously_known=was_known', db)

    def test_pre_delete_sync_excludes_remote_delete(self):
        main = source('main.lua')
        sync = source('miuread/annotation_sync.lua')
        self.assertIn('preferences=prefs,limit=200,upload_only=true', main)
        self.assertIn('if options.upload_only == true then', sync)
        self.assertIn('row.sync_state ~= "delete_pending"', sync)
        self.assertIn('row.sync_state ~= "delete_unknown"', sync)
        self.assertIn('upload_only=options.upload_only==true', sync)
        self.assertIn('Apply the filter inside SQL', source('miuread/local_annotation_database.lua'))
        self.assertIn('and options.upload_only == true then', sync)
        self.assertIn('out.remote_deletions', main)
        self.assertIn('summary.held_local', main)

    def test_book_delete_does_not_remove_global_favorites(self):
        deletion = source('miuread/book_delete_service.lua')
        cleanup = source('miuread/cache_cleanup_task.lua')
        store = source('miuread/store.lua')
        favorites = source('miuread/thought_favorites.lua')
        self.assertIn('self.store:book_cache_path(book_id)', deletion)
        self.assertIn('self.store:forget_book_local_state(plan.book_id)', deletion)
        self.assertIn('独立评论收藏受保护', cleanup)
        self.assertIn('self:forget_book_local_state(key)', store)
        self.assertIn('tostring(store.data_dir)', favorites)
        self.assertNotIn('ThoughtFavorites.remove', deletion)
        self.assertNotIn('ThoughtFavorites.remove', store)

    def test_download_resume_and_release_workflows_untouched(self):
        self.assertTrue((ROOT / '.github/workflows/release-beta.yml').exists())
        self.assertTrue((ROOT / '.github/workflows/release.yml').exists())
        self.assertTrue((PLUGIN / 'miuread/download_task.lua').exists())


if __name__ == '__main__':
    unittest.main()
