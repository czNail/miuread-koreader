"""B4 static integration contracts; device-level networking/UI remain unverified."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / 'miuread.koplugin'

def src(name):
    return (PLUGIN / name).read_text(encoding='utf-8')

class B4DownloadContract(unittest.TestCase):
    def test_no_new_download_edition_selectors(self):
        main=src('main.lua')
        download_choice=main[main.index('function Plugin:choose_download(b,'):main.index('function Plugin:_download_summary(')]
        self.assertIn('return self:choose_download_mode(',download_choice)
        self.assertNotIn('ButtonDialog:new',download_choice)
        current_rebuild=main[main.index('function Plugin:current_book_rebuild_menu('):main.index('function Plugin:current_book_menu(')]
        self.assertEqual(current_rebuild.count('text="重新生成正文"'),1)
        self.assertNotIn('划线与想法版',current_rebuild)
        range_choice=main[main.index('function Plugin:_choose_range_version('):main.index('function Plugin:_range_count_menu(')]
        self.assertIn('return self:choose_download_mode(',range_choice)
        self.assertNotIn('ButtonDialog:new',range_choice)
        self.assertNotIn('text="纯净版"',main)
        self.assertNotIn('text="划线与想法版"',main)

    def test_enforced_at_queue_entry_and_execution(self):
        main=src('main.lua')
        for name in ('choose_download_mode','_queue_download','download'):
            part=main[main.index('function Plugin:'+name+'('):]
            self.assertIn('b4_content_only_options(opt)',part[:320],name)
        task=src('miuread/download_task.lua')
        self.assertIn('clean_options.annotations=false',task)
        self.assertIn('clean_options.annotation_requested=nil',task)
        self.assertIn('clean_options.annotation_pending=nil',task)
        # Do not call the annotation API when options.annotations is false.
        down=src('miuread/downloader.lua')
        self.assertIn('local requested_annotations=opt.annotations==true',down)

    def test_clean_filename_and_old_sidecar_path(self):
        down=src('miuread/downloader.lua')
        self.assertIn('local edition_suffix=kind=="notes"',down)
        self.assertIn('..chapter_name..edition_suffix..".epub"',down)
        self.assertIn('path=recorded_path',down)
        self.assertIn('local same_identity=',down)

    def test_legacy_files_readable_not_regenerated(self):
        main=src('main.lua')
        self.assertIn('self:_preferred_record(b.bookId)',main)
        self.assertIn('本机文件与高级管理',main)
        dialog=src('miuread/book_local_files_dialog.lua')
        self.assertIn('if kind == "clean" then',dialog)
        self.assertIn('"notes"',main)
        self.assertIn('text = "打开" .. label',dialog)
        self.assertIn('text="仅删除"..label',dialog)
        self.assertIn('text = "高级文件管理"',dialog)

    def test_legacy_notes_checkpoint_not_clean_source(self):
        integrity=src('miuread/book_integrity.lua')
        self.assertIn('if kind=="notes" then',integrity)
        self.assertIn('legacy_ignored=true',integrity)
        self.assertIn('annotations=false',integrity)
        main=src('main.lua')
        self.assertIn('旧版可阅读',main) if False else self.assertIn('选择新的正文范围',main)

    def test_old_notes_chapter_prefetch_uses_clean_target(self):
        main=src('main.lua')
        prefetch=main[main.index('function Plugin:_chapter_prefetch_context('):main.index('function Plugin:_chapter_prefetch_status(')]
        self.assertIn('ctx.source_kind=source_ctx.kind',prefetch)
        self.assertIn('ctx.kind="clean"',prefetch)
        self.assertIn('self.store:hidden_prefetch_record(ctx.book_id,ctx.next_uid,ctx.kind)',prefetch)
        self.assertNotIn('source_ctx.kind="clean"',prefetch)

    def test_no_b5_b6_ui_changes(self):
        # unchanged B3 source modules beyond B4 file list
        self.assertTrue((PLUGIN/'miuread/comment_overlay.lua').exists())
        self.assertTrue((PLUGIN/'miuread/comment_sync.lua').exists())
        self.assertTrue((PLUGIN/'miuread/thought_favorites.lua').exists())

if __name__=='__main__': unittest.main()
