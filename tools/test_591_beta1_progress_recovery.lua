local script=arg and arg[0] or ""
local root=script:match("^(.*)/tools/[^/]+$") or "."
local function read(path)
    local f=assert(io.open(root.."/"..path,"rb")); local s=f:read("*a"); f:close(); return s
end

local config=read("miuread.koplugin/miuread/config.lua")
local main=read("miuread.koplugin/main.lua")
local sync=read("miuread.koplugin/miuread/sync.lua")
local store=read("miuread.koplugin/miuread/store.lua")
local worker=read("miuread.koplugin/miuread/legacy/read_report_worker.lua")

assert(config:find('VERSION = ',1,true),"version identity missing while validating 5.9.1 beta.1+ recovery contract")
assert(config:find('SCHEMA = 136',1,true),"schema unexpectedly changed")

-- Exact native beta.19 snapshots must be replayable after Reader close.
assert(main:find('function Plugin:_normalize_exact_progress_snapshot',1,true),"exact snapshot normalizer missing")
assert(main:find('snapshot.safe=true',1,true),"exact snapshot safe flag missing")
assert(main:find('safe=true,coordinate_safe=true,precise=true',1,true),"passive exact cache safety flags missing")
assert(store:find('progress_exact_snapshot_repair_591b1',1,true),"one-shot beta.19 repair missing")
assert(store:find('session.progress_upload_state="pending_send"',1,true),"repaired unsent exact snapshot not returned to pending_send")

-- ReadingEnd mapping failures retain enough immutable material for Home recovery.
assert(sync:find('anchor=U.copy(anchor)',1,true),"source failure does not return captured Reader anchor")
assert(main:find('source_anchor=type(source_anchor)=="table" and U.copy(source_anchor) or nil',1,true),"recovery capsule does not persist source anchor")
assert(main:find('progress_sync_state="local_coordinate_unresolved"',1,true),"unresolved coordinate state missing")
assert(main:find('function Plugin:_recover_pending_progress_anchor',1,true),"Home saved-anchor recovery missing")
assert(sync:find('function Sync:resolve_saved_progress_anchor',1,true),"detached saved-anchor resolver missing")
assert(sync:find('SourcePosition.locate(reader,record_snapshot,anchor,{cache_only=true})',1,true),"saved-anchor local recovery missing")
assert(sync:find('cache_only=false,force_refresh=true',1,true),"saved-anchor fresh network fallback missing")
assert(main:find('can_recover_anchor=anchor_only and saved_anchor~=nil',1,true),"failure item does not expose anchor recovery")
assert(main:find('text="恢复精确位置"',1,true),"manual Home anchor recovery action missing")

-- No opaque pending: anchor recovery is first-class, old unrecoverable rows are explicit stale rows.
assert(main:find('local_coordinate_unresolved=true',1,true),"unresolved state absent from pending state set")
assert(main:find('"anchor=",tostring(anchor),"stale=",tostring(stale)',1,true),"sync diagnostics do not classify anchor/stale states")
assert(main:find('can_clear_stale=replayable~=true and not (anchor_only and saved_anchor~=nil)',1,true),"recoverable anchor could be misclassified as stale")

-- Reading-time worker requested stop is not treated as a crash/restart source.
assert(sync:find('lightweight service exited after requested stop',1,true),"requested-stop ReadReport log missing")
assert(sync:find('if was_active then',1,true),"ReadReport restart not gated by active state")

-- Existing cloud-integrity hard rules remain present.
-- 6.2: periodic time compatibility writes replay the first verified Web
-- position for this reading session; native Kindle position is reserved for
-- the separate precise progress writer, which retains its terminal guard.
assert(worker:find('local terminal_ok,terminal_error=validate_terminal_progress(book,position)',1,true),
    "precise progress report lost its terminal chapter guard")
assert(worker:find('if time_only ~= true then',1,true),
    "precise progress position validation no longer separated from pure time")
assert(worker:find('position_override=normalize_cloud_anchor(saved,{})',1,true),
    "session Web anchor reuse missing")
assert(worker:find('local anchor=type(job.cloud_anchor)=="table" and job.cloud_anchor or {}',1,true),
    "the opening Web snapshot is not available to the time writer")
assert(worker:find('observed_at>=session_started-2',1,true),
    "the opening Web snapshot is not bound to this reader session")
assert(worker:find('book.session_time_anchor_session=session_id',1,true),
    "session identity not bound to the time anchor")
assert(not worker:find('position_override.source="kindle_native_time_guard"',1,true),
    "time compatibility mode unexpectedly reintroduced Kindle's changing coordinate")
assert(main:find('pending_send',1,true),"pending_send recovery contract lost")
assert(main:find('freshness',1,true),"freshness resolver integration lost")

print('5.9.1-beta.1 progress transaction recovery contract: PASS')
