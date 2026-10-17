-- Official WeRead generation, used only after an explicit reader action.
-- No local membership flag, free-trial activation or third-party translator.
local M={}
local function truth(value) return value==true or value==1 or value=="1" or value=="true" end
local function uid(chapter) return type(chapter)=="table" and tostring(chapter.chapterUid or chapter.uid or "") or "" end

function M.normalize_batch_size(value)
    if value=="all" then return value end
    value=tonumber(value)
    return (value==1 or value==5 or value==10 or value==20) and value or "auto"
end

-- Work inside the local EPUB's selected catalog. Directory pages do not use
-- the reading budget, and missing word counts still have a hard chapter cap.
-- Cached chapters count toward the reading window but need no generation.
function M.plan(chapters, current_uid, options)
    options=options or {}
    local batch=M.normalize_batch_size(options.batch_size)
    local found,words=batch=="all",0
    local current_found=false
    local plan={chapters={},pending={},words=0}
    for _,chapter in ipairs(chapters or {}) do
        local key=uid(chapter)
        if key==tostring(current_uid) then found=true; current_found=true end
        if found and chapter.structural~=true and not (options.structural_uids and options.structural_uids[key]) and key~="" then
            plan.chapters[#plan.chapters+1]=chapter
            words=words+math.max(0,tonumber(chapter.wordCount or chapter.word_count) or 0)
            if not (options.cached_uids and options.cached_uids[key]) then
                plan.pending[#plan.pending+1]=chapter
            end
            local count=#plan.chapters
            if (batch=="auto" and (count>=20 or (count>=3 and words>=8000)))
                or (type(batch)=="number" and count>=batch) then break end
        end
    end
    if not current_found then error("当前章节不在本地书籍范围内，原文件已保留。") end
    for _,chapter in ipairs(plan.chapters) do
        if uid(chapter)==tostring(current_uid) then plan.required_uid=uid(chapter); break end
    end
    -- A title/directory page has no translatable body. Use the first readable
    -- chapter in the window as the installation guard instead.
    plan.required_uid=plan.required_uid or (plan.chapters[1] and uid(plan.chapters[1]))
    plan.words=words
    return plan
end

-- Log schema and types only. A raw response may contain account/session data.
function M.describe_response(value,depth)
    depth=depth or 0
    if type(value)~="table" then return type(value) end
    if depth>=3 then return "table" end
    local parts,known={},{}
    for _,key in ipairs({"data","result","payload","curStatus","stopPoll","tips","errCode","errMsg","code","message"}) do
        if value[key]~=nil then
            known[key]=true
            parts[#parts+1]=key.."="..M.describe_response(value[key],depth+1)
        end
    end
    local other=0
    for key in pairs(value) do if not known[key] then other=other+1 end end
    if other>0 then parts[#parts+1]="other_fields="..other end
    return "table("..table.concat(parts,",")..")"
end

function M.parse_status(value)
    for _=1,5 do
        if type(value)~="table" then return nil end
        if value.curStatus~=nil or value.stopPoll~=nil or value.tips~=nil or next(value)==nil then return value end
        local nested
        for _,key in ipairs({"data","result","payload"}) do
            if type(value[key])=="table" then nested=value[key]; break end
        end
        if not nested then return nil end
        value=nested
    end
end

function M.friendly_error(error_value)
    local message=tostring(error_value or "")
    local lower=message:lower()
    if message:find("下载不完整，未生成新的 EPUB",1,true) then
        local expected,actual=message:match("必需内容：(%d+)"),message:match("已完整获取：(%d+)")
        local title=message:match("\n• ([^\r\n]-)：")
        local summary=expected and actual and ("已保存 "..actual.." / "..expected.." 章下载内容，仍有章节未完成。")
            or "仍有章节未完整下载。"
        if title then summary=summary.."\n未完成章节："..title.."。" end
        return summary.."\n原书和下载进度已保留，可从断点继续。"
    end
    if message:find("[MiuReadTranslationMemberRequired]",1,true)
        or message:find("仅限会员",1,true) or message:find("付费会员",1,true)
        or message:find("会员专属",1,true) or lower:find("membership required",1,true)
        or lower:find("paid member",1,true) then
        return "下载译文需要微信读书付费会员，请确认当前登录账号的会员状态。"
    end
    if message:find("[MiuReadTranslationTimeout]",1,true) then
        return "本章译文还在准备中，已保留下载进度，可以继续阅读原文并稍后重试。"
    end
    if message:find("[MiuReadTranslationContentPending]",1,true) then
        local title=message:match("%[MiuReadTranslationContentPending%]%s*《([^\r\n]-)》")
        return (title and ("《"..title.."》") or "").."译文暂未准备好，原书和下载进度已保留，继续下载时会重新确认本章。"
    end
    if message:find("[MiuReadTranslationUnsupported]",1,true)
        or message:find("暂不支持",1,true) or message:find("不支持翻译",1,true)
        or message:find("无法翻译",1,true) or message:find("翻译不可用",1,true)
        or lower:find("translation unsupported",1,true)
        or lower:find("translation not supported",1,true)
        or lower:find("translation unavailable",1,true)
        or lower:find("not available for this book",1,true) then
        return "当前书籍暂不支持微信读书官方翻译，原文可以继续阅读。"
    end
    return nil
end

local function authorize(api, book_id, options)
    local function check_cancel()
        if options.cancelled and options.cancelled() then error("download cancelled") end
    end
    check_cancel()
    local member=api:translation_member_summary(book_id)
    check_cancel()
    if type(member)~="table" or member.isPaying==nil then
        error("无法确认微信读书会员状态，请稍后重试。")
    end
    if not truth(member.isPaying) then error("[MiuReadTranslationMemberRequired]") end
    return check_cancel
end

local function prepare_chapter(api, book_id, chapters, current_uid, options)
    local now=options.now or os.time
    local wait=options.wait or function(seconds) require("socket").sleep(seconds) end
    local function check_cancel()
        if options.cancelled and options.cancelled() then error("download cancelled") end
    end
    check_cancel()
    local index
    for i,chapter in ipairs(chapters or {}) do if uid(chapter)==tostring(current_uid) then index=i; break end end
    if not index then error("微信读书目录中没有找到当前章节，原文件已保留。") end
    -- The official reader sends the catalog version, then polls until
    -- stopPoll. A non-zero version alone does not mean the job has finished.
    local current=chapters[index]
    local baseline=math.max(0,tonumber(current.translateVersion) or 0)
    local was_translated=truth(current.hasTranslated) or (tonumber(current.transWordCount) or 0)>0
    local read={{uid=current.chapterUid or current.uid,translateVersion=baseline}}
    if chapters[index+1] and options.include_next~=false then
        read[#read+1]={uid=chapters[index+1].chapterUid or chapters[index+1].uid,
            translateVersion=math.max(0,tonumber(chapters[index+1].translateVersion) or 0)}
    end
    local deadline=now()+math.max(2,math.min(120,tonumber(options.timeout) or 90))
    local logged_state
    while true do
        check_cancel()
        local raw_response=api:en_read(book_id,read[1].uid,read)
        check_cancel()
        local response=M.parse_status(raw_response)
        if not response then
            local summary=M.describe_response(raw_response)
            require("logger").warn("[MiuRead][Translation] unrecognized response schema",summary)
            error("暂时无法确认译文状态，原书和下载进度已保留，请稍后重试。")
        end
        local versions,current_seen={},false
        for _,status in ipairs(type(response.curStatus)=="table" and response.curStatus or {}) do
            local key=uid(status)
            if key==tostring(current_uid) then current_seen=true end
            if key~="" and (tonumber(status.translateVersion) or 0)>0 then versions[key]=tonumber(status.translateVersion) end
        end
        local version=versions[tostring(current_uid)]
        local stopped=truth(response.stopPoll)
        local tip=type(response.tips)=="string" and response.tips or ""
        if stopped and M.friendly_error(tip) then error(M.friendly_error(tip)) end
        local state=tostring(version)..":"..tostring(stopped)..":"..type(response.curStatus)
        if state~=logged_state then
            logged_state=state
            require("logger").info("[MiuRead][Translation] generation status","chapter=",tostring(current_uid),
                "catalog_version=",tostring(baseline),"server_version=",tostring(version),"previously_translated=",tostring(was_translated),
                "stop_poll=",tostring(stopped),"schema=",M.describe_response(raw_response))
        end
        -- curStatus is optional while work is in progress, and can contain
        -- interim versions. The official reader consumes it at stopPoll.
        -- An unchanged completed version still needs fetching when the local
        -- chapter has no translation; Reader checks the actual body before save.
        if stopped and not current_seen and baseline>0 then version=baseline end
        if stopped and version then
            local ready={[tostring(current_uid)]=version}
            for offset,item in ipairs(read) do
                local chapter=chapters[index+offset-1]
                local already=truth(chapter.hasTranslated) or (tonumber(chapter.transWordCount) or 0)>0
                local available=versions[tostring(item.uid)]
                if available and (available>item.translateVersion or (already and available>=item.translateVersion)) then
                    ready[tostring(item.uid)]=available
                end
            end
            return ready
        end
        if stopped then
            error(M.friendly_error(tip) or (tip~="" and tip or "微信读书已结束本次请求，但当前章译文尚未就绪。原文件已保留。"))
        end
        if now()>=deadline then error("[MiuReadTranslationTimeout]") end
        if options.progress then options.progress(tip~="" and tip or "正在等待微信读书生成当前章译文") end
        wait(2)
    end
end

function M.prepare(api, book_id, chapters, current_uid, options)
    options=options or {}
    authorize(api,book_id,options)
    local found=false
    for _,chapter in ipairs(chapters or {}) do if uid(chapter)==tostring(current_uid) then found=true; break end end
    if not found then error("微信读书目录中没有找到当前章节，原文件已保留。") end
    api:toggle_translate(book_id,true)
    return prepare_chapter(api,book_id,chapters,current_uid,options)
end

-- Keep the official current/next request shape. Unlike the opportunistic next
-- request, every missing chapter in this window gets its own completed poll.
-- A later generation timeout keeps the completed prefix; cancellation and
-- service errors still stop the transaction before the original is replaced.
function M.prepare_batch(api, book_id, chapters, current_uid, options)
    options=options or {}
    local plan=M.plan(chapters,current_uid,options)
    if not plan.required_uid then error("当前下载范围没有可翻译的正文章节。") end
    current_uid=plan.required_uid
    local whole_book=M.normalize_batch_size(options.batch_size)=="all"
    local ready,targets,indices={},{},{}
    for index,chapter in ipairs(chapters) do indices[uid(chapter)]=index end
    for _,chapter in ipairs(plan.pending) do
        local key=uid(chapter)
        targets[key]=true
        -- Persisted completed generation is distinct from installed text. It
        -- still requires a guarded content fetch before it can be displayed.
        local saved=options.ready_versions and tonumber(options.ready_versions[key])
        local baseline=math.max(0,tonumber(chapter.translateVersion) or 0)
        if saved and saved>0 and saved>=baseline then ready[key]=saved end
    end
    if #plan.pending==0 then return ready,plan end
    local check_cancel=authorize(api,book_id,options)
    api:toggle_translate(book_id,true)
    local now=options.now or os.time
    local deadline=not whole_book and (now()+300) or nil
    -- For the whole file, prepare the open chapter first, then the remaining
    -- chapters in catalog order. Never change the EPUB's actual chapter order.
    local order={}
    if whole_book and targets[tostring(current_uid)] then order[1]=chapters[indices[tostring(current_uid)]] end
    for _,chapter in ipairs(plan.pending) do
        if not whole_book or uid(chapter)~=tostring(current_uid) then order[#order+1]=chapter end
    end
    for _,chapter in ipairs(order) do
        local key=uid(chapter)
        local index=indices[key]
        if targets[key] and not ready[key] then
            check_cancel()
            local remaining=deadline and (deadline-now()) or 120
            if remaining<2 then
                if not ready[tostring(current_uid)] and not (options.cached_uids and options.cached_uids[tostring(current_uid)]) then
                    error("[MiuReadTranslationTimeout]")
                end
                plan.incomplete=true
                break
            end
            local completed=0
            for id in pairs(ready) do if targets[id] then completed=completed+1 end end
            local prefix="正在准备译文 · "..(completed+1).."/"..#plan.pending.." · "..tostring(chapter.title or key)
            if options.progress then options.progress(prefix,completed+1,#plan.pending) end
            local per_chapter={now=options.now,wait=options.wait,cancelled=options.cancelled,
                timeout=math.min(tonumber(options.timeout) or 90,remaining),
                include_next=chapters[index+1]~=nil and targets[uid(chapters[index+1])]==true and not ready[uid(chapters[index+1])],
                progress=function(message) if options.progress then options.progress(prefix.."\n"..message,completed+1,#plan.pending) end end}
            local ok,versions=pcall(prepare_chapter,api,book_id,chapters,key,per_chapter)
            if not ok then
                check_cancel()
                if (whole_book or next(ready)) and key~=tostring(current_uid) and tostring(versions):find("[MiuReadTranslationTimeout]",1,true)
                    and (ready[tostring(current_uid)] or (options.cached_uids and options.cached_uids[tostring(current_uid)])) then
                    plan.incomplete=true
                    if not whole_book then break end
                else
                    error(versions,0)
                end
            else
                local completed_versions={}
                for id,version in pairs(versions) do
                    if targets[id] then ready[id]=version; completed_versions[id]=version end
                end
                if options.on_ready then options.on_ready(completed_versions) end
            end
        end
    end
    check_cancel()
    return ready,plan
end

function M.content_ready(fragment)
    local analyzed,err=require("miuread.translation").analyze("<html><body>"..tostring(fragment or "").."</body></html>")
    return analyzed~=nil and analyzed.blocks>0,err
end

function M.is_content_pending(value)
    return tostring(value):find("[MiuReadTranslationContentPending]",1,true)~=nil
end

function M.content_pending_error(chapter)
    local title=tostring(chapter and (chapter.title or chapter.chapterUid or chapter.uid) or ""):gsub("[%c]"," ")
    return "[MiuReadTranslationContentPending]《"..title.."》"
end

function M.should_refresh(versions, chapter_uid)
    local target=type(versions)=="table" and tonumber(versions[tostring(chapter_uid)]) or nil
    -- The explicit request means the open local chapter has no usable
    -- translation. Fetch it even if metadata already reported the same
    -- version: generation status can precede the updated content shards.
    return target~=nil and target>0
end

function M.can_reuse_content(entry, version, fragment)
    local saved=type(entry)=="table" and tonumber(entry.translation_version)
    local target=tonumber(version)
    return saved~=nil and target~=nil and saved>=target and target>0 and M.content_ready(fragment)
end
return M
