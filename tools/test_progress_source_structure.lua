-- Run on KOReader from its directory:
--   ./luajit <repo>/tools/test_progress_source_structure.lua <repo>/miuread.koplugin [original source_position.lua]
-- Title-only chapters and empty placeholder sources must not block progress
-- conversion. Uses real cache files in a temporary directory; network is stubbed.
require('setupkoenv')
local plugin=assert(arg[1],'plugin path required')
package.path=plugin..'/?.lua;'..package.path
local S=require('miuread.source_position')
local P=require('miuread.precise_position')
local Original=arg[2] and assert(loadfile(arg[2]))() or nil

local TMP='/mnt/us/miuread-backups/test-progress-source-'..tostring(os.time())
local CACHE=TMP..'/book/progress-source-position'
os.execute("mkdir -p '"..CACHE.."' '"..TMP.."/temp'")
local function write(path,data) local f=assert(io.open(path,'wb')); f:write(data); f:close() end
local function read(path) local f=io.open(path,'rb'); if not f then return nil end local d=f:read('*a'); f:close(); return d end
local function xhtml(body)
    return '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title/></head><body>'..body..'</body></html>'
end
local real=xhtml('<h2>第五章 归来</h2><p>春天的风吹过山谷，她终于回到了那座熟悉的小镇。</p><p>街角的面包店还在，门口的铃铛轻轻作响。</p>')
local placeholder='<div class="miu-part-page" data-miuread-structure="1"><h1 class="miu-part-title">第五章 归来</h1></div>'

local network_calls,network_reply=0,nil
local reader={
    store={book_dir=function() return TMP..'/book' end,temp_dir=TMP..'/temp'},
    chapter=function()
        network_calls=network_calls+1
        if not network_reply then error('network disabled') end
        return network_reply,nil,nil,{coord_html=network_reply}
    end,
}
local record={book={book_id='9'},record={}}
local function anchor(extra)
    local a={
        chapter_uid='5',chapter_index=5,chapter_title='第五章 归来',
        chapter_word_count=40,total_word_count=400,words_before=100,book_version=0,
        anchor_text='她终于回到了那座熟悉的小镇',context_before='春天的风吹过山谷，',context_after='。',
        point_side='start',anchor_kind='forward_12',xpointer='/body/DocFragment[5]/body/p[1]/text().9',
    }
    for k,v in pairs(extra or {}) do a[k]=v end
    return a
end
local function reset()
    os.execute("rm -f '"..CACHE.."'/*")
    network_calls,network_reply=0,nil
end

