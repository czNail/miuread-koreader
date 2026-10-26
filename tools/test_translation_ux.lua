local TOOL_DIR=tostring(arg and arg[0] or ''):gsub('\\','/'):match('^(.*)/[^/]+$') or '.'
local ROOT=TOOL_DIR..'/../miuread.koplugin/'
package.path=TOOL_DIR..'/?.lua;'..ROOT..'?.lua;'..package.path
local UX=require('miuread.translation_ui')
local DownloadResult=require('miuread.download_result')
assert(DownloadResult.shelf_status({translation_mode='original'},true)=='译文待应用')
assert(DownloadResult.notice('Book',{translation_mode='bilingual'},true):find('应用',1,true))
local function copy(value)
    if type(value)~='table' then return value end
    local out={}; for key,item in pairs(value) do out[key]=copy(item) end; return out
end
local record={file='book.epub',variant='clean',chapter_map={{uid='1'},{uid='2'},{uid='3',structural=true}}}
local empty={blocks=0,chapters={}}
local partial={blocks=1,chapters={{chapter_uid='1',blocks=1}}}
local full={blocks=2,chapters={{chapter_uid='1',blocks=1},{chapter_uid='2',blocks=1}}}
local state=UX.describe(empty,record)
assert(state.kind=='idle' and state.primary.label=='下载整本译文' and state.more)
state=UX.describe(partial,record)
assert(state.available==1 and state.total==2 and state.primary.label=='补齐整本译文')
state=UX.describe(full,record)
assert(state.kind=='complete' and not state.more and state.primary.enabled==false)
local range=copy(record); range.partial_range=true
assert(UX.describe(empty,range).primary.label=='下载这些章节的译文')
local staged=copy(record); staged.pending_install=true; staged.pending_file='new.epub'; staged.translation_mode='bilingual'
assert(UX.describe(partial,staged).primary.action=='apply')
staged.translation_mode=nil
assert(UX.describe(partial,staged).primary.action=='manage')
assert(UX.describe(empty,record,{status='active',activity='translation_wait'}).primary.value=='正在准备译文')
assert(UX.describe(empty,record,{status='active',activity='translation_wait',translation_current=2,translation_total=30}).primary.value=='准备第 2 / 30 章')
assert(UX.describe(empty,record,{status='active',percent=.25}).primary.value=='已完成 25%')
assert(UX.describe(empty,record,{status='active',paused=true}).primary.action=='resume')
assert(UX.describe(empty,record,{status='failed',error_kind='network'}).primary.action=='retry')
assert(UX.describe(empty,record,{status='queued'}).primary.action=='manage')
assert(UX.describe(empty,record,{status='failed',error='[MiuReadTranslationMemberRequired]'}).kind=='unavailable')
assert(UX.describe(empty,record,{status='failed',error='[MiuReadTranslationUnsupported]'}).primary.action=='manage')

local Plugin={}
local env=setmetatable({Plugin=Plugin,U={copy=copy,file_exists=function(path) return path~=nil and path~='missing' end},
    logger={warn=function() end}}, {__index=_G})
require('translation_test_support').load_plugin_methods(ROOT,{
    '_reader_translation_record','_reader_translation_context','_reader_translation_download_action',
    '_apply_reader_translation_update'},env)
