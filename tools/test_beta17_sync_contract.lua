-- Release-specific integration invariants for 6.1.0-beta.17.
local script=arg and arg[0] or ""
local root=script:match("^(.*)/tools/[^/]+$") or "."
local function read(path)
    local f=assert(io.open(root.."/"..path,"rb")); local value=f:read("*a"); f:close(); return value
end
local function fragment(source,start_marker,end_marker)
    local begin_at=assert(source:find(start_marker,1,true),"missing "..start_marker)
    local end_at=end_marker and source:find(end_marker,begin_at+1,true)
    return source:sub(begin_at,(end_at and end_at-1) or #source)
end
local config=read("miuread.koplugin/miuread/config.lua")
local main=read("miuread.koplugin/main.lua")
local worker=read("miuread.koplugin/miuread/legacy/read_report_worker.lua")
local sync=read("miuread.koplugin/miuread/sync.lua")
local service=read("miuread.koplugin/miuread/read_report_service.lua")
assert(config:find('VERSION = "6.1.0-beta.17"',1,true),"beta.17 metadata")

-- The user has made Kindle the authoritative position on each safe upload.
local replay=fragment(main,"function Plugin:_submit_saved_pending_progress","function Plugin:_submit_all_saved_pending_progress")
assert(replay:find("force_write=true",1,true),"local submission not authoritative")
assert(replay:find("_progress_snapshot_current(book_id,position)",1,true),"stale local snapshot not rejected")
assert(not replay:find("self.sync:remote(book_id",1,true),"remote freshness still blocks Kindle")
assert(main:find("kindle_coordinate_authoritative",1,true),"cloud fence not bypassed for native Kindle")
assert(main:find("_verify_progress_submission",1,true),"cloud readback verification missing")

-- Time and progress are separate tasks but remain position-coordinated.
local compat=fragment(worker,"if reading_time_compat then","local accepted, result")
assert(compat:find("estimate_position(book,progress_ratio)",1,true),"Kindle coordinates not used for time")
assert(not compat:find("refresh_remote_anchor(client, book_id, book)",1,true),"Web GET still required before time POST")
assert(compat:find("request_dispatched=false",1,true),"unsafe time position dispatch not guarded")
assert(worker:find("validate_terminal_progress(book,position)",1,true),"terminal progress safety removed")
assert(sync:find("position=position_override or self:_position_for_report(nil,true)",1,true),"time daemon not supplied position")
assert(sync:find("position_safe = position~=nil and position.safe==true",1,true),"unsafe daemon control")
assert(service:find("report_book.local_chapter_uid=control.local_chapter_uid",1,true),"daemon not passing exact chapter")
assert(service:find("report_book.local_native_chapter_offset=control.local_native_chapter_offset == true",1,true),"daemon not passing native marker")

-- Existing manual resolution and lossless pending state stay available.
local store=read("miuread.koplugin/miuread/store.lua")
assert(store:find("pending_unresolved_position",1,true),"pending position persistence removed")
assert(main:find('text="以云端为准"',1,true),"manual remote resolution lost")
assert(main:find('text="以本机为准"',1,true),"manual Kindle resolution lost")
print("beta17 Kindle-authoritative progress / time separation contracts: PASS")
