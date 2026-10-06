-- One non-retrying write, followed by authoritative membership checks.
-- The caller persists uncertainty before invoking this worker so cancellation
-- and process loss can only lead to a later read, never automatic resubmission.
local M={}

function M.run(api,id,verify_only)
    local present=api:book_on_shelf(id)
    if type(present)~="boolean" then error("shelf membership is unknown") end
    if present then return {state="verified",already=true} end
    if verify_only then return {state="absent"} end
    local sent,value=pcall(api.add_to_shelf,api,id)
    local message=not sent and tostring(value) or nil
    for _=1,2 do
        local ok,on_shelf=pcall(api.book_on_shelf,api,id)
        if ok and on_shelf==true then return {state="verified",already=false} end
        if not ok then message=tostring(on_shelf) end
    end
    return {state="unconfirmed",error=message or "云端尚未确认加入结果"}
end

return M
