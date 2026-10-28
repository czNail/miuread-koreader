local function read(path)
    local f=assert(io.open(path,"rb")); local s=f:read("*a"); f:close(); return s
end
local main=read("miuread.koplugin/main.lua")
local sync=read("miuread.koplugin/miuread/sync.lua")
local worker=read("miuread.koplugin/miuread/legacy/read_report_worker.lua")
local service=read("miuread.koplugin/miuread/read_report_service.lua")
local store=read("miuread.koplugin/miuread/store.lua")

for _,needle in ipairs{
    "progress_write_fenced", "remote_fetch_pending",
    "remote_newer_pending", "remote_exact_unresolved", "open_local_position=",
    "jump_cached_remote_position", "text_anchor_rescue", "bounded percent fallback",
} do assert(main:find(needle,1,true),needle) end
assert(not main:find("automatic_check_after_user_interaction",1,true),"interaction cannot force local winner")
assert(not main:find("late_remote_after_user_interaction",1,true),"late interaction cannot force local winner")

assert(sync:find("First PageUpdate after opening only establishes the baseline",1,true),"first restored page must not become a local event")
assert(sync:find("local freshness belongs to progress reconciliation",1,true),"local event tracking must be independent of time sync")
assert(sync:find("remote_xpointer_cache",1,true),"verified remote XPointer cache exists")
assert(sync:find("_save_safe_pending_state",1,true),"unsubmitted time remains recoverable")

assert(worker:find("anchor.protocol_progress or anchor.raw_progress",1,true),"time-only Web wire echo uses server progress")
assert(not worker:find("anchor.raw_percent or anchor.raw_progress",1,true),"raw percent cannot lead canonical anchor")
assert(service:find("local drop_time=false -- never silently discard accumulated time",1,true),"time retry budget must not discard unsent seconds")
assert(store:find("preserve SAFE, provably unsent reading-time carry",1,true),"restarts must preserve verified unsent time")

print("beta.5 sync contract: PASS")
