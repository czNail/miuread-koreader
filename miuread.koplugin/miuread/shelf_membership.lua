-- One non-retrying write, followed by authoritative membership checks.
-- The caller persists uncertainty before invoking this worker so cancellation
-- and process loss can only lead to a later read, never automatic resubmission.
local M={}

function M.run(api,id,desired,verify_only)
    assert(type(desired)=="boolean","shelf target must be boolean")
    local present=api:book_on_shelf(id)
    if type(present)~="boolean" then error("shelf membership is unknown") end
    if present==desired then return {state="verified",already=true,present=present} end
    if verify_only then return {state="mismatch",present=present} end
    local mutate=desired and api.add_to_shelf or api.remove_from_shelf
    local sent,value=pcall(mutate,api,id)
    local message=not sent and tostring(value) or nil
    for _=1,2 do
        local ok,on_shelf=pcall(api.book_on_shelf,api,id)
        if ok and on_shelf==desired then return {state="verified",already=false,present=on_shelf} end
        if not ok then message=tostring(on_shelf) end
    end
    return {state="unconfirmed",error=message or "云端尚未确认书架变更结果"}
end

return M
