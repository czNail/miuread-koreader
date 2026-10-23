-- One deterministic route per download run. Book content and services prefer E-Ink;
-- an ordinary Native failure pins the remaining run to Web. Rate limits,
-- cancellation and hibernation propagate without issuing a fallback request.
local U=require("miuread.util")
local Http=require("miuread.http")
local Protocol=require("miuread.protocol")
local logger=require("logger")
local M={}; M.__index=M
local FAILURE_STAGES={catalog="目录",chapter_download="章节包下载",refresh="客户端凭据续期",style="书籍样式",
    annotations="划线与想法",translation="译文准备",
    client_download="客户端请求",decode="章节包解码",images="章节图片"}
local FAILURE_FILES={"eink_client.lua","eink_crypto.lua","eink_archive.lua","reader.lua"}
-- Only fixed local messages and numeric status codes may be persisted. HTTP
-- errors and native library failures can contain response data or file paths.
local KNOWN_FAILURES={
    {"E-Ink 与 Web 目录版本不同","catalog_version","目录版本不一致","catalog"},
    {"E-Ink 未返回对应书籍目录","catalog_missing","未返回本书目录","catalog"},
    {"E-Ink 目录中不存在当前章节","chapter_missing","目录中没有当前章节","catalog"},
    {"E-Ink 目录未确认章节免费或已购买","chapter_access","目录未确认章节免费或已购买","catalog"},
    {"E-Ink 书籍格式暂不支持","book_format","书籍格式暂不支持","catalog"},
    {"E-Ink 书籍版本缺失","book_version","未返回书籍版本","catalog"},
    {"E-Ink 下载需要客户端授权","authorization","需要客户端授权","client_download"},
    {"E-Ink 未返回章节下载密钥","key_missing","未返回章节下载密钥","chapter_download"},
    {"E-Ink 账号标识无效","account_invalid","客户端账号标识无效","decode"},
    {"E-Ink 解密组件不可用","crypto_unavailable","设备解密组件不可用","decode"},
    {"E-Ink 解压组件不可用","inflate_unavailable","设备解压组件不可用","decode"},
    {"E-Ink 下载密钥","key_decode","章节下载密钥解码或校验失败","decode"},
    {"E-Ink ZIP 密码","zip_password","章节包密码校验失败","decode"},
    {"E-Ink ZIP","archive_invalid","章节包解压或完整性校验失败","decode"},
    {"E-Ink 章节包大小无效","archive_size","章节包大小无效","decode"},
    {"E-Ink 书籍样式未能获取","style_missing","书籍样式未能获取","style"},
    {"E-Ink 章节清单","chapter_manifest","章节文件清单无效或缺失正文","decode"},
    {"E-Ink 未返回唯一章节正文","body_missing","章节包中没有唯一可用正文","decode"},
    {"E-Ink 章节正文为空","body_empty","章节正文为空","decode"},
    {"无法读取 E-Ink 章节包","archive_read","设备无法读取章节包","decode"},
    {"E-Ink 图片格式无效","image_format","章节图片格式无效","images"},
    {"无法保存 E-Ink 章节图片","image_save","设备无法保存章节图片","images"},
    {"E-Ink 正文图片未完整获取","image_missing","章节图片未完整获取","images"},
    {"E-Ink 批注位置未能验证","annotation_alignment","批注位置未能验证","annotations"},
    {"E-Ink 划线响应不完整","annotation_underlines","划线响应不完整","annotations"},
    {"E-Ink 想法响应不完整","annotation_reviews","想法响应不完整","annotations"},
    {"E-Ink 会员响应不完整","translation_member","会员状态响应不完整","translation"},
    {"E-Ink 译文模式未能开启","translation_mode","译文模式切换未成功","translation"},
    {"E-Ink 译文状态响应无效","translation_status","译文状态响应无效","translation"},
    {"E-Ink 未返回译文正文","translation_body","章节包尚无可用译文","chapter_download"},
    {"客户端续期返回了其他账号","refresh_account","续期返回了其他账号","refresh"},
    {"登录账号或凭据已变更","auth_changed","登录账号或凭据已变更","refresh"},
    {"客户端续期凭证未保存","refresh_save","续期凭据未保存","refresh"},
    {"客户端授权未返回完整登录凭证","refresh_incomplete","未返回完整客户端凭据","refresh"},
}

local function control_error(value)
    local text=tostring(value)
    return text:find("__MIUREAD_HIBERNATE__",1,true)
        or text:lower():find("download cancelled",1,true)
        or (type(Http.is_rate_limit_error)=="function" and Http.is_rate_limit_error(value))
        or text:find("[MiuReadRateLimit]",1,true)
end
local function web_reason(reader,options,mode)
    if mode=="web" then return "manual_web" end
    if options.fresh_context then return "coordinate_source" end
    local store=reader.store or {}
    if type(store.auth)~="function" or not require("miuread.shelf_client").credentials(store:auth()) then return "authorization_required" end
