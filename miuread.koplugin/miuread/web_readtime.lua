-- Reuse the established Web Reader context and fresh remote-position guard.
-- Web has no historical hour field: only the latest closed, recent window is
-- eligible. The controller preserves beta.8's end-of-reading Web write policy.
local M={}
function M.eligible(row,now,window)
    return window~=nil and row.window==window and row.start_time>=now-120
        and row.start_time+row.duration<=now
end
function M.send(auth,batch,before_dispatch)
    local result=require("miuread.legacy_adapter_worker").run{
        book_id=batch.book_id,book={book_id=batch.book_id},elapsed_seconds=batch.seconds,
        time_only=true,report_mode="reading_time_compat",allow_renewal=false,
        cookies=auth.cookies or {},api_key=auth.api_key or "",
        wr_ticket=auth.wr_ticket or "",wr_wrpa=auth.wr_wrpa or "",
        before_dispatch=before_dispatch,
    }
    local Http=require("miuread.http")
    local limited=not result.accepted and Http.rate_limit_details(result.error)
    return {state=result.accepted and "confirmed" or (result.request_dispatched and "unknown" or "pending"),
        dispatched=result.request_dispatched==true,
        retry_after=limited and limited.wait_seconds,
        error=not result.accepted and (limited and "rate_limited" or result.error_kind=="authentication" and "authentication" or "web_request_failed") or nil}
end
return M
