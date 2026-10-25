-- Run from the repository root: lua5.1 tools/test_store_incremental_flush.lua
-- Settings flushes reuse unchanged top-level entries; the file must stay identical in meaning.
local TOOL_DIR=tostring(arg and arg[0] or ''):match('^(.*)/[^/]+$') or '.'
local ROOT=TOOL_DIR..'/../miuread.koplugin/'
package.path=ROOT..'?.lua;'..package.path
local unique=os.tmpname()
os.remove(unique)
local TMP=(os.getenv('TMPDIR') or '/tmp')..'/miuread-store-'..unique:match('([^/]+)$')
local function quote(value) return "'"..tostring(value):gsub("'", "'\\''").."'" end
local function mkdir(path) os.execute('mkdir -p '..quote(path)); return true end
mkdir(TMP)

local function copy(value)
    if type(value)~='table' then return value end
    local out={}; for k,v in pairs(value) do out[k]=copy(v) end; return out
end
local function merge(a,b)
    local out=copy(a or {})
    for k,v in pairs(b or {}) do
        if type(v)=='table' and type(out[k])=='table' then out[k]=merge(out[k],v)
        else out[k]=copy(v) end
    end
    return out
end
local function dump(value)
    if type(value)=='string' then return string.format('%q',value) end
    if type(value)~='table' then return tostring(value) end
    local out={'{'}
    for k,v in pairs(value) do out[#out+1]='['..dump(k)..']='..dump(v)..',' end
    out[#out+1]='}'; return table.concat(out)
end
local function read(path)
    local f=io.open(path,'rb'); if not f then return nil end
    local data=f:read('*a'); f:close(); return data
end
local fail_write=false
local write_count=0
local function write(path,data)
    if fail_write then return false,'simulated write failure' end
    write_count=write_count+1
    local f=assert(io.open(path,'wb')); f:write(data); f:close(); return true
end
local function attributes(path,what)
    local ok=os.execute('[ -d '..quote(path)..' ]')
    local attr
    if ok==true or ok==0 then attr={mode='directory',modification=1}
    else local data=read(path); if data then attr={mode='file',size=#data,modification=1} end end
    return attr and (what and attr[what] or attr)
end
package.preload['datastorage']=function()
    return {getFullDataDir=function() return TMP end,getSettingsDir=function() return TMP end,getDataDir=function() return TMP end}
end
package.preload['libs/libkoreader-lfs']=function() return {attributes=attributes} end
package.preload['luasettings']=function()
    local Settings={}
    function Settings:open(path)
        local chunk=loadfile(path)
        local obj={data=chunk and chunk() or {}}
        function obj:readSetting(k,d) local v=self.data[k]; if v==nil then return d end; return v end
        function obj:saveSetting(k,v) self.data[k]=v end
        function obj:delSetting(k) self.data[k]=nil end
        return obj
    end
    return Settings
end
package.preload['dump']=function() return dump end
package.preload['miuread.json']=function() return {} end
package.preload['miuread.download_database']=function()
    return {runtime_path=function(path) return path..'/runtime' end}
end
package.preload['miuread.cookies']=function() return {} end
package.preload['logger']=function() return {info=function() end,warn=function() end,err=function() end} end
package.preload['miuread.util']=function()
    return {copy=copy,merge=merge,mkdir=mkdir,atomic_write=write,
        copy_file=function(a,b) local data=read(a); return data and write(b,data) or false end,
        file_size=function(path) local data=read(path); return data and #data end,
        trim=function(v) return tostring(v or ''):match('^%s*(.-)%s*$') end,
    }
end


-- Independent oracle: what the file must mean, compared with tostring() numbers
-- exactly like the persisted representation.
local function same(a,b)
    if type(a)=='number' and type(b)=='number' then return tostring(a)==tostring(b) end
    if type(a)~='table' or type(b)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function expect_file(path,data,label)
    local persisted=assert(loadfile(path),label..': settings file does not load')()
    local expected=assert(loadstring('return '..dump(data)))()
    assert(same(persisted,expected),label..': persisted settings differ from memory')
    assert(read(path..'.miuread-backup')==read(path),label..': backup differs from the settings file')
end

local function run()
    local Config=require('miuread.config')
    local path=TMP..'/miuread.lua'
    local catalog={}
    for i=1,200 do catalog[i]={chapterUid=i,title='第'..i..'章 "q" \\ \n',level=1+i%3,ratio=i/7} end
    assert(write(path,'return '..dump({schema=Config.SCHEMA,
        library={['100']={book_id='100',catalog=catalog,variants={full={file='/a.epub',size=1}}}},
        sessions={['100']={percent=0.25,offset=10}},
        preferences={home_ui={active_section='device'}}})))
    local Store=require('miuread.store')
    local store=Store:new({settings_path=path,data_dir=TMP..'/data'})
    local data=store.db.data
    assert(store:flush('first'))
    expect_file(path,data,'first flush')
    local entries=assert(store._validated_settings.entries,'flush did not keep validated entries')

    -- Unchanged keys reuse their entry; an in-place nested change is detected.
    data.sessions['100'].percent=0.5
    assert(store:flush('session'))
    expect_file(path,data,'session change')
    local after=store._validated_settings.entries
    assert(after.library==entries.library,'unchanged library was serialized again')
    assert(after.sessions~=entries.sessions,'changed sessions reused stale text')
    data.library['100'].catalog[150].title='changed in place'
    assert(store:flush('library'))
    expect_file(path,data,'nested library change')
    assert(store._validated_settings.entries.library~=after.library,'in-place library change was missed')
    -- Precision below the persisted representation is not a change.
    data.sessions['100'].offset=10+1e-15
    local before=store._validated_settings.entries.sessions
    assert(store:flush('precision'))
    assert(store._validated_settings.entries.sessions==before,'representation-equal number forced a rewrite')

    -- Randomized mutations, including deletions and type changes.
    math.randomseed(20261016)
    local strings={'','中文','a"b','\\','\n\r\t','\0\255',']=','--[[','x'}
    local function scalar()
        local pick=math.random(5)
        if pick==1 then return strings[math.random(#strings)] end
        if pick==2 then return math.random(-1000,1000) end
        if pick==3 then return math.random()/3 end
        if pick==4 then return math.random(2)==1 end
        return {k=strings[math.random(#strings)],n=math.random(9)}
    end
    local function random_table(root)
        local node=root
        for _=1,math.random(0,3) do
            local children={}
            for _,v in pairs(node) do if type(v)=='table' then children[#children+1]=v end end
            if #children==0 then break end
            node=children[math.random(#children)]
        end
        return node
    end
    local top_keys={'library','sessions','preferences','shelf_cache','auth','extra_a','extra_b'}
    for round=1,300 do
        local op=math.random(6)
        local key=top_keys[math.random(#top_keys)]
        if op==1 then
            data[key]=nil
        elseif op==2 then
            data[key]=scalar()
        else
            if type(data[key])~='table' then data[key]={} end
            local node=random_table(data[key])
            local field=math.random(3)==1 and math.random(20) or strings[math.random(#strings)]..math.random(5)
            if op==3 then node[field]=nil else node[field]=scalar() end
        end
        if math.random(4)==1 then
            assert(store:flush('round '..round))
            expect_file(path,data,'round '..round)
        end
    end
    assert(store:flush('final'))
    expect_file(path,data,'final random state')

    -- A value compact serialization cannot represent takes the original path,
    -- fails as before and drops the cached entries; recovery writes everything.
    local good=read(path)
    data.preferences={callback=function() end}
    assert(not store:flush('unsupported'),'unsupported value was persisted')
    assert(read(path)==good,'failed flush changed the settings file')
    assert(store._validated_settings==nil,'failed flush kept cached entries')
    data=store.db.data -- a failed flush reopens the settings from disk
    data.preferences={home_ui={active_section='shelf'}}
    assert(store:flush('recovered'))
    expect_file(path,data,'after unsupported value')

    -- Parser-depth failures still trigger the emergency session compaction.
    local deep={}; local node=deep
    for _=1,260 do node.child={}; node=node.child end
    data.sessions=type(data.sessions)=='table' and data.sessions or {}
    data.sessions['200']={percent=0.75,remote_sources=deep}
    assert(store:flush('deep'),'deep diagnostic field was not compacted')
    local persisted=loadfile(path)()
    assert(persisted.sessions['200'].percent==0.75 and persisted.sessions['200'].remote_sources==nil,
        'emergency compaction result differs')
    expect_file(path,data,'after emergency compaction')

    -- A write failure keeps the previous file; the next flush rewrites it.
    good=read(path)
    data.sessions['200'].percent=0.8
    fail_write=true
    assert(not store:flush('write failure'))
    fail_write=false
    assert(read(path)==good,'failed write changed the settings file')
    data=store.db.data
    data.sessions['200'].percent=0.8
    assert(store:flush('after write failure'))
    expect_file(path,data,'after write failure')

    -- Bytes written by another process are parsed once, then reused by reads,
    -- reload checks and the next flush; a further change is parsed again.
    local real_loadstring=loadstring
    local parses=0
    loadstring=function(chunk,name)
        if name=='@'..path then parses=parses+1 end
        return real_loadstring(chunk,name)
    end
    local foreign=loadfile(path)(); foreign.preferences={home_ui={active_section='device'}}
    assert(write(path,'return '..dump(foreign)))
    assert(store:read_persisted('preferences').home_ui.active_section=='device')
    assert(store:read_persisted('preferences').home_ui.active_section=='device')
    store:reload()
    data=store.db.data
    assert(data.preferences.home_ui.active_section=='device','reload missed the external write')
    assert(parses==1,'external settings parsed '..parses..' times')
    foreign.preferences.home_ui.active_section='recent'
    assert(write(path,'return '..dump(foreign)))
    assert(store:read_persisted('preferences').home_ui.active_section=='recent','changed bytes reused a stale snapshot')
    assert(parses==2,'changed settings were not parsed again')
    local copy=store:read_persisted('preferences'); copy.home_ui.active_section='mutated'
    assert(store:read_persisted('preferences').home_ui.active_section=='recent','read_persisted returned shared state')
    loadstring=real_loadstring
    store:reload(); data=store.db.data
    assert(store:flush('after external write'))
    expect_file(path,data,'after external write')

    -- reload() of the bytes it already validated: no parse, memory becomes
    -- exactly the file (strict numbers), deferred in-memory edits are dropped
    -- as before, and unchanged top-level tables are kept.
    local function strict(a,b)
        if a==b then return true end
        if type(a)~='table' or type(b)~='table' then return false end
        for k,v in pairs(a) do if not strict(v,b[k]) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    -- Memory keeps more digits than the file stores (tostring precision).
    data.sessions['200'].percent=0.1234567890123456
    assert(store:flush('before reload'))
    data=store.db.data
    assert(data.sessions['200'].percent~=assert(loadfile(path))().sessions['200'].percent,'precision case not set up')
    local library_table=data.library
    store:set_deferred('recent_reads',{items={{book_id='x'}}})
    data.extra_reload_key={dropped=true}
    local real_loadfile=loadfile
    local file_parses=0
    loadfile=function(name,...) if name==path then file_parses=file_parses+1 end return real_loadfile(name,...) end
    parses=0; loadstring=function(chunk,name) if name=='@'..path then parses=parses+1 end return real_loadstring(chunk,name) end
    local writes_before_reload=write_count
    store:reload()
    loadfile=real_loadfile; loadstring=real_loadstring
    assert(file_parses==0 and parses==0,'unchanged reload parsed the file again')
    assert(write_count==writes_before_reload,'unchanged reload rewrote the backup')
    assert(store.db.data.library==library_table,'unchanged library table was replaced')
    assert(strict(store.db.data,assert(loadfile(path))()),'reload does not match the file exactly')
    data=store.db.data

    -- Shared persisted copies: one copy per file state, never the snapshot.
    local first=store:read_persisted_shared('library')
    assert(first==store:read_persisted_shared('library'),'shared copy was rebuilt for unchanged bytes')
    assert(first~=store._validated_settings.data.library,'validated snapshot was shared')
    first.injected=true
    assert(store:read_persisted('library').injected==nil,'shared copy leaked into persisted reads')
    data.library['300']={book_id='300',title='new'}
    assert(store:flush('library changed'))
    local second=store:read_persisted_shared('library')
    assert(second~=first and second['300'] and second['300'].title=='new','shared copy survived a file change')

    -- With the backup already equal to the file, a change writes the file and
    -- the backup only (no duplicate .previous copy).
    data=store.db.data
    data.sessions['200'].percent=0.9
    local writes_before=write_count
    assert(store:flush('two writes'))
    assert(write_count==writes_before+2,'changed flush wrote '..(write_count-writes_before)..' files')
    expect_file(path,data,'two writes')

    -- Unchanged data still skips the write entirely.
    local writes=write_count
    assert(store:flush('unchanged'))
    assert(write_count==writes,'unchanged settings were written again')
    print('incremental settings flush: reuse, change detection, random mutations, fallback, compaction, write failure, external reads, reload and shared reads: PASS')
end

local ok,err=xpcall(run,debug.traceback)
os.execute('rm -rf '..quote(TMP))
if not ok then error(err,0) end