end
function M.new(reader,options)
    options=options or {}
    local store=reader.store or {}
    local prefs=type(store.preferences)=="function" and store:preferences() or {}
    local mode=tostring(options.download_transport or prefs.download_transport or "auto")
    if mode~="web" then mode="auto" end
    local reason=web_reason(reader,options,mode)
    return setmetatable({reader=reader,mode=mode,selected=reason and "web" or "eink",
        reason=reason or "eink_preferred",web_chapters=0,eink_chapters=0,api_counts={eink={},web={}}},M)
end
function M:native()
    local reader=self.reader
    reader._eink_client=reader._eink_client or require("miuread.eink_client").new(reader.http,reader.store)
    reader._eink_client.keepalive=true
    reader._eink_client.before_request=function(stage)
        if type(self.checkpoint)=="function" then self.checkpoint(stage) end
    end
    return reader._eink_client
end
function M:use_web(value)
    self:note_eink_failure(value)
    self.selected,self.reason="web","eink_failed"
    logger.info("[MiuRead][Transport] fallback","channel=","web","reason=",self.failure.code)
    self.reader:cleanup_transient_images()
    if type(self.on_fallback)=="function" then self.on_fallback() end
end
function M:service(api)
    local owner=self
    local methods={underlines="annotations",readreviews="annotations",translation_member_summary="translation",
        toggle_translate="translation",en_read="translation"}
    return setmetatable({}, {__index=function(_,name)
        local stage=methods[name]
        if not stage then return function(_,...) return api[name](api,...) end end
        return function(_,...)
            local channel=owner.selected
            owner.active_channel,owner.active_phase=channel,stage
            if channel=="eink" then
                local native=owner:native()
                owner.api_counts.eink[stage]=(owner.api_counts.eink[stage] or 0)+1
                local ok,value=pcall(native[name],native,...)
                if ok then
                    owner.active_channel,owner.active_phase=nil,nil
                    return value
                end
                if control_error(value) then owner:note_rate_limit(value); error(value,0) end
                owner:use_web(value)
                -- An annotation source switch also requires a matching chapter
                -- body. Let Downloader restart this chapter before fetching Web.
                if stage=="annotations" then error("[MiuReadTransportChanged]",0) end
            end
            owner.active_channel,owner.active_phase="web",stage
            owner.api_counts.web[stage]=(owner.api_counts.web[stage] or 0)+1
            local ok,value=pcall(api[name],api,...)
            if not ok then owner:note_rate_limit(value); error(value,0) end
            owner.active_channel,owner.active_phase=nil,nil
            return value
        end
    end})
end
function M:configure(format)
    if self.selected=="eink" and format and format~="epub" and format~="txt" then
        self.selected,self.reason="web","unsupported_format"
    end
end
function M:restore(prior)
    -- A partial download must not hammer a failed Native route after a worker
    -- restart. This cannot grant Native access or override explicit Web mode.
    if self.selected=="eink" and type(prior)=="table" and prior.schema==2
        and prior.selected=="web" and type(prior.failure)=="table" then
        self.selected,self.reason="web","eink_failed"
        self.failure=U.copy(prior.failure)
    end
end
function M:activity(opt,channel)
    self.active_channel,self.active_phase=channel,"download"
    if type(opt.activity)=="function" then opt.activity("transport_download",{channel=channel}) end
end
function M:note_eink_failure(value)
    local text=tostring(value or "")
    local stage=text:match("native_stage=([%w_]+)")
    if not FAILURE_STAGES[stage] then stage=nil end
    local failure={code="unknown",message="未识别的客户端错误",stage=stage}
    for _,known in ipairs(KNOWN_FAILURES) do
        if text:find(known[1],1,true) then
            failure.code,failure.message,failure.stage=known[2],known[3],known[4]
            break
        end
    end
    if failure.code=="unknown" then
        local status=tonumber(text:match("HTTP (%d%d%d)"))
        local code=tonumber(text:match("error_code=(%-?%d+)"))
        local lower=text:lower()
        if status then failure.code,failure.message,failure.status="http_status","客户端请求被服务拒绝",status
        elseif code then failure.code,failure.message,failure.error_code="service_error","客户端服务返回错误",code
        elseif lower:find("network request failed",1,true) or lower:find("timed out",1,true)
            or lower:find("timeout",1,true) then failure.code,failure.message="network","客户端请求连接失败或超时" end
    end
    for _,file in ipairs(FAILURE_FILES) do
        local line=tonumber(text:match(file:gsub("%.","%%.")..":(%d+):"))
        if line then failure.file,failure.line=file,line; break end
    end
    self.failure=failure
    logger.info("[MiuRead][Transport] native failure","stage=",failure.stage or "unknown","reason=",failure.code,
        "status=",tostring(failure.status or failure.error_code or ""))
end
function M:note_rate_limit(value)
    if not tostring(value):find("[MiuReadRateLimit]",1,true) then return end
    if not self.stopped then
        self.stopped_channel,self.stopped_phase=self.active_channel,self.active_phase or "download"
    end
    self.reason="rate_limited"
    local text=tostring(value)
    self.limit_code=tonumber(text:match("error_code=(%-?%d+)")) or tonumber(text:match("HTTP (%d+)"))
    self.wait_seconds=tonumber(text:match("wait_seconds=(%d+)"))
    self.local_cooldown=text:find("[MiuReadLocalCooldown]",1,true)~=nil
    self.native_stage=text:match("native_stage=([%w_]+)")
    self.stopped=true
