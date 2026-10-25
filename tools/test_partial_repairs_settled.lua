-- Run on KOReader from its directory:
--   ./luajit <repo>/tools/test_partial_repairs_settled.lua <repo>/miuread.koplugin [original book_integrity.lua]
-- Uses real SQLite partial caches in a temporary directory. With the optional
-- second argument, every result is also compared with the original module.
require('setupkoenv')
local plugin=assert(arg[1],'plugin path required')
package.path=plugin..'/?.lua;'..package.path
local lfs=require('libs/libkoreader-lfs')
local DownloadDatabase=require('miuread.download_database')
local BookIntegrity=require('miuread.book_integrity')
local Original=arg[2] and assert(loadfile(arg[2]))() or nil

local TMP='/mnt/us/miuread-backups/test-partial-repairs-'..tostring(os.time())
os.execute("mkdir -p '"..TMP.."'")
local loads=0
local load_manifest=DownloadDatabase.load_manifest
DownloadDatabase.load_manifest=function(root) loads=loads+1; return load_manifest(root) end

local book_file=TMP..'/book.epub'
local function write(path,data) local f=assert(io.open(path,'wb')); f:write(data); f:close() end
write(book_file,'epub')
local book={book_id='1',variants={notes={file=book_file}},chapters={}}
local roots={}
local store={
    data_dir=TMP,
    book=function(_,id) return id=='1' and book or nil end,
    partial_cache_paths=function() return roots end,
}
local function manifest(complete)
    return {option_key='notes-images-book',updated_at=os.time(),chapters={
        ['10']={uid='10',index=1,complete=true},
        ['11']={uid='11',index=2,complete=complete},
    }}
end
local function age(root,seconds)
    local path=DownloadDatabase.partial_path(root)
    local t=os.time()-seconds
    for _,p in ipairs({path,path..'-wal'}) do
        if lfs.attributes(p,'mode')=='file' then assert(lfs.touch(p,t,t)) end
    end
end
local function check(label,expected_rows,expected_loads)
    loads=0
    local rows=BookIntegrity.partial_repairs(store,'1')
    assert(#rows==expected_rows,label..': rows '..#rows..' ~= '..expected_rows)
    if expected_loads then assert(loads==expected_loads,label..': manifest decodes '..loads..' ~= '..expected_loads) end
    if Original then
        local original=Original.partial_repairs(store,'1')
        assert(#original==#rows,label..': original returned '..#original..' rows')
        for i,row in ipairs(rows) do
            for _,k in ipairs({'root','kind','label','complete','failed','total','updated_at','option_error'}) do
                assert(row[k]==original[i][k],label..': field '..k..' differs from original')
            end
        end
    end
    return rows
end

local function run()
    -- The device clock and file timestamps must agree for the settle rule.
    local probe=TMP..'/clock'; write(probe,'x')
    local skew=math.abs(lfs.attributes(probe,'modification')-os.time())
    assert(skew<=2,'file mtime differs from os.time() by '..skew..' s')

    local root=TMP..'/.miuread-partial-notes-images-book'
    os.execute("mkdir -p '"..root.."'")
    roots={root}
    assert(DownloadDatabase.save_manifest(root,manifest(true)))

    -- Just written: verdicts are not remembered, every call decodes.
    check('fresh complete',0,1)
    check('fresh complete again',0,1)
    -- Settled and complete: the second call skips the manifest decode.
    age(root,10)
    check('settled complete',0,1)
    check('settled complete cached',0,0)
    -- Missing generated file makes the cache repairable again immediately.
    os.remove(book_file)
    check('generated file missing',1,1)
    write(book_file,'epub')
    check('generated file restored',0,1)
    age(root,10)
    check('settled again',0,0) -- the restore call above already remembered it
    check('settled again cached',0,0)
    -- A new manifest write (unfinished chapter) is never hidden by the cache.
    assert(DownloadDatabase.save_manifest(root,manifest(false)))
    local rows=check('new unfinished write',1,1)
    assert(rows[1].failed==1 and rows[1].complete==1 and rows[1].manifest,'unfinished row content')
    age(root,10)
    check('settled unfinished',1,1)
    check('settled unfinished again',1,1) -- repairable caches are always decoded
    -- Rewriting it as complete, then removing the cache, behave as before.
    assert(DownloadDatabase.save_manifest(root,manifest(true)))
    age(root,10)
    check('complete after repair',0,1)
    check('complete after repair cached',0,0)
    -- Verdicts survive a restart (module reload) and are reused only while
    -- the files keep their signature; a damaged verdict file is ignored.
    os.execute('sleep 2'); check('flush verdicts',0,0)
    local verdicts=TMP..'/partial-repair-verdicts-v1.json'
    assert(io.open(verdicts,'rb'),'verdicts were not saved')
    local function restart()
        package.loaded['miuread.book_integrity']=nil
        BookIntegrity=require('miuread.book_integrity')
    end
    restart()
    check('after restart',0,0)
    restart()
    write(verdicts,'{damaged')
    check('damaged verdict file',0,1)
    os.execute('sleep 2'); check('re-saved',0,0)
    restart()
    assert(DownloadDatabase.save_manifest(root,manifest(false)))
    check('write after restart',1,1)
    os.execute("rm -rf '"..root.."'")
    check('cache removed',0)
    print('partial repairs: settled verdict reuse, generated file check, new writes, restart persistence, removal'..(Original and ', original parity' or '')..': PASS')
end

local ok,err=xpcall(run,debug.traceback)
os.execute("rm -rf '"..TMP.."'")
if not ok then error(err,0) end