local function run()
    -- 1. A stale placeholder at the exact path no longer hides a valid source
    --    cached under another book version.
    reset()
    write(CACHE..'/5-v0.xhtml',placeholder)
    write(CACHE..'/5-v123.xhtml',real)
    local pos,err=S.locate(reader,record,anchor(),{cache_only=true})
    assert(pos,'stale placeholder still blocks the valid source: '..tostring(err))
    assert(pos.source_cache_kind=='legacy_verified' and pos.native_offset==true,'unexpected source '..tostring(pos.source_cache_kind))
    local expected_co=pos.offset
    if Original then
        local old=Original.locate(reader,record,anchor(),{cache_only=true})
        assert(old==nil,'original module unexpectedly resolved the placeholder case')
    end

    -- 2. A valid exact cache resolves exactly as before, to the same offset.
    reset()
    write(CACHE..'/5-v0.xhtml',real)
    pos=assert(S.locate(reader,record,anchor(),{cache_only=true}))
    assert(pos.source_cache_kind=='exact' and pos.offset==expected_co,'exact cache path changed')
    if Original then
        local old=assert(Original.locate(reader,record,anchor(),{cache_only=true}))
        assert(old.offset==pos.offset and old.chapter_uid==pos.chapter_uid and old.progress==pos.progress,'exact result differs from original')
    end

    -- 3. Only a placeholder cached: cache-only reports a missing source; the
    --    network placeholder is used for this call but never persisted.
    reset()
    write(CACHE..'/5-v0.xhtml',placeholder)
    pos,err=S.locate(reader,record,anchor(),{cache_only=true})
    assert(not pos and err=='source_cache_missing','placeholder-only cache: '..tostring(err))
    os.remove(CACHE..'/5-v0.xhtml')
    network_reply=placeholder
    pos,err=S.locate(reader,record,anchor(),{})
    assert(not pos and network_calls>=1,'placeholder network reply resolved a position')
    assert(read(CACHE..'/5-v0.xhtml')==nil,'empty placeholder from the network was cached')
    network_reply=real
    pos=assert(S.locate(reader,record,anchor(),{}),'real network source failed')
    assert(pos.offset==expected_co and read(CACHE..'/5-v0.xhtml')==real,'real network source was not cached')

    -- 4. A placeholder that does contain the anchor (a real part page) is used.
    reset()
    write(CACHE..'/5-v0.xhtml',placeholder)
    pos,err=S.locate(reader,record,anchor({anchor_text='第五章 归来',context_before='',context_after=''}),{cache_only=true})
    assert(pos and pos.source_cache_kind=='exact','matching part page was skipped: '..tostring(err))

    -- 5. Title-only local chapter: exact chapter start, no source needed.
    reset()
    pos=assert(S.locate(reader,record,anchor({chapter_title_only=true,anchor_text='第五章 归来第六章'}),{cache_only=true}))
    assert(pos.chapter_uid=='5' and pos.offset==0 and pos.chapter_offset==0,'title-only offset')
    assert(pos.native_offset==true and pos.offset_basis=='wr_data_co' and pos.safe==true,'title-only basis')
    assert(math.abs(pos.progress-25)<1e-9,'title-only progress '..tostring(pos.progress))
    assert(network_calls==0,'title-only chapter fetched the network')

    -- 6. capture() marks title-only chapters only when the local text is the
    --    title, and never reads long chapters.
    local tokens={'第一章','春','风','吹','过','山','谷','她','回','到','小','镇','第二部分','第三章','街','角','面','包','店'}
    local chapters={{1,12,'第一章'},{13,13,'第二部分'},{14,19,'第三章'}}
    local per_page=3
    local text_reads=0
    local function index(xp) return tonumber(tostring(xp):match('^w:(%d+)$')) end
    local document={}
    function document:isXPointerInDocument(xp) local i=index(xp); return i~=nil and i>=1 and i<=#tokens end
    function document:getPageFromXPointer(xp) return math.floor((index(xp)-1)/per_page)+1 end
    function document:getTextFromXPointers(a,b)
        text_reads=text_reads+1
        local i,j=index(a),index(b)
        local out={}
        for k=i,math.min(j-1,#tokens) do out[#out+1]=tokens[k] end -- [a,b) like CRE
        return table.concat(out,'\n')
    end
    function document:getNextVisibleWordEnd(xp) local i=index(xp); return 'w:'..math.min(#tokens,i+1) end
    function document:getPrevVisibleWordStart(xp) local i=index(xp); return 'w:'..math.max(1,i-1) end
    function document:getPageCount() return math.ceil(#tokens/per_page) end
    function document:getPageXPointer(page) return 'w:'..((page-1)*per_page+1) end
    local toc={toc={}}
    for i,c in ipairs(chapters) do toc.toc[i]={title=c[3],xpointer='w:'..c[1]} end
    function toc:getTocIndexByPage(xp)
        local i,found=index(xp),nil
        for k,c in ipairs(chapters) do if i>=c[1] then found=k end end
        return found
    end
    local map,catalog={}, {}
    for i,c in ipairs(chapters) do
        map[i]={chapterUid=tostring(10+i),chapterIdx=i,title=c[3]}
        catalog[i]={chapterUid=tostring(10+i),chapterIdx=i,title=c[3],wordCount=(c[2]-c[1]+1)*10}
    end
    local book_record={book={book_id='9'},record={chapter_map=map}}
    local ui={document=document,toc=toc,rolling={xpointer='w:13'}}
    local a=assert(P.capture(ui,book_record,catalog))
    assert(a.chapter_uid=='12' and a.chapter_title_only==true,'part page not detected as title-only')
    ui.rolling.xpointer='w:15'
    a=assert(P.capture(ui,book_record,catalog))
    assert(a.chapter_title_only==false,'body chapter marked title-only')
    ui.rolling.xpointer='w:5'
    text_reads=0
    a=assert(P.capture(ui,book_record,catalog))
    assert(a.chapter_title_only==false,'long chapter marked title-only')
    local long_reads=text_reads
    catalog[1].wordCount=40 -- the catalog now counts it as tiny: it is inspected
    text_reads=0
    a=assert(P.capture(ui,book_record,catalog))
    assert(a.chapter_title_only==false,'body text chapter marked title-only')
    assert(text_reads==long_reads+1,'tiny chapter was not inspected exactly once more')
    -- Pagination never changes the decision.
    for _,pages in ipairs({1,3,1000}) do
        per_page=pages; ui.rolling.xpointer='w:13'
        assert(P.capture(ui,book_record,catalog).chapter_title_only==true,'pagination changed the title-only decision')
    end
    -- Embedded CSS can collapse a whitespace-only heading to an empty string.
    local saved_title=tokens[13]
    tokens[13]=''
    assert(P.capture(ui,book_record,catalog).chapter_title_only==true,'empty chapter text not treated as title-only')
    tokens[13]=saved_title
    print('progress source: stale placeholders, unchanged exact path, no placeholder caching, part pages, title-only chapters'..(Original and ', original parity' or '')..': PASS')
end

local ok,e=xpcall(run,debug.traceback)
os.execute("rm -rf '"..TMP.."'")
if not ok then error(e,0) end
