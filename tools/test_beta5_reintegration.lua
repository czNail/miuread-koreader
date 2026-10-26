-- beta.5 selective-cherry-pick behavior contracts; runs under Lua 5.1, LuaJIT, or texlua.
local root=(arg[0] or ''):gsub('tools/test_beta5_reintegration.lua$','')
if root=='' then root='./' end
local function read(path)
  local f=assert(io.open(root..path,'rb'));local value=f:read('*a');f:close();return value
end
local function extract(s,a,b)
  local i=assert(s:find(a,1,true),a);local j=assert(s:find(b,i+#a,true),b)
  return s:sub(i,j-1)
end
local function compile(code,name,env)
  if _VERSION=='Lua 5.1' then
    local chunk=assert(loadstring(code,name));setfenv(chunk,env);return chunk
  end
  return assert(load(code,name,'t',env))
end
local count=0
local function test(name,fn)
  local ok,err=pcall(fn)
  if not ok then error('FAIL '..name..': '..tostring(err),0) end
  count=count+1
end
local main=read('miuread.koplugin/main.lua')
local sync=read('miuread.koplugin/miuread/sync.lua')
local worker=read('miuread.koplugin/miuread/legacy/read_report_worker.lua')
local base={logger={info=function() end,warn=function() end},U={copy=function(x)return x end}}
setmetatable(base,{__index=_G})
local cls={};base.Plugin=cls
compile(extract(main,'function Plugin:_remote_matches(', '\nfunction Plugin:_prepare_progress_snapshot('),'@compare',base)()
local function comparator()
  return setmetatable({store={preferences=function() return {sync={threshold=2}} end}}, {__index=cls})
end
local target={progress=10,chapter_uid='41',chapter_offset=368,offset=1,offset_basis='wr_data_co'}
local web_good={chapter_uid='41',offset=368,percent=10,source='web_cookie'}
local web_bad={chapter_uid='41',offset=0,percent=10,source='web_cookie'}
local agent_good={chapter_uid='41',offset=368,percent=10,source='agent_gateway'}
test('Web POST never verified by Agent when Web missing', function()
  local s=comparator()
  assert(s:_remote_matches(agent_good,target,true)==false)
  assert(s:_remote_matches({agent=agent_good},target,true)==false)
end)
test('Web POST not verified if Web differs even with matching Agent', function()
  local s=comparator()
  assert(s:_remote_matches({web=web_bad,agent=agent_good,conflict=true},target,true)==false)
  assert(s:_remote_matches({web={chapter_uid='41',offset=348,percent=10,source='web_cookie'},agent=agent_good},target,true)==false)
end)
test('Web POST confirms when Web matches, regardless of Agent absence', function()
  local s=comparator()
  assert(s:_remote_matches(web_good,target,true)==true)
  assert(s:_remote_matches({web=web_good,agent=web_bad,conflict=true},target,true)==true)
end)
test('beta.2 coordinate field precedence preserved',function()
  local s=comparator()
  assert(s:_remote_matches(web_good,target,true)==true) -- chapter_offset=368 preferred over offset=1
end)
test('normal multi-source comparison retains beta.2 semantics',function()
  local s=comparator()
  assert(s:_remote_matches({web=web_bad,agent=agent_good,conflict=true},target)==true)
end)
test('source mapping failure propagates recovery anchor metadata',function()
  assert(select(2,sync:gsub('function%(position, err, source_meta%)',''))==2)
  assert(sync:find('meta=type(source_meta)=="table" and U.copy(source_meta) or {}',1,true))
end)
local helpers=extract(worker,'local function normalize_cloud_anchor(', '\nlocal function last_readable_chapter_uid(')
local helper_env=setmetatable({Content={is_structural_chapter=function() return false end},chapter_uid=function(c) return c.chapterUid or c.chapter_uid end}, {__index=base})
compile(helpers..'\n_G.__beta5_refresh=refresh_remote_anchor\n','@webreadtime',helper_env)()
test('reading-time report uses Web and same-book matching chapter index',function()
  local book={chapter_uid='old',chapter_idx=99,chapters={{chapterUid='41',chapterIdx=6}}}
  local c={get_web_progress=function()return {book={bookId='book1',chapterUid='41',chapterOffset=368,progress=87}}end}
  assert(_G.__beta5_refresh(c,'book1',book)==true)
  assert(book.remote_chapter_idx==6 and book.remote_chapter_offset==368)
end)
test('missing chapter index does not reuse stale index',function()
  local book={chapter_uid='old',chapter_idx=99}
  local c={get_web_progress=function() return {book={bookId='book1',chapterUid='41',chapterOffset=368,progress=87}}end}
  assert(_G.__beta5_refresh(c,'book1',book)==false)
end)
test('Web chapter index accepted when response complete',function()
  local c={get_web_progress=function()return {book={bookId='book1',chapterUid='41',chapterOffset=368,chapterIdx=5,progress=87}}end}
  local book={}
  assert(_G.__beta5_refresh(c,'book1',book)==true)
  assert(book.remote_chapter_idx==5)
end)
local remote_env=setmetatable({Sync={},
  sourced_progress=function(value,_,source)
    if not value then return nil end
    return {source=source,chapter_uid=value.chapterUid,offset=value.chapterOffset,
       percent=value.progress,raw_percent=value.progress,updated_at=13}
  end,
  catalog_progress_from_remote=function(p) return p end,
  choose_remote_progress=function(web,agent)return web or agent end,
  strip_progress_sources=function(x)return x end,
  Http={is_auth_error=function() return false end}
},{__index=base})
compile(extract(sync,'function Sync:remote(book_id, callback, options)', '\nfunction Sync:mark_verified('),'@remote',remote_env)()
local function fake_remote()
  local calls={web=0,both=0,writes=0}
  local store={auth=function()return {login_session_id='session',account={vid='user'}}end,
    reload=function()end,preferences=function()return {sync={threshold=2}}end,
    session=function()return {}end,
    save_session=function() calls.writes=calls.writes+1;return {},true end}
  local s=setmetatable({store=store,record_generation=0,host={},
    api={web_progress=function() calls.web=calls.web+1
      return {chapterUid='41',chapterOffset=368,progress=10} end,
    progress_sources=function() calls.both=calls.both+1
      return {web={chapterUid='41',chapterOffset=368,progress=10},agent={chapterUid='41',chapterOffset=368,progress=10}}end},
    async={run=function(_,_,fn,cb) local ok,val=pcall(fn);cb(ok and {ok=true,value=val} or {ok=false,error=tostring(val)});return true end}},
    {__index=remote_env.Sync})
  function s:record()return nil end
  function s:_remote_catalog()return {}end
  function s:_normalize_remote_progress(p)return p end
  function s:set_remote_wire_anchor()return true end
  function s:set_cloud_anchor()return true end
  return s,calls
end
test('Web verify-only calls Web once and never changes session baseline',function()
  local s,calls=fake_remote();local result
  s:remote('book1',function(r,err) assert(err==nil);result=r end,{detached=true,web_only=true,verify_only=true,raw_coordinate=true})
  assert(result and result.source=='web_cookie' and result.offset==368)
  assert(calls.web==1 and calls.both==0 and calls.writes==0)
end)
test('normal cloud progress retains dual-source API',function()
  local s,calls=fake_remote();local result
  s:remote('book1',function(r,err) assert(err==nil);result=r end,{detached=true,raw_coordinate=true,update_cloud_anchor=false})
  assert(result and calls.both==1 and calls.web==0 and calls.writes>=1)
end)
local timers={};base.UIManager={scheduleIn=function(_,_,cb)timers[#timers+1]=cb end}
compile(extract(main,'function Plugin:_verify_progress_submission(', '\nfunction Plugin:_submit_progress_snapshot('),'@verify',base)()
test('same Web verification coalesces callbacks and requires Web flag',function()
  timers={};local reads,commits,callbacks=0,0,0
  local s=setmetatable({store={auth=function()return {account={vid='user'},login_session_id='session'}end},
    sync={record=function()return nil end,remote=function(_,_,cb,opt)
      assert(opt.web_only==true and opt.verify_only==true)
      reads=reads+1
      cb({chapter_uid='41',offset=368,source='web_cookie',percent=10})
      return true
    end,set_cloud_anchor=function()end,mark_verified=function()end}}, {__index=cls})
  function s:_prepare_progress_snapshot(_,p)return p end
  function s:_progress_snapshot_current()return true end
  function s:_remote_matches(_,_,webflag)assert(webflag==true);return true,10,'web_cookie',{reason='chapter_offset_exact'}end
  function s:_commit_progress_verified()commits=commits+1 end
  function s:_save_progress_state()end
  local p={chapter_uid='41',chapter_offset=368,progress=10,progress_epoch=2,progress_sequence=9}
  for _=1,2 do assert(s:_verify_progress_submission('book1',p,{verify_delays={.2}},function(ok)assert(ok);callbacks=callbacks+1 end))end
  assert(#timers==1)
  timers[1]()
  assert(reads==1 and commits==1 and callbacks==2 and next(s._progress_verify_inflight)==nil)
end)
test('verification result from prior login never persists into current account',function()
  timers={};local auth={account={vid='userA'},login_session_id='A'}
  local writes,readbacks=0,0
  local s=setmetatable({store={auth=function() return auth end},sync={
    record=function()return nil end,
    remote=function(_,_,cb)readbacks=readbacks+1;cb(nil,'login changed');return true end,
    set_cloud_anchor=function()writes=writes+1 end,
    mark_verified=function()writes=writes+1 end}}, {__index=cls})
  function s:_prepare_progress_snapshot(_,p)return p end
  function s:_progress_snapshot_current()return true end
  function s:_remote_matches()return false end
  function s:_commit_progress_verified()writes=writes+1 end
  function s:_save_pending_progress()writes=writes+1 end
  function s:_save_progress_state()end
  local result
  s:_verify_progress_submission('book1',{chapter_uid='41',chapter_offset=368,progress=10,
    progress_epoch=2,progress_sequence=9},{verify_delays={.2}},function(ok,_,why)
     assert(ok==false);result=why
  end)
  auth={account={vid='userB'},login_session_id='B'}
  timers[1]()
  assert(result=='account_changed' and readbacks==1 and writes==0)
end)
print('PASS: '..count..' beta5 reintegration contracts')
