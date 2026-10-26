-- Reader-facing translation states. Availability is based on installed text;
-- server generation and a staged EPUB are not yet available to the reader.
local M={}

function M.describe(profile,record,task)
    record=record or {}
    local translated,total,available={},0,0
    for _,chapter in ipairs(profile and profile.chapters or {}) do
        if chapter.blocks>0 then translated[tostring(chapter.chapter_uid)]=true end
    end
    local chapters=record.chapter_map or (profile and profile.chapters) or {}
    for _,chapter in ipairs(chapters) do
        if chapter.structural~=true then
            total=total+1
            if translated[tostring(chapter.uid or chapter.chapterUid or chapter.chapter_uid)] then available=available+1 end
        end
    end
    local limited=record.chapter_uid~=nil or record.partial_range==true or record.range_start_index~=nil
        or record.access_scope=="preview"
    local scope=limited and "这些章节的" or "整本"
    local out={total=total,available=available,limited=limited,
        subtitle="使用微信读书官方译文，下载需要付费会员",
        primary={label=(available>0 and "补齐" or "下载")..scope.."译文",value="下载时可以继续阅读",action="download"},
        more=total>1 and available<total}
    if limited then out.subtitle="译文下载仅包含本机已有的章节" end
    if total>0 and available>0 then out.subtitle=available.." / "..total.." 章译文可离线阅读" end
    if record.pending_install and record.translation_mode then
        out.kind="ready"
        out.subtitle="新译文已就绪，应用后保留当前位置"
        out.primary={label="应用译文",value="重新载入本书",action="apply",value_bold=true}
        out.more=false
    elseif record.pending_install then
        out.kind="book_update"
        out.subtitle="本书有更新等待应用"
        out.primary={label="查看书籍更新",value="先完成当前更新",action="manage"}
        out.more=false
    elseif task then
        local status=tostring(task.status or "active")
        if status=="failed" or status=="interrupted" then
            out.kind="interrupted"
            out.subtitle=task.error_kind=="authentication" and "登录失效，恢复登录后可继续"
                or (task.error_kind=="network" and "网络中断，已保留下载进度" or "下载未完成，已保留进度")
            out.primary={label="继续下载译文",value="从上次进度继续",action="retry"}
            local reason=require("miuread.translation_generation").friendly_error(task.error)
            if reason and (reason:find("付费会员",1,true) or reason:find("暂不支持",1,true)) then
                out.kind="unavailable"
                out.subtitle=reason:find("付费会员",1,true) and "下载译文需要微信读书付费会员" or "本书暂不支持微信读书官方译文"
                out.primary={label="查看下载说明",value="可以继续阅读原文",action="manage"}
            end
        elseif status=="queued" then
            out.kind="queued"
            out.subtitle="译文已加入下载队列"
            out.primary={label="查看下载进度",value="等待其他任务完成",action="manage"}
        elseif task.paused then
            out.kind="paused"
            out.subtitle="译文下载已暂停，进度已保留"
            out.primary={label="继续下载译文",value="在后台继续",action="resume"}
        else
            out.kind="downloading"
            out.subtitle="正在后台准备译文，可以继续阅读"
            local percent=tonumber(task.percent) or 0
            local current,total=tonumber(task.translation_current),tonumber(task.translation_total)
            local value=task.activity=="translation_wait" and (current and total and ("准备第 "..current.." / "..total.." 章") or "正在准备译文")
                or (percent>0 and ("已完成 "..math.floor(math.min(1,percent)*100).."%") or "正在准备")
            out.primary={label="查看下载进度",value=value,action="manage"}
        end
        out.more=false
    elseif total>0 and available==total then
        out.kind="complete"
        out.subtitle=limited and "已下载章节的译文均可离线阅读" or "整本译文已可离线阅读"
        out.primary={label="译文已下载",value=total.." 章",enabled=false}
        out.more=false
    else
        out.kind="idle"
    end
    return out
end

return M