end

function M:_chapter_once(book,chapter,format,opt)
    local function web()
        self:activity(opt,"web")
        local a,b,c,d=self.reader:chapter(book,chapter,format,opt)
        self.web_chapters=self.web_chapters+1
        return a,b,c,d
    end
    if Protocol.is_mp(tostring(book.bookId or book.book_id or "")) then self.selected,self.reason="web","mp" end
    if self.selected=="web" or opt.fresh_context then return web() end
    self:native()
    self:activity(opt,"eink")
    local ok,a,b,c,d=pcall(self.reader.eink_chapter,self.reader,book,chapter,format,opt)
    if ok then self.eink_chapters=self.eink_chapters+1; return a,b,c,d end
    if control_error(a) then error(a,0) end
    self:use_web(a)
    return web()
end
function M:chapter(book,chapter,format,opt)
    local ok,a,b,c,d=pcall(self._chapter_once,self,book,chapter,format,opt or {})
    if not ok then self:note_rate_limit(a) end
    self.active_channel,self.active_phase=nil,nil
    if not ok then error(a,0) end
    return a,b,c,d
end
function M:result()
    return {schema=2,mode=self.mode,selected=self.selected,reason=self.reason,
        web_chapters=self.web_chapters,eink_chapters=self.eink_chapters,
        stopped=self.stopped,stopped_channel=self.stopped_channel,
        stopped_phase=self.stopped_phase,limit_code=self.limit_code,
        wait_seconds=self.wait_seconds,local_cooldown=self.local_cooldown,
        native_stage=self.native_stage,failure=self.failure,api_counts=U.copy(self.api_counts)}
end
function M.failure_summary(failure)
    if type(failure)~="table" then return "未识别的客户端错误" end
    local message="未识别的客户端错误"
    for _,known in ipairs(KNOWN_FAILURES) do if known[2]==failure.code then message=known[3]; break end end
    if failure.code=="http_status" then message="客户端请求被服务拒绝"
    elseif failure.code=="service_error" then message="客户端服务返回错误"
    elseif failure.code=="network" then message="客户端请求连接失败或超时" end
    message=(FAILURE_STAGES[failure.stage] and (FAILURE_STAGES[failure.stage].." · ") or "")..message
    if tonumber(failure.status) then message=message.."（HTTP "..tostring(tonumber(failure.status)).."）"
    elseif tonumber(failure.error_code) then message=message.."（代码 "..tostring(tonumber(failure.error_code)).."）" end
    for _,file in ipairs(FAILURE_FILES) do
        local line=tonumber(failure.line)
        if failure.file==file and line and line>0 and line<100000 then
            message=message.."（"..file..":"..tostring(math.floor(line)).."）"; break
        end
    end
    return message
end

function M.summary(value)
    -- Old experimental measurements are not production download results.
    if type(value)~="table" or value.schema~=2 then return nil end
    local reasons={eink_preferred="优先使用 E-Ink",manual_web="已选择 Web",
        annotations="划线与想法使用 Web",translation="译文使用 Web",prefetch="自动准备章节使用 Web",
        coordinate_source="精确位置校验使用 Web",unsupported_format="此格式使用 Web",mp="公众号使用 Web",
        authorization_required="未授权 E-Ink，使用 Web",eink_failed="E-Ink 未能完成，本次后续使用 Web"}
    local text=reasons[value.reason] or (value.selected=="eink" and "使用 E-Ink" or "使用 Web")
    if value.reason=="eink_failed" and value.failure then text=text.."；原因："..M.failure_summary(value.failure) end
    if value.reason=="rate_limited" then
        text=(value.stopped_channel=="eink" and "E-Ink" or value.stopped_channel=="web" and "Web" or "下载").."请求受限，已停止"
        if FAILURE_STAGES[value.native_stage] then text=text.."；步骤："..FAILURE_STAGES[value.native_stage] end
        if value.local_cooldown then text=text.."（本地冷却，本次未再次发送请求）" end
        if tonumber(value.limit_code) then text=text.."；限制代码 "..tostring(tonumber(value.limit_code)) end
        if tonumber(value.wait_seconds) then text=text.."；本地冷却剩余约 "..tostring(tonumber(value.wait_seconds)).." 秒" end
    end
    text=text..string.format("；本次获取 E-Ink %d 章 / Web %d 章",tonumber(value.eink_chapters) or 0,tonumber(value.web_chapters) or 0)
    for _,stage in ipairs({"annotations","translation"}) do
        local counts=value.api_counts or {}
        local native,web=tonumber((counts.eink or {})[stage]) or 0,tonumber((counts.web or {})[stage]) or 0
        if native+web>0 then text=text..string.format("；%s接口调用 E-Ink %d 次 / Web %d 次",FAILURE_STAGES[stage],native,web) end
    end
    return text
end
return M