local current={book={book_id='book'},variant='clean',record=record}
local messages,notices,downloads,managed,resumed={}, {},0,0,0
local saved=record
local plugin=setmetatable({
    _current_book_record=function() return current end,
    store={variant=function() return saved end,download_state=function() return {} end,download_queue=function() return {} end},
    info=function(_,message) messages[#messages+1]=message end,
    toast=function(_,message) notices[#notices+1]=message end,status_toast=function() end,
    show_download_status=function() managed=managed+1; return true end,
    _request_reader_translation_mode=function(_,mode,ahead,batch)
        downloads=downloads+1; assert(mode=='original' and ahead and batch=='all'); return true
    end,
}, {__index=Plugin})
local context=plugin:_reader_translation_context(empty)
assert(plugin:_reader_translation_download_action(context,'original') and downloads==1)
plugin._download_runtime={book={bookId='other'},options={generate_translation_uid='1',active_document_path='other.epub'}}
plugin.download_task={busy=function() return true end,is_paused=function() return false end}
context=plugin:_reader_translation_context(empty)
assert(context.task==nil and context.state.primary.label=='加入下载队列','another book hijacked translation controls')
plugin._download_runtime={book={bookId='book'},options={generate_translation_uid='1',active_document_path='book.epub'},
    last_state={percent=.4}}
plugin._download_runtime.options.active_document_path='other.epub'
plugin._download_runtime.options.translation_target_file='book.epub'
context=plugin:_reader_translation_context(empty)
assert(context.state.kind=='downloading' and not context.state.more)
assert(plugin:_reader_translation_download_action(context,'original') and managed==1 and downloads==1)
plugin.download_task.is_paused=function() return true end
plugin.download_task.resume=function(_,reason) assert(reason=='manual'); resumed=resumed+1; return true end
context=plugin:_reader_translation_context(empty)
assert(plugin:_reader_translation_download_action(context,'original') and resumed==1 and downloads==1)
plugin.download_task.resume=function() return false end
assert(plugin:_reader_translation_download_action(context,'original') and managed==2,'unsuccessful resume was reported as completed')
plugin._download_runtime=nil; plugin.download_task=nil
plugin.store.download_state=function() return {status='failed',book_id='book',options={generate_translation_uid='1',translation_batch_size='all'}} end
context=plugin:_reader_translation_context(empty)
assert(context.state.kind=='interrupted' and plugin:_reader_translation_download_action(context,'original') and downloads==2)
plugin.store.download_state=function() return {} end
plugin.store.download_queue=function() return {{book={bookId='book'},options={generate_translation_uid='1'}}} end
assert(plugin:_reader_translation_context(empty).state.kind=='queued')
plugin.store.download_queue=function() return {} end

-- A ready update is applied only after the reader has saved its final cursor
-- and released the document. Installation failure must still reopen the book.
saved=copy(record); saved.pending_install=true; saved.pending_file='new.epub'; saved.translation_mode='bilingual'
local installed,reopened,fail_install,fail_close=0,0,false,false
local ui={document={file='book.epub'}}
plugin.ui=ui
plugin._install_pending_record=function(_,book_id,kind,chapter_uid,updated)
    assert(ui.document==nil and ui.settings_saved and book_id=='book' and kind=='clean')
    assert(updated.translation_follow_display and chapter_uid==nil)
    installed=installed+1
    if fail_install then return false,'private internal diagnostics' end
    return true,{translation_display_fallback=plugin.test_fallback}
end
function ui:reloadDocument(after_close,seamless,after_open)
    assert(seamless)
    if fail_close then after_close('book.epub'); after_open(); return end
    self.settings_saved=true
    self.document=nil
    after_close('book.epub')
    self.document={file='book.epub'}
    reopened=reopened+1
    after_open()
end
assert(plugin:_apply_reader_translation_update() and installed==1 and reopened==1)
assert(notices[#notices]=='译文已应用' and not plugin._reader_translation_applying)
fail_install=true
assert(not plugin:_apply_reader_translation_update() and installed==2 and reopened==2)
assert(not messages[#messages]:find('private',1,true),'application failure exposed internal diagnostics')
fail_install=false; fail_close=true
assert(not plugin:_apply_reader_translation_update() and installed==2,'live document was replaced')
assert(ui.document and not plugin._reader_translation_applying)
fail_close=false; plugin.test_fallback=true
assert(plugin:_apply_reader_translation_update() and notices[#notices]:find('双语',1,true),
    'application fallback was silent about changing to bilingual display')
ui.reloadDocument=nil
assert(not plugin:_apply_reader_translation_update() and installed==3,'unsupported reader version replaced the active file')
saved.pending_file='missing'
assert(plugin:_reader_translation_context(empty).state.kind~='ready')
assert(not plugin:_apply_reader_translation_update() and installed==3)
print('Translation UX: contextual actions, offline availability, queue isolation, manual resume and safe one-tap application passed')
