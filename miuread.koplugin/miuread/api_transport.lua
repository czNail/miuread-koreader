-- Shared E-Ink/Web policy. A scoped operation can pin its route; independent
-- API calls start fresh. Mutations never cross routes after an uncertain send.
local Http=require("miuread.http")
local logger=require("logger")
local M={}; M.__index=M

function M.control_error(value)
    local text=tostring(value or "")
    return text:find("[MiuReadRateLimit]",1,true)
        or (type(Http.is_rate_limit_error)=="function" and Http.is_rate_limit_error(value))
        or text:find("__MIUREAD_HIBERNATE__",1,true)
        or text:lower():find("download cancelled",1,true)
end
function M.preference(store)
    local prefs=store and type(store.preferences)=="function" and store:preferences() or {}
    return prefs.api_transport or prefs.download_transport or "auto"
end
function M.new(store,options)
    options=options or {}
    local mode=options.channel or options.download_transport or M.preference(store)
    mode=mode=="web" and "web" or "auto"
    local authorized=store and type(store.auth)=="function"
        and require("miuread.shelf_client").credentials(store:auth() or {})
    local reason=mode=="web" and "manual_web" or options.fresh_context and "coordinate_source"
        or not authorized and "authorization_required" or "eink_preferred"
    return setmetatable({mode=mode,selected=reason=="eink_preferred" and "eink" or "web",reason=reason,
        web_chapters=0,eink_chapters=0,api_counts={eink={},web={}}},M)
end
function M:use_web(_,operation)
    self.selected,self.reason="web","eink_failed"
    logger.info("[MiuRead][API] fallback","operation=",operation or "unknown","channel=","web")
end
function M:invoke(name,native,web,options)
    if self.control_failure then error(self.control_failure,0) end
    options=options or {}
    local channel=options.web_only and "web" or self.selected
    if options.native_only and (channel~="eink" or not native) then
        error("[MiuReadCoordinateSource] E-Ink 批注坐标需要同源接口，未发送写入",0)
    end
    local phase=options.phase or name
    local function call(fn,selected)
        self.active_channel,self.active_phase=selected,phase
        local counts=self.api_counts[selected]
        counts[phase]=(counts[phase] or 0)+1
        local ok,a,b,c,d=pcall(fn)
        self.last_channel=selected
        if not ok and M.control_error(a) then self.control_failure=a end
        if not ok and type(self.note_rate_limit)=="function" then self:note_rate_limit(a) end
        self.active_channel,self.active_phase=nil,nil
        return ok,a,b,c,d
    end
    if channel=="eink" and native then
        local ok,a,b,c,d=call(native,"eink")
        if ok then return a,b,c,d end
        if M.control_error(a) then error(a,0) end
        if options.native_only then error(a,0) end
        -- Only a failure before sending a mutation can safely fall back.
        if options.write and not tostring(a):find("[MiuReadBeforeWrite]",1,true) then error(a,0) end
        self:use_web(a,name)
        if options.restart_on_fallback then error("[MiuReadTransportChanged]",0) end
    end
    local ok,a,b,c,d=call(web,"web")
    if not ok then error(a,0) end
    return a,b,c,d
end
return M
