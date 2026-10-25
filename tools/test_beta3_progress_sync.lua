-- Standalone beta.3 regressions: luatex --luaonly tools/test_beta3_progress_sync.lua
local root=(arg[0] or ''):gsub('tools/test_beta3_progress_sync.lua$','')
if root=='' then root='./' end
local function read(path)
    local f=assert(io.open(root..path,'rb'))
    local s=f:read('*a');f:close();return s
end
local main=read('miuread.koplugin/main.lua')
local sync=read('miuread.koplugin/miuread/sync.lua')
local worker=read('miuread.koplugin/miuread/legacy/read_report_worker.lua')
local client=read('miuread.koplugin/miuread/legacy/client.lua')
local function compile(code, name, env)
    if _VERSION=='Lua 5.1' then
        local chunk=assert(loadstring(code,name));setfenv(chunk,env);return chunk
    end
    return assert(load(code,name,'t',env))
end
local count=0
local function test(name,fn)
    local ok,err=pcall(fn)
    if not ok then error(name..': '..tostring(err),0) end
    count=count+1
end
local function extract(s,a,b)
    local i=assert(s:find(a,1,true),a)
    local j=assert(s:find(b,i+#a,true),b)
    return s:sub(i,j-1)
end
local base={math=math,tonumber=tonumber,tostring=tostring,type=type,
    table=table,ipairs=ipairs,pairs=pairs,pcall=pcall,
    logger={info=function() end,warn=function() end},
    U={copy=function(value) return value end}}
setmetatable(base,{__index=_G})
local class={};base.Plugin=class
compile(extract(main,'function Plugin:_remote_matches(', '\nfunction Plugin:_prepare_progress_snapshot('),'@remote_match',base)()
test('Web and Agent conflict never confirms a progress upload',function()
    local self=setmetatable({store={preferences=function() return {sync={threshold=2}} end}},{__index=class})
    local target={progress=10,chapter_uid='41',chapter_offset=368,offset_basis='wr_data_co'}
    local web={percent=10,chapter_uid='41',offset=0,source='web_cookie'}
    local agent={percent=10,chapter_uid='41',offset=368,source='agent_gateway'}
    local ok,_,_,meta=self:_remote_matches({conflict=true,web=web,agent=agent},target)
    assert(ok==false and meta.reason=='web_unconfirmed_remote_source_conflict')
    assert(self:_remote_matches(web,target)==false)
    assert(self:_remote_matches(agent,target)==true)
    -- Conversely, a Web-confirmed POST must not remain indefinitely pending
    -- merely because the Agent endpoint is stale or interprets co differently.
    local web_confirmed={percent=10,chapter_uid='41',offset=368,source='web_cookie'}
    local agent_stale={percent=10,chapter_uid='41',offset=0,source='agent_gateway'}
    local confirmed,_,source,details=self:_remote_matches({conflict=true,web=web_confirmed,agent=agent_stale},target)
    assert(confirmed and source=='web_cookie' and details.source_conflict==true)
end)

test('source callback forwards failure metadata including anchor',function()
    assert(sync:find('function(position, err, source_meta)',1,true))
    assert(select(2,sync:gsub('function%(position, err, source_meta%)',''))==2)
    assert(sync:find('meta=type(source_meta)=="table" and U.copy(source_meta) or {}',1,true))
    assert(sync:find('anchor=U.copy(anchor)',1,true))
end)

-- Exercise the *actual* legacy helper with fake replies and no HTTP request.
local raw_helpers=extract(worker,'local function normalize_cloud_anchor(', '\nlocal function last_readable_chapter_uid(')
local helper_env=setmetatable({},{__index=base})
compile(raw_helpers..'\n_G.__beta3_refresh=refresh_remote_anchor\n','@web_anchor',helper_env)()
test('reading-time worker uses fresh Web coordinate, never the Agent coordinate',function()
    local book={}
    local web_calls,agent_calls=0,0
    local c={
      get_web_progress=function() web_calls=web_calls+1;return {book={bookId='853116',chapterUid='41',chapterOffset=368,chapterIdx=5,progress=87}} end,
      get_progress=function() agent_calls=agent_calls+1;error('agent must not be used') end,
    }
    assert(_G.__beta3_refresh(c,'853116',book))
    assert(book.remote_chapter_offset==368 and book.remote_raw_progress==87)
    assert(web_calls==1 and agent_calls==0)
    c.get_web_progress=function() return {book={bookId='different',chapterUid='41',chapterOffset=0,progress=87}} end
    assert(not _G.__beta3_refresh(c,'853116',{}))
    c.get_web_progress=function() return {book={chapterUid='41',chapterOffset=nil,progress=87}} end
    assert(not _G.__beta3_refresh(c,'853116',{}))
end)
local client_env=setmetatable({Client={},WeRead={e=function(v) return tostring(v) end,reader_url=function() return 'https://weread.qq.com/web/reader/test' end}},{__index=base})
compile(extract(client,'function Client:get_web_progress(', '\nfunction Client:get_progress('),'@legacy_web_progress',client_env)()
test('Web reading-time GET uses only Cookie Web endpoint',function()
    local called
    local c=setmetatable({get_text=function(_,url,opts)
        called={url=url,opts=opts};return 'json-response'
    end,json_decode=function(_,text) return {parsed=text} end},{__index=client_env.Client})
    local value=c:get_web_progress('853116')
    assert(value.parsed=='json-response')
    assert(called.url:find('/web/book/getProgress?bookId=853116',1,true))
    assert(called.opts.accept=='application/json, text/plain, */*')
end)

-- Actual verification function with a deterministic UI scheduler mock.
local timers={};base.UIManager={scheduleIn=function(_,secs,cb) timers[#timers+1]=cb end}
compile(extract(main,'function Plugin:_verify_progress_submission(', '\nfunction Plugin:_submit_progress_snapshot('),'@verify_progress',base)()
test('only one verify worker runs for two callbacks on the same position',function()
    local readbacks,commits,notified=0,0,0
    timers={}
    local s=setmetatable({
      sync={record=function() return nil end,remote=function(_,_,callback)
          readbacks=readbacks+1
          callback({chapter_uid='41',offset=368,source='web_cookie'},nil)
          return true
      end,set_cloud_anchor=function() end,mark_verified=function() end},
    },{__index=class})
    function s:_prepare_progress_snapshot(_,p) return p end
    function s:_progress_snapshot_current() return true end
    function s:_remote_matches() return true,10,'web_cookie',{reason='chapter_offset_exact'} end
    function s:_commit_progress_verified() commits=commits+1 end
    function s:_save_pending_progress() error('verified should not become pending') end
    function s:_save_progress_state() end
    local position={chapter_uid='41',chapter_offset=368,progress=10,progress_epoch=2,progress_sequence=11}
    assert(s:_verify_progress_submission('853116',position,{verify_delays={0.2}},function(ok)
        assert(ok);notified=notified+1
    end))
    assert(s:_verify_progress_submission('853116',position,{verify_delays={0.2}},function(ok)
        assert(ok);notified=notified+1
    end))
    assert(#timers==1, 'duplicate verification scheduled')
    timers[1]()
    assert(readbacks==1 and commits==1 and notified==2)
    assert(next(s._progress_verify_inflight)==nil)
end)

compile(extract(main,'function Plugin:_adopt_remote_progress_issue(', '\nfunction Plugin:_force_local_progress_issue('),'@adopt_remote',base)()
test('unresolved remote does not clear 48 local sync fields',function()
    local resets=0
    local s=setmetatable({
      store={reset_progress_sync_state=function() resets=resets+1 end},
      sync={remote=function(_,_,callback)
        callback({chapter_uid='41',offset=0,position_basis='wr_data_co_unresolved'})
        return true
      end},
    },{__index=class})
    function s:logged_in() return true end
    function s:_network_radio_hint() return true end
    function s:_stored_progress_record() return {book={book_id='853116'},path='test'} end
    local outcome
    assert(s:_adopt_remote_progress_issue({book_id='853116'},function(ok,reason)
      assert(ok==false);outcome=reason
    end))
    assert(outcome=='remote_exact_unresolved' and resets==0)
end)
print('PASS: '..count..' beta3 progress sync regression tests')
