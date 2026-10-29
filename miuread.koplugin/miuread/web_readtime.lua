-- Reuse the established Web Reader context and fresh remote-position guard.
-- Web has no historical hour field: only the latest closed, recent window is
-- eligible. The controller preserves beta.8's end-of-reading Web write policy.
local M={}
function M.eligible(row,now,window)
    return window~=nil and row.window==window and row.start_time>=now-120
        and row.start_time+row.duration<=now
end
function M.send(auth,batch,before_dispatch,api)
    local Http=require("miuread.http")
    local started=os.time()
    -- Closing progress may already have advanced the cloud position. Obtain a
    -- new tuple through the primary Web API, then let the existing worker
    -- validate it against the catalog. Never echo an opening/Legacy GET cache.
    local ok,value=pcall(function()
        return api:web_progress(batch.book_id,{no_auth_recovery=true,timeout={5,10}})
    end)
    local anchor,kind
    if ok then
        local message
        anchor,message,kind=require("miuread.legacy.web_progress_wire").parse(value,batch.book_id)
        if not anchor then value=message end
    end
    if not anchor then
        local limited=Http.rate_limit_details(value)
        return {state="pending",dispatched=false,retry_after=limited and limited.wait_seconds,
            error=limited and "rate_limited" or (kind=="authentication" or Http.is_auth_error(value))
                and "authentication" or "web_position_unavailable"}
    end
    anchor.book_id,anchor.source,anchor.fetched_at=batch.book_id,"web_cookie",os.time()
    local result=require("miuread.legacy_adapter_worker").run{
        book_id=batch.book_id,book={book_id=batch.book_id},elapsed_seconds=batch.seconds,
        time_only=true,report_mode="reading_time_compat",allow_renewal=false,
        reading_time_session_id="session-"..tostring(started).."-outbox",
        cloud_anchor=anchor,
        cookies=auth.cookies or {},api_key=auth.api_key or "",
        wr_ticket=auth.wr_ticket or "",wr_wrpa=auth.wr_wrpa or "",
        before_dispatch=before_dispatch,
    }
    local limited=not result.accepted and Http.rate_limit_details(result.error)
    return {state=result.accepted and "confirmed" or (result.request_dispatched and "unknown" or "pending"),
        dispatched=result.request_dispatched==true,
        retry_after=limited and limited.wait_seconds,
        error=not result.accepted and (limited and "rate_limited" or result.error_kind=="authentication" and "authentication" or "web_request_failed") or nil}
end
return M
