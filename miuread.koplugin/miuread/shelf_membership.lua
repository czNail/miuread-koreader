-- One non-retrying write, followed by authoritative membership checks.
-- The caller persists uncertainty before invoking this worker so cancellation
-- and process loss can only lead to a later read, never automatic resubmission.
local M={}

function M.run(api,id,desired,verify_only)
    assert(type(desired)=="boolean","shelf target must be boolean")
    if type(api.scope)=="function" then api=api:scope() end
    local read,present=pcall(api.book_on_shelf,api,id)
    if not read or type(present)~="boolean" then
        local message=not read and tostring(present) or "shelf membership is unknown"
        return {state=verify_only and "unconfirmed" or "blocked",stage="membership",
            error=message,read_error=message}
    end
    if present==desired then return {state="verified",already=true,present=present} end
    if verify_only then return {state="mismatch",present=present} end
    -- A missing native credential is not an uncertain write. Check this only
    -- *after* the Web readback, so an already-removed book needs no QR scan.
    if not desired and type(api.store)=="table" and type(api.store.auth)=="function" then
        local authenticated=require("miuread.shelf_client").credentials(api.store:auth() or {})
        if not authenticated then
            return {state="blocked",stage="credentials",present=present,
                error="[MiuReadShelfAuthorization] 需要 E-Ink 客户端授权后才能从微信书架移除"}
        end
    end
    -- Web cannot remove shelf entries. A user-authorized native shelf client is
    -- the only supported write route; Web remains usable for readback.
    -- This per-action override does not change the global API transport mode.
    local writer=api
    if not desired and type(api.for_channel)=="function" then
        writer=api:for_channel("eink")
    end
    local mutate=desired and writer.add_to_shelf or writer.remove_from_shelf
    local sent,value=pcall(mutate,writer,id)
    local write_error=not sent and tostring(value) or nil
    if not desired and write_error and (write_error:find("[MiuReadShelfPreflight]",1,true)
        or write_error:find("E-Ink 来源暂不可用",1,true)) then
        -- Transport-level native cooldown is also a preflight block: no
        -- DELETE was dispatched. Offer authorization, not an upload retry.
        local authorization_error=write_error:find("[MiuReadShelfPreflight]",1,true)
            and write_error or "[MiuReadShelfAuthorization] E-Ink 书架管理凭据暂不可用，请重新授权"
        return {state="blocked",stage="credentials",present=present,error=authorization_error}
    end
    local read_error,last_present
    for _=1,2 do
        local ok,on_shelf=pcall(api.book_on_shelf,api,id)
        if ok and type(on_shelf)=="boolean" then last_present=on_shelf end
        if ok and on_shelf==desired then
            return {state="verified",stage="readback",already=false,present=on_shelf,
                write_error=write_error,read_error=read_error}
        end
        if not ok then read_error=tostring(on_shelf)
        elseif type(on_shelf)~="boolean" then read_error="shelf membership is unknown" end
    end
    return {state="unconfirmed",stage="readback",present=last_present,write_error=write_error,read_error=read_error,
        error=write_error or read_error or "云端尚未确认书架变更结果"}
end

return M
